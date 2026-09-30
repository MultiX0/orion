// Speech to text, for whichever provider the stt stage names: Fish's own API,
// or any OpenAI compatible multipart POST <base_url>/audio/transcriptions with
// file and model (on DeepInfra, Qwen3-ASR-1.7B is the best choice, see
// tools/cloud/asr_speed.py). Streaming while the user talks is Fish only; the
// others get the whole recording at once.
//
// The recording is up to 10 seconds of 16 kHz mono, 320 KB, and copying it
// into a multipart body would mean holding 640 KB. Instead the body is
// streamed: the preamble, the 44 byte WAV header built in memory, the PCM
// straight from the recording buffer, then the epilogue.
//
// No language field, on purpose. With "ar", whisper translates an English
// question into Arabic ("What is the capital of France?" comes back as
// "ما هو مدينة فرنسا؟") and Orion answers in the wrong language.

#include "cloud_private.h"

#include <string.h>

#include "cJSON.h"
#include "esp_log.h"

static const char *TAG = "cloud_asr";

#define BOUNDARY "----orion7f3a91c2e5"
#define SAMPLE_RATE 16000

typedef struct {
    char pre[224];
    size_t pre_len;
    char post[288];
    size_t post_len;
    uint8_t wav[44];
    const int16_t *pcm;
    size_t pcm_bytes;
} asr_body_t;

static esp_err_t write_all(esp_http_client_handle_t c, const char *p, size_t n)
{
    // In chunks, so a long recording yields while it uploads.
    while (n) {
        const size_t take = n > 4096 ? 4096 : n;
        const int w = esp_http_client_write(c, p, (int) take);
        if (w <= 0) return ESP_FAIL;
        p += w;
        n -= (size_t) w;
    }
    return ESP_OK;
}

static esp_err_t write_body(esp_http_client_handle_t c, void *ctx)
{
    const asr_body_t *b = ctx;
    if (write_all(c, b->pre, b->pre_len) != ESP_OK ||
        write_all(c, (const char *) b->wav, sizeof(b->wav)) != ESP_OK ||
        write_all(c, (const char *) b->pcm, b->pcm_bytes) != ESP_OK ||
        write_all(c, b->post, b->post_len) != ESP_OK) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

static esp_err_t parse_text(const char *body, char *out, size_t out_len)
{
    cJSON *root = cJSON_Parse(body);
    if (!root) return ESP_ERR_INVALID_RESPONSE;
    cJSON *text = cJSON_GetObjectItemCaseSensitive(root, "text");
    esp_err_t err = ESP_ERR_INVALID_RESPONSE;
    if (cJSON_IsString(text) && text->valuestring) {
        strlcpy(out, text->valuestring, out_len);
        err = ESP_OK;
    }
    cJSON_Delete(root);
    return err;
}

esp_err_t cloud_asr_run(const int16_t *pcm, size_t samples, char *out, size_t out_len,
                        uint32_t *connect_ms)
{
    if (!pcm || !samples || !out || out_len == 0) return ESP_ERR_INVALID_ARG;
    out[0] = '\0';
    const cloud_cfg_t *cfg = cloud_cfg();
    const cloud_stage_cfg_t *stt = &cfg->stt;
    const bool fish = stt->prov == CLOUD_PROV_FISH;

    asr_body_t *b = cloud_psram_alloc(sizeof(*b));
    if (!b) return ESP_ERR_NO_MEM;
    b->pcm = pcm;
    b->pcm_bytes = samples * sizeof(int16_t);
    cloud_wav_header(b->wav, b->pcm_bytes, SAMPLE_RATE);
    b->pre_len = (size_t) snprintf(b->pre, sizeof(b->pre),
        "--" BOUNDARY "\r\n"
        "Content-Disposition: form-data; name=\"%s\"; filename=\"speech.wav\"\r\n"
        "Content-Type: audio/wav\r\n\r\n", fish ? "audio" : "file");
    b->post_len = (size_t) snprintf(b->post, sizeof(b->post), "\r\n");
    if (!fish) {
        b->post_len += (size_t) snprintf(b->post + b->post_len, sizeof(b->post) - b->post_len,
            "--" BOUNDARY "\r\n"
            "Content-Disposition: form-data; name=\"model\"\r\n\r\n%s\r\n", stt->model);
    }
    b->post_len += (size_t) snprintf(b->post + b->post_len, sizeof(b->post) - b->post_len,
                                     "--" BOUNDARY "--\r\n");

    cloud_req_t req = {
        .url = stt->url,
        .method = HTTP_METHOD_POST,
        .auth = stt->auth[0] ? stt->auth : NULL,
        .content_type = "multipart/form-data; boundary=" BOUNDARY,
        .model = fish ? stt->model : NULL,
        .body_len = (int) (b->pre_len + sizeof(b->wav) + b->pcm_bytes + b->post_len),
        .write_body = write_body,
        .ctx = b,
    };
    const cloud_slot_t slot = CLOUD_SLOT_STT;
    const uint32_t t0 = cloud_now_ms();
    cloud_resp_t resp;
    esp_err_t err = cloud_send(slot, &req, &resp);
    free(b);
    if (err != ESP_OK) return err;
    if (connect_ms) *connect_ms = resp.connect_ms;

    char *body = NULL;
    size_t len = 0;
    cloud_read_all(&resp, &body, &len, 4096);
    const int status = resp.status;
    cloud_finish(slot, &resp, true);

    if (status != 200) {
        ESP_LOGE(TAG, "%s http %d: %.120s", stt->url, status, body ? body : "");
        free(body);
        return status == 402 ? ESP_ERR_NOT_ALLOWED : ESP_FAIL;
    }
    err = body ? parse_text(body, out, out_len) : ESP_ERR_NO_MEM;
    free(body);
    ESP_LOGI(TAG, "%s %.1f s audio -> %u ms (connect %u, upload and headers %u), %d chars",
             stt->model, (float) samples / SAMPLE_RATE,
             (unsigned) (cloud_now_ms() - t0), (unsigned) resp.connect_ms,
             (unsigned) resp.send_ms, (int) strlen(out));
    return err;
}

// ---------------------------------------------------------------------------
// Streaming: the recording goes up while the user is still talking, so when
// they stop, only the last 100 ms and the server's own time are left. Fish
// takes a chunked multipart body and a WAV header whose sizes say 0xFFFFFFFF,
// and returns the same words as fast as for a whole upload
// (tools/cloud/fish_asr_probe.py).
// ---------------------------------------------------------------------------

#define STREAM_CHUNK 3200           // 100 ms of 16 kHz audio per HTTP chunk
#define STREAM_HEAD  10             // room for "<hex size>\r\n" before the data

typedef struct {
    bool open;
    cloud_resp_t resp;
    uint8_t *buf;                   // PSRAM: head room, payload, "\r\n"
    size_t pending;
    size_t audio_bytes;
} asr_stream_t;

static asr_stream_t s_as;

static esp_err_t stream_flush(void)
{
    if (!s_as.pending) return ESP_OK;
    char head[STREAM_HEAD + 1];
    const int h = snprintf(head, sizeof(head), "%x\r\n", (unsigned) s_as.pending);
    uint8_t *start = s_as.buf + STREAM_HEAD - h;
    memcpy(start, head, (size_t) h);
    memcpy(s_as.buf + STREAM_HEAD + s_as.pending, "\r\n", 2);
    const int total = h + (int) s_as.pending + 2;
    s_as.pending = 0;
    return esp_http_client_write(s_as.resp.c, (const char *) start, total) == total ? ESP_OK : ESP_FAIL;
}

static esp_err_t stream_put(const void *data, size_t n)
{
    const uint8_t *p = data;
    while (n) {
        size_t take = STREAM_CHUNK - s_as.pending;
        if (take > n) take = n;
        memcpy(s_as.buf + STREAM_HEAD + s_as.pending, p, take);
        s_as.pending += take;
        p += take;
        n -= take;
        if (s_as.pending == STREAM_CHUNK && stream_flush() != ESP_OK) return ESP_FAIL;
    }
    return ESP_OK;
}

void cloud_asr_stream_abort(void)
{
    if (s_as.open) {
        cloud_finish(CLOUD_SLOT_STT, &s_as.resp, false);
        s_as.open = false;
    }
}

esp_err_t cloud_asr_stream_begin(void)
{
    const cloud_cfg_t *cfg = cloud_cfg();
    if (cfg->stt.prov != CLOUD_PROV_FISH) return ESP_ERR_NOT_SUPPORTED;   // streaming is Fish only
    if (s_as.open) cloud_asr_stream_abort();
    if (!s_as.buf) {
        s_as.buf = cloud_psram_alloc(STREAM_HEAD + STREAM_CHUNK + 2);
        if (!s_as.buf) return ESP_ERR_NO_MEM;
    }
    cloud_req_t req = {
        .url = cfg->stt.url,
        .method = HTTP_METHOD_POST,
        .auth = cfg->stt.auth[0] ? cfg->stt.auth : NULL,
        .content_type = "multipart/form-data; boundary=" BOUNDARY,
        .model = cfg->stt.model,
    };
    esp_err_t err = cloud_open_stream(CLOUD_SLOT_STT, &req, &s_as.resp);
    if (err != ESP_OK) return err;
    s_as.open = true;
    s_as.pending = 0;
    s_as.audio_bytes = 0;

    char pre[160];
    const int n = snprintf(pre, sizeof(pre),
        "--" BOUNDARY "\r\n"
        "Content-Disposition: form-data; name=\"audio\"; filename=\"speech.wav\"\r\n"
        "Content-Type: audio/wav\r\n\r\n");
    uint8_t wav[44];
    cloud_wav_header(wav, 0xFFFFFFFFu - 36, SAMPLE_RATE);   // length unknown yet
    if (stream_put(pre, (size_t) n) != ESP_OK || stream_put(wav, sizeof(wav)) != ESP_OK) {
        cloud_asr_stream_abort();
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t cloud_asr_stream_write(const int16_t *pcm, size_t samples)
{
    if (!s_as.open) return ESP_ERR_INVALID_STATE;
    const size_t bytes = samples * sizeof(int16_t);
    if (stream_put(pcm, bytes) != ESP_OK) {
        ESP_LOGW(TAG, "stream write failed after %u bytes of audio", (unsigned) s_as.audio_bytes);
        cloud_asr_stream_abort();
        return ESP_FAIL;
    }
    s_as.audio_bytes += bytes;
    return ESP_OK;
}

esp_err_t cloud_asr_stream_end(char *out, size_t out_len, uint32_t *connect_ms)
{
    if (!s_as.open) return ESP_ERR_INVALID_STATE;
    out[0] = '\0';
    const uint32_t t0 = cloud_now_ms();
    static const char post[] = "\r\n--" BOUNDARY "--\r\n";
    if (stream_put(post, sizeof(post) - 1) != ESP_OK || stream_flush() != ESP_OK ||
        esp_http_client_write(s_as.resp.c, "0\r\n\r\n", 5) != 5 ||
        cloud_stream_response(&s_as.resp) != ESP_OK) {
        cloud_asr_stream_abort();
        return ESP_FAIL;
    }
    if (connect_ms) *connect_ms = s_as.resp.connect_ms;

    char *body = NULL;
    size_t len = 0;
    cloud_read_all(&s_as.resp, &body, &len, 4096);
    const int status = s_as.resp.status;
    cloud_finish(CLOUD_SLOT_STT, &s_as.resp, true);
    s_as.open = false;

    if (status != 200) {
        ESP_LOGE(TAG, "fish stream http %d: %.120s", status, body ? body : "");
        free(body);
        return status == 402 ? ESP_ERR_NOT_ALLOWED : ESP_FAIL;
    }
    esp_err_t err = body ? parse_text(body, out, out_len) : ESP_ERR_NO_MEM;
    free(body);
    ESP_LOGI(TAG, "fish streamed %.1f s audio, %u ms from the last word to the text, %d chars",
             (float) s_as.audio_bytes / (SAMPLE_RATE * sizeof(int16_t)),
             (unsigned) (cloud_now_ms() - t0), (int) strlen(out));
    return err;
}
