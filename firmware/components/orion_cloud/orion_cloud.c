// The public face of the component: init, the conversation history, and the
// simple calls. The streamed reply lives in cloud_stream.c.
//
// Everything that outlives a request lives in PSRAM. Internal RAM is for Wi-Fi
// and the TLS handshakes, and it runs down to about 11 KB during a turn.

#include "orion_cloud.h"
#include "cloud_private.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "esp_log.h"
#include "esp_spiffs.h"

#include "orion_config.h"

static const char *TAG = "orion_cloud";

typedef struct {
    char *user;
    char *reply;
} turn_t;

static turn_t s_history[CLOUD_HISTORY_TURNS];
static int s_count;
static SemaphoreHandle_t s_hist_lock;
static char *s_prompt;
static orion_cloud_timing_t s_timing;
static bool s_ready;

static const char *FALLBACK_PROMPT =
    "You are Orion. Answer in one or two short spoken sentences, in the language "
    "the user spoke. Write numbers as words. No markdown, no emoji.";

orion_cloud_timing_t *cloud_timing(void)
{
    return &s_timing;
}

// Read once here, on the main task. SPIFFS reads flash, which the workers,
// with their stacks in PSRAM, must never do.
static void load_prompt(void)
{
    esp_vfs_spiffs_conf_t conf = {
        .base_path = ASSETS_BASE, .partition_label = "assets",
        .max_files = 4, .format_if_mount_failed = false,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "assets not mounted (%s), using the built in prompt", esp_err_to_name(err));
        return;
    }
    FILE *f = fopen(ASSETS_BASE "/system_prompt.txt", "rb");
    if (!f) {
        ESP_LOGW(TAG, "no system_prompt.txt in assets, using the built in prompt");
        return;
    }
    fseek(f, 0, SEEK_END);
    const long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len > 0 && len < 16384) {
        char *buf = cloud_psram_alloc((size_t) len + 1);
        if (buf && fread(buf, 1, (size_t) len, f) == (size_t) len) {
            buf[len] = '\0';
            s_prompt = buf;
            ESP_LOGI(TAG, "system prompt loaded, %ld bytes", len);
        } else {
            free(buf);
        }
    }
    fclose(f);
}

// Emotion tags are Fish only. The prompt file keeps its tag rules between a
// "<fish>" line and a "</fish>" line: with Fish the two marker lines go and the
// rules stay; with any other TTS the whole section goes, since that voice
// would read "[laugh]" out loud, and the line below asks for no brackets at
// all. The board strips any that slip through, from each piece and the screen.
static const char *NO_TAGS_LINE =
    "\n\nNever write anything in square brackets: the voice you speak through "
    "reads everything aloud.";

static char *s_prompt_eff;      // what the model gets: the file, cut for the TTS

// Past the end of a marker's line, CRLF or LF.
static const char *past_line(const char *p)
{
    if (*p == '\r') p++;
    if (*p == '\n') p++;
    return p;
}

// Copies base into out, which holds strlen(base) + 1, with the fish section
// kept or dropped. The marker lines themselves never reach the model.
void cloud_cut_fish_section(const char *base, bool fish, char *out)
{
    const char *open = strstr(base, "<fish>");
    const char *close = open ? strstr(open, "</fish>") : NULL;
    if (!close) {
        strcpy(out, base);
        return;
    }
    size_t w = (size_t) (open - base);
    memcpy(out, base, w);
    if (fish) {
        const char *body = past_line(open + strlen("<fish>"));
        memcpy(out + w, body, (size_t) (close - body));
        w += (size_t) (close - body);
    }
    const char *rest = past_line(close + strlen("</fish>"));
    if (!fish) rest = past_line(rest);      // no blank line left behind
    strcpy(out + w, rest);
}

void cloud_prompt_refresh(void)
{
    const char *base = s_prompt ? s_prompt : FALLBACK_PROMPT;
    const cloud_cfg_t *cfg = cloud_cfg();
    const bool fish = !cfg || cfg->tts.prov == CLOUD_PROV_FISH;
    free(s_prompt_eff);
    const size_t n = strlen(base) + strlen(NO_TAGS_LINE) + 1;
    s_prompt_eff = cloud_psram_alloc(n);
    if (s_prompt_eff) {
        cloud_cut_fish_section(base, fish, s_prompt_eff);
        if (!fish) {
            strlcat(s_prompt_eff, NO_TAGS_LINE, n);
        }
        ESP_LOGI(TAG, "prompt for %s voice, %u bytes", fish ? "Fish" : "a non-Fish",
                 (unsigned) strlen(s_prompt_eff));
    }
}

const char *cloud_system_prompt(void)
{
    if (s_prompt_eff) return s_prompt_eff;
    return s_prompt ? s_prompt : FALLBACK_PROMPT;
}

int cloud_history_count(void)
{
    return s_count;
}

const char *cloud_history_user(int i)
{
    return (i >= 0 && i < s_count && s_history[i].user) ? s_history[i].user : "";
}

const char *cloud_history_reply(int i)
{
    return (i >= 0 && i < s_count && s_history[i].reply) ? s_history[i].reply : "";
}

// Only ever called by the LLM worker, the same task that reads the history.
void cloud_history_push(const char *user, const char *reply)
{
    if (!user || !reply || !user[0] || !reply[0]) {
        return;
    }
    xSemaphoreTake(s_hist_lock, portMAX_DELAY);
    if (s_count == CLOUD_HISTORY_TURNS) {
        free(s_history[0].user);
        free(s_history[0].reply);
        memmove(&s_history[0], &s_history[1], sizeof(turn_t) * (CLOUD_HISTORY_TURNS - 1));
        s_count--;
    }
    s_history[s_count].user = cloud_psram_strdup(user);
    s_history[s_count].reply = cloud_psram_strdup(reply);
    s_count++;
    xSemaphoreGive(s_hist_lock);
}

void orion_cloud_history_reset(void)
{
    // Not while the LLM worker might be reading it to build a request.
    cloud_workers_idle(5000);
    xSemaphoreTake(s_hist_lock, portMAX_DELAY);
    for (int i = 0; i < s_count; i++) {
        free(s_history[i].user);
        free(s_history[i].reply);
        s_history[i].user = s_history[i].reply = NULL;
    }
    s_count = 0;
    xSemaphoreGive(s_hist_lock);
}

esp_err_t orion_cloud_init(void)
{
    if (s_ready) {
        return ESP_OK;
    }
    if (!orion_config_is_provisioned()) {
        ESP_LOGE(TAG, "not provisioned, run tools/cloud/provision.py");
        return ESP_ERR_NOT_FOUND;
    }
    s_hist_lock = xSemaphoreCreateMutex();
    if (!s_hist_lock) {
        return ESP_ERR_NO_MEM;
    }
    load_prompt();
    esp_err_t err = cloud_cfg_load();
    cloud_prompt_refresh();
    if (err == ESP_OK) err = cloud_net_init();
    if (err == ESP_OK) err = cloud_stream_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "init: %s", esp_err_to_name(err));
        return err;
    }
    s_ready = true;
    return ESP_OK;
}

esp_err_t orion_cloud_asr(const int16_t *pcm, size_t samples, char *out, size_t out_len)
{
    cloud_busy_enter();
    const uint32_t t0 = cloud_now_ms();
    uint32_t connect = 0;
    esp_err_t err = cloud_asr_run(pcm, samples, out, out_len, &connect);
    s_timing.asr_ms = cloud_now_ms() - t0;
    s_timing.asr_connect_ms = connect;
    cloud_busy_exit();
    return err;
}

// A stream counts as busy from a successful begin until it ends, either way,
// so a config reload cannot change the settings under an open upload.
static bool s_stream_busy;

static void stream_release(void)
{
    if (s_stream_busy) {
        s_stream_busy = false;
        cloud_busy_exit();
    }
}

esp_err_t orion_cloud_asr_stream_begin(void)
{
    stream_release();
    cloud_busy_enter();
    s_stream_busy = true;
    esp_err_t err = cloud_asr_stream_begin();
    if (err != ESP_OK) {
        stream_release();
    }
    return err;
}

esp_err_t orion_cloud_asr_stream_write(const int16_t *pcm, size_t samples)
{
    esp_err_t err = cloud_asr_stream_write(pcm, samples);
    if (err != ESP_OK) {
        stream_release();       // a failed write has already closed the stream
    }
    return err;
}

// asr_ms is from the last word, which is what the user waits for.
esp_err_t orion_cloud_asr_stream_end(char *out, size_t out_len)
{
    const uint32_t t0 = cloud_now_ms();
    uint32_t connect = 0;
    esp_err_t err = cloud_asr_stream_end(out, out_len, &connect);
    s_timing.asr_ms = cloud_now_ms() - t0;
    s_timing.asr_connect_ms = connect;
    stream_release();
    return err;
}

void orion_cloud_asr_stream_abort(void)
{
    cloud_asr_stream_abort();
    stream_release();
}

esp_err_t orion_cloud_reply(const char *text, char *reply, size_t reply_len,
                            orion_tts_sink_t sink, void *sink_ctx,
                            orion_reply_cb_t on_reply, void *reply_ctx)
{
    cloud_busy_enter();
    esp_err_t err = cloud_reply_stream(text, reply, reply_len, sink, sink_ctx,
                                       on_reply, reply_ctx);
    cloud_busy_exit();
    return err;
}

esp_err_t orion_cloud_llm(const char *text, char *out, size_t out_len)
{
    return orion_cloud_reply(text, out, out_len, NULL, NULL, NULL, NULL);
}

esp_err_t orion_cloud_tts(const char *text, orion_tts_sink_t sink, void *ctx)
{
    cloud_busy_enter();
    const uint32_t t0 = cloud_now_ms();
    uint32_t first = 0, connect = 0;
    esp_err_t err = cloud_tts_run(text, sink, ctx, &first, &connect);
    s_timing.tts_first_ms = first;
    s_timing.tts_connect_ms = connect;
    s_timing.tts_total_ms = cloud_now_ms() - t0;
    cloud_busy_exit();
    return err;
}

uint32_t orion_cloud_tts_rate(void)
{
    const cloud_cfg_t *c = cloud_cfg();
    return c ? c->tts_rate : 16000;
}

void orion_cloud_last_timing(orion_cloud_timing_t *out)
{
    if (out) {
        *out = s_timing;
    }
}
