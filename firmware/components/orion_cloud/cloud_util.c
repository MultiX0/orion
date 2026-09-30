// Small helpers every file in orion_cloud uses.

#include "cloud_private.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"

static const char *TAG = "cloud_net";

uint32_t cloud_now_ms(void)
{
    return (uint32_t) (esp_timer_get_time() / 1000);
}

void *cloud_psram_alloc(size_t bytes)
{
    void *p = heap_caps_malloc(bytes, MALLOC_CAP_SPIRAM);
    return p ? p : malloc(bytes);
}

char *cloud_psram_strdup(const char *s)
{
    const size_t n = strlen(s) + 1;
    char *p = cloud_psram_alloc(n);
    if (p) {
        memcpy(p, s, n);
    }
    return p;
}

// 44 byte canonical RIFF header. Fish's own WAV headers carry placeholder
// sizes, so every header in this project is built here instead.
void cloud_wav_header(uint8_t hdr[44], size_t pcm_bytes, uint32_t rate)
{
    const uint16_t channels = 1, bits = 16, block = 2, pcm_tag = 1;
    const uint32_t byte_rate = rate * block;
    const uint32_t riff = 36 + (uint32_t) pcm_bytes;
    const uint32_t fmt_len = 16;
    const uint32_t data_len = (uint32_t) pcm_bytes;

    memcpy(hdr, "RIFF", 4);
    memcpy(hdr + 4, &riff, 4);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    memcpy(hdr + 16, &fmt_len, 4);
    memcpy(hdr + 20, &pcm_tag, 2);
    memcpy(hdr + 22, &channels, 2);
    memcpy(hdr + 24, &rate, 4);
    memcpy(hdr + 28, &byte_rate, 4);
    memcpy(hdr + 32, &block, 2);
    memcpy(hdr + 34, &bits, 2);
    memcpy(hdr + 36, "data", 4);
    memcpy(hdr + 40, &data_len, 4);
}

// Runs fn on a helper task with a 12 KB stack in PSRAM and waits for it. For
// callers whose own stack is too small for a TLS handshake: the console's REPL
// task has 4 KB, which asr_test would overflow. fn must never touch
// flash (NVS, SPIFFS): with its stack in PSRAM, disabling the cache asserts.
typedef struct {
    void (*fn)(void *arg);
    void *arg;
    SemaphoreHandle_t done;
} big_job_t;

static void big_stack_task(void *p)
{
    big_job_t *job = p;
    job->fn(job->arg);
    xSemaphoreGive(job->done);
    // Parked until the console deletes it: a WithCaps task that deletes itself
    // needs a clean up task, with a stack in internal RAM, to free it.
    vTaskSuspend(NULL);
}

bool cloud_run_big(void (*fn)(void *arg), void *arg)
{
    big_job_t job = { .fn = fn, .arg = arg, .done = xSemaphoreCreateBinary() };
    TaskHandle_t task = NULL;
    if (!job.done) return false;
    const bool started = xTaskCreatePinnedToCoreWithCaps(big_stack_task, "cloud_cmd",
                                                         12 * 1024, &job, 4, &task,
                                                         tskNO_AFFINITY,
                                                         MALLOC_CAP_SPIRAM) == pdPASS;
    if (started) {
        xSemaphoreTake(job.done, portMAX_DELAY);
        while (eTaskGetState(task) != eSuspended) {
            vTaskDelay(1);
        }
        vTaskDeleteWithCaps(task);
    }
    vSemaphoreDelete(job.done);
    return started;
}

// "[warm] Hello. [playful] Hi" -> "Hello. Hi". In place. A tag's trailing space
// goes with it, so no double spaces are left behind.
void cloud_strip_tags(char *text)
{
    char *w = text;
    for (const char *r = text; *r;) {
        if (*r == '[') {
            const char *end = strchr(r, ']');
            if (end) {
                r = end + 1;
                while (*r == ' ') r++;
                continue;
            }
        }
        *w++ = *r++;
    }
    *w = '\0';
}

esp_err_t cloud_read_all(cloud_resp_t *resp, char **out, size_t *len, size_t cap)
{
    *out = NULL;
    *len = 0;
    char *buf = cloud_psram_alloc(cap + 1);
    if (!buf) {
        return ESP_ERR_NO_MEM;
    }
    size_t got = 0;
    while (got < cap) {
        int n = cloud_read(resp, buf + got, (int) (cap - got));
        if (n <= 0) {
            break;
        }
        got += (size_t) n;
    }
    buf[got] = '\0';
    *out = buf;
    *len = got;
    return ESP_OK;
}

// HEAD to the stage's own endpoint. Servers answer it at once, usually 404 or
// 405 with Connection: keep-alive, which is all this needs: the session.
uint32_t cloud_prewarm_slot(cloud_slot_t slot)
{
    const cloud_stage_cfg_t *st = cloud_slot_stage(slot);
    if (!st->url[0]) {
        return 0;       // the PC slot while PC mode is off
    }
    cloud_req_t req = {
        .url = st->url,
        .method = HTTP_METHOD_HEAD,
        .auth = st->auth[0] ? st->auth : NULL,
    };
    cloud_resp_t resp;
    const uint32_t t0 = cloud_now_ms();
    if (cloud_send(slot, &req, &resp) != ESP_OK) {
        return 0;
    }
    cloud_finish(slot, &resp, true);
    const uint32_t ms = cloud_now_ms() - t0;
    static const char *names[] = { "llm", "stt", "tts", "pc", "phone" };
    ESP_LOGI(TAG, "prewarm %s %s: %u ms, %s", names[slot], st->origin, (unsigned) ms,
             resp.reused ? "was already warm" : "new session");
    return ms;
}
