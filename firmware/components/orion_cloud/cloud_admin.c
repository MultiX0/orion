// The API's side of the cloud: rereading the settings after a config change,
// and the connection test for each stage. See docs/DEVICE_PROTOCOL.md,
// "Firmware interface between the API and the cloud stages".
//
// A gate keeps a reload from rewriting the settings under a turn that is
// using them. Every entry point that makes a request counts itself in; a
// reload goes ahead only when the count is zero and both workers are idle, and
// otherwise returns ESP_ERR_INVALID_STATE for the API to retry after the turn.

#include "cloud_private.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "esp_log.h"

static const char *TAG = "cloud_admin";

// A turn in progress is refused at once. A prewarm or heartbeat on the workers
// is not a turn: it finishes within a few seconds even on a fresh TLS session,
// so a reload or a test waits for it rather than report busy.
#define PREWARM_WAIT_MS 8000

static SemaphoreHandle_t s_gate;
static int s_busy;

static void gate_init(void)
{
    if (!s_gate) {
        s_gate = xSemaphoreCreateMutex();
    }
}

bool cloud_gate_lock(uint32_t wait_ms)
{
    gate_init();
    return xSemaphoreTake(s_gate, pdMS_TO_TICKS(wait_ms)) == pdTRUE;
}

void cloud_gate_unlock(void)
{
    xSemaphoreGive(s_gate);
}

bool cloud_busy_enter(void)
{
    gate_init();
    xSemaphoreTake(s_gate, portMAX_DELAY);
    s_busy++;
    xSemaphoreGive(s_gate);
    return true;
}

void cloud_busy_exit(void)
{
    xSemaphoreTake(s_gate, portMAX_DELAY);
    if (s_busy > 0) {
        s_busy--;
    }
    xSemaphoreGive(s_gate);
}

// Reads NVS, so the caller's stack must be in internal RAM: the API's httpd
// task qualifies, the cloud workers do not.
esp_err_t orion_cloud_reload(void)
{
    gate_init();
    xSemaphoreTake(s_gate, portMAX_DELAY);
    if (s_busy > 0 || !cloud_workers_idle(PREWARM_WAIT_MS)) {
        xSemaphoreGive(s_gate);
        return ESP_ERR_INVALID_STATE;
    }
    const uint32_t t0 = cloud_now_ms();
    esp_err_t err = cloud_cfg_load();
    cloud_prompt_refresh();
    // Only a stage whose host changed loses its warm connection.
    cloud_net_bind();
    xSemaphoreGive(s_gate);
    ESP_LOGI(TAG, "reloaded in %u ms: %s", (unsigned) (cloud_now_ms() - t0),
             esp_err_to_name(err));
    return err;
}

// ---- orion_cloud_test ----

typedef struct {
    cloud_slot_t slot;
    int stage;              // 0 llm, 1 stt, 2 tts
    esp_err_t err;
} test_job_t;

static bool discard_pcm(const void *pcm, size_t bytes, void *ctx)
{
    (void) pcm;
    size_t *total = ctx;
    *total += bytes;
    return true;
}

static void test_job(void *arg)
{
    test_job_t *j = arg;
    if (j->stage == 1) {
        // One second of silence: the smallest real transcription.
        int16_t *pcm = cloud_psram_alloc(16000 * sizeof(int16_t));
        if (!pcm) {
            j->err = ESP_ERR_NO_MEM;
            return;
        }
        memset(pcm, 0, 16000 * sizeof(int16_t));
        char text[64];
        j->err = cloud_asr_run(pcm, 16000, text, sizeof(text), NULL);
        free(pcm);
    } else if (j->stage == 2) {
        size_t total = 0;
        j->err = cloud_tts_run("Hello there", discard_pcm, &total, NULL, NULL);
        if (j->err == ESP_OK && total == 0) {
            j->err = ESP_FAIL;
        }
    } else {
        j->err = cloud_llm_ping();
    }
}

static void describe(cloud_slot_t slot, uint32_t ms, char *out, size_t out_len)
{
    int status = 0;
    esp_err_t net = ESP_OK;
    cloud_last_result(slot, &status, &net);
    if (status > 0 && status != 200) {
        snprintf(out, out_len, "http_%d", status);
    } else if (net == ESP_ERR_HTTP_EAGAIN || net == ESP_ERR_TIMEOUT || ms >= 25000) {
        strlcpy(out, "timeout", out_len);
    } else if (status == 200) {
        // The server said yes but the answer was not usable.
        snprintf(out, out_len, "bad_response");
    } else {
        strlcpy(out, "unreachable", out_len);
    }
}

esp_err_t orion_cloud_test(const char *stage, uint32_t *ms, char *err, size_t err_len)
{
    if (err && err_len) err[0] = '\0';
    if (ms) *ms = 0;
    test_job_t j = { .err = ESP_FAIL };
    if (stage && strcmp(stage, "llm") == 0) {
        j.stage = 0;
    } else if (stage && strcmp(stage, "stt") == 0) {
        j.stage = 1;
    } else if (stage && strcmp(stage, "tts") == 0) {
        j.stage = 2;
    } else {
        if (err) strlcpy(err, "invalid_stage", err_len);
        return ESP_ERR_INVALID_ARG;
    }
    j.slot = (cloud_slot_t) j.stage;

    gate_init();
    xSemaphoreTake(s_gate, portMAX_DELAY);
    if (s_busy > 0 || !cloud_workers_idle(PREWARM_WAIT_MS)) {
        xSemaphoreGive(s_gate);
        if (err) strlcpy(err, "busy", err_len);
        return ESP_ERR_INVALID_STATE;
    }
    s_busy++;
    xSemaphoreGive(s_gate);

    const uint32_t t0 = cloud_now_ms();
    cloud_run_big(test_job, &j);
    const uint32_t took = cloud_now_ms() - t0;
    cloud_busy_exit();

    char why[24] = "";
    if (j.err != ESP_OK) {
        describe(j.slot, took, why, sizeof(why));
    }
    if (ms) *ms = took;
    if (err) strlcpy(err, why, err_len);
    ESP_LOGI(TAG, "test %s: %s in %u ms %s", stage, j.err == ESP_OK ? "ok" : "failed",
             (unsigned) took, why);
    return j.err;
}
