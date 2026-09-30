// Text to speech, raw 16 bit mono PCM handed to the caller in chunks as it
// arrives, so the speaker starts before the sentence is finished. Fish gives
// 32 kHz by default; an OpenAI compatible server gives 24 kHz, and
// orion_cloud_tts_rate tells the caller which before the speaker opens.
//
// Two Fish settings here were measured, not guessed:
//   format "pcm"      wav responses carry a placeholder RIFF header whose size
//                     fields always read 4294967076, so we never ask for wav
//   latency "balanced"  the API default is "normal", which is four times slower
//                     to first audio. 2868 ms against 639 ms, measured.

#include "cloud_private.h"

#include <string.h>

#include "cloud_json.h"
#include "esp_log.h"

static const char *TAG = "cloud_tts";

#define TTS_CHUNK       2048

// What the board side needs to know about the level arriving on this socket:
// it is already hot, about -9.4 dBFS RMS with peaks at -0.3 dBFS, and peak
// level is dominated by generation variance rather than by anything we send.
// The same line regenerated varies 1.9 to 3.7 dB peak to peak. So the limiter
// has to expect occasional peaks that brush full scale, and there is no source
// side setting that prevents that. See build_body.

// The name is said the English way, "Orion", with the rest of the sentence in
// natural Arabic. No Arabic spelling comes out that way: plain "أوريون" loses
// its initial hamza, and the vowelled "أُورْيُون" keeps the hamza but still
// sounds Arabic. The Orion voice does say a Latin "Orion" the English way
// inside an Arabic sentence, so every Arabic spelling the model uses becomes
// the Latin word in the text sent to Fish. The screen keeps what the model
// wrote. This happens here rather than in the prompt, where it would only be
// a suggestion.
static const char *PRONOUNCE[][2] = {
    {"أوريون", "Orion"},
    {"اوريون", "Orion"},
    {"أورايون", "Orion"},
    {"اورايون", "Orion"},
};

#define PRONOUNCE_N (sizeof(PRONOUNCE) / sizeof(PRONOUNCE[0]))

// The replacement for a spelling that starts at p, and that spelling's length.
static const char *pronounce_at(const char *p, size_t *from_len)
{
    for (size_t i = 0; i < PRONOUNCE_N; i++) {
        const size_t len = strlen(PRONOUNCE[i][0]);
        if (strncmp(p, PRONOUNCE[i][0], len) == 0) {
            *from_len = len;
            return PRONOUNCE[i][1];
        }
    }
    return NULL;
}

// Returns either `text` unchanged or a new PSRAM buffer the caller must free.
static char *fix_pronunciation(const char *text, bool *allocated)
{
    *allocated = false;
    // A first pass sizes the result exactly: a replacement may be shorter or
    // longer than what it replaces.
    size_t size = 1, hits = 0, from_len = 0;
    for (const char *p = text; *p; ) {
        const char *to = pronounce_at(p, &from_len);
        if (to) {
            size += strlen(to);
            p += from_len;
            hits++;
        } else {
            size++;
            p++;
        }
    }
    if (!hits) {
        return (char *) text;
    }
    char *out = cloud_psram_alloc(size);
    if (!out) {
        return (char *) text;
    }
    size_t w = 0;
    for (const char *p = text; *p; ) {
        const char *to = pronounce_at(p, &from_len);
        if (to) {
            const size_t n = strlen(to);
            memcpy(out + w, to, n);
            w += n;
            p += from_len;
        } else {
            out[w++] = *p++;
        }
    }
    out[w] = '\0';
    *allocated = true;
    return out;
}

// Fish: tags stay in exactly as the model wrote them; they are performed, never
// read aloud, and each piece carries its own. The name fix above applies.
static bool build_fish(jw_t *w, const cloud_stage_cfg_t *st, const char *text)
{
    bool owned = false;
    char *spoken = fix_pronunciation(text, &owned);
    const bool ok = jw_init(w, 256 + jw_escaped_len(spoken) + strlen(st->voice));
    if (ok) {
        jw_raw(w, "{");
        jw_kv_str(w, "text", spoken);
        // No prosody object: sending one at all costs about 9 dB, and the
        // stream already arrives 0.3 dB from full scale.
        char fmt[80];
        snprintf(fmt, sizeof(fmt), ",\"format\":\"pcm\",\"sample_rate\":%u,\"latency\":\"balanced\"",
                 (unsigned) cloud_cfg()->tts_rate);
        jw_raw(w, fmt);
        if (st->voice[0]) {
            jw_raw(w, ",");
            jw_kv_str(w, "reference_id", st->voice);
        }
        jw_raw(w, "}");
    }
    if (owned) {
        free(spoken);
    }
    return ok && !w->overflow;
}

// OpenAI shape: {model, input, voice, response_format "pcm"}, which is 24 kHz,
// 16 bit, mono. Tags are Fish only, so they are taken out: any other voice
// would read "[warm]" aloud. Qwen/Qwen3-TTS on DeepInfra is the one model there
// that speaks Arabic back correctly (tools/cloud/openai_tts_probe.py).
static bool build_openai(jw_t *w, const cloud_stage_cfg_t *st, const char *text)
{
    char *plain = cloud_psram_strdup(text);
    if (!plain) {
        return false;
    }
    cloud_strip_tags(plain);
    const bool ok = jw_init(w, 256 + jw_escaped_len(plain) + strlen(st->model) + strlen(st->voice));
    if (ok) {
        jw_raw(w, "{");
        jw_kv_str(w, "model", st->model);
        jw_raw(w, ",");
        jw_kv_str(w, "input", plain);
        if (st->voice[0]) {
            jw_raw(w, ",");
            jw_kv_str(w, "voice", st->voice);
        }
        jw_raw(w, ",\"response_format\":\"pcm\"}");
    }
    free(plain);
    return ok && !w->overflow;
}

static esp_err_t write_body(esp_http_client_handle_t c, void *ctx)
{
    const jw_t *w = ctx;
    return esp_http_client_write(c, w->buf, (int) w->len) == (int) w->len ? ESP_OK : ESP_FAIL;
}

// Some servers send a WAV header even when asked for raw PCM (inworld on
// DeepInfra does). Returns how many bytes of chunk to skip: past "data" + size.
static size_t riff_skip(const char *chunk, size_t n)
{
    if (n < 12 || memcmp(chunk, "RIFF", 4) != 0) {
        return 0;
    }
    for (size_t i = 12; i + 8 <= n && i < 256; i++) {
        if (memcmp(chunk + i, "data", 4) == 0) {
            return i + 8;
        }
    }
    return 44;
}

esp_err_t cloud_tts_run(const char *text, orion_tts_sink_t sink, void *ctx,
                        uint32_t *first_ms, uint32_t *connect_ms)
{
    if (!text || !text[0] || !sink) {
        return ESP_ERR_INVALID_ARG;
    }
    const cloud_stage_cfg_t *st = &cloud_cfg()->tts;
    const bool fish = st->prov == CLOUD_PROV_FISH;
    jw_t w;
    if (!(fish ? build_fish(&w, st, text) : build_openai(&w, st, text))) {
        jw_free(&w);
        return ESP_ERR_NO_MEM;
    }
    cloud_req_t req = {
        .url = st->url, .method = HTTP_METHOD_POST, .auth = st->auth[0] ? st->auth : NULL,
        .content_type = "application/json", .model = fish ? st->model : NULL,
        .body_len = (int) w.len, .write_body = write_body, .ctx = &w,
    };
    const uint32_t t0 = cloud_now_ms();
    cloud_resp_t resp;
    esp_err_t err = cloud_send(CLOUD_SLOT_TTS, &req, &resp);
    jw_free(&w);
    if (err != ESP_OK) {
        return err;
    }
    if (connect_ms) {
        *connect_ms = resp.connect_ms;
    }
    if (resp.status != 200) {
        char *msg = NULL;
        size_t len = 0;
        cloud_read_all(&resp, &msg, &len, 512);
        ESP_LOGE(TAG, "tts http %d: %.120s", resp.status, msg ? msg : "");
        free(msg);
        cloud_finish(CLOUD_SLOT_TTS, &resp, false);
        return resp.status == 402 ? ESP_ERR_NOT_ALLOWED : ESP_FAIL;
    }

    char *chunk = cloud_psram_alloc(TTS_CHUNK);
    if (!chunk) {
        cloud_finish(CLOUD_SLOT_TTS, &resp, false);
        return ESP_ERR_NO_MEM;
    }
    uint32_t first = 0;
    size_t total = 0;
    bool aborted = false;
    while (!esp_http_client_is_complete_data_received(resp.c)) {
        const int n = cloud_read(&resp, chunk, TTS_CHUNK);
        if (n <= 0) {
            break;
        }
        const size_t skip = first ? 0 : riff_skip(chunk, (size_t) n);
        if (!first) {
            first = cloud_now_ms() - t0;
        }
        if ((size_t) n <= skip) {
            continue;
        }
        total += (size_t) n - skip;
        if (!sink(chunk + skip, (size_t) n - skip, ctx)) {
            aborted = true;
            break;
        }
    }
    free(chunk);
    // An abandoned stream still has audio on the socket, so it is not reused.
    cloud_finish(CLOUD_SLOT_TTS, &resp, !aborted);

    if (first_ms) {
        *first_ms = first;
    }
    const uint32_t rate = cloud_cfg()->tts_rate;
    ESP_LOGI(TAG, "%s %d chars -> %.1f s audio at %u Hz, connect %u, first %u, total %u ms%s",
             st->model, (int) strlen(text), (float) total / 2.0f / rate, (unsigned) rate,
             (unsigned) resp.connect_ms, (unsigned) first,
             (unsigned) (cloud_now_ms() - t0), aborted ? ", aborted" : "");
    return total ? ESP_OK : ESP_FAIL;
}
