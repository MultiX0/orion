// Debug clips: 2 s of mic audio around a detection, base64 over the console.
// tools/serial_capture.py looks for exactly this framing:
//   ORION_CLIP_BEGIN <name> <sample_rate>
//   <base64>
//   ORION_CLIP_END
// The payload goes out as one write() call so no log line can land inside it.
#include "orion_wakeword.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "orion_audio.h"
#include "ww_priv.h"

static const char *TAG = "ww_clip";

#define NVS_NAMESPACE   "orion"
#define NVS_KEY         "debug_clips"
#define CLIP_BEFORE_MS  1500
#define CLIP_AFTER_MS   500
#define CLIP_SAMPLES    ((CLIP_BEFORE_MS + CLIP_AFTER_MS) * ORION_AUDIO_SAMPLE_RATE / 1000)

static bool s_debug;
static uint32_t s_seq;

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static size_t base64(const uint8_t *in, size_t n, char *out)
{
    size_t o = 0;
    size_t i = 0;
    for (; i + 2 < n; i += 3) {
        uint32_t v = (in[i] << 16) | (in[i + 1] << 8) | in[i + 2];
        out[o++] = B64[(v >> 18) & 63];
        out[o++] = B64[(v >> 12) & 63];
        out[o++] = B64[(v >> 6) & 63];
        out[o++] = B64[v & 63];
    }
    if (i < n) {
        uint32_t v = in[i] << 16;
        if (i + 1 < n) {
            v |= in[i + 1] << 8;
        }
        out[o++] = B64[(v >> 18) & 63];
        out[o++] = B64[(v >> 12) & 63];
        out[o++] = i + 1 < n ? B64[(v >> 6) & 63] : '=';
        out[o++] = '=';
    }
    out[o] = 0;
    return o;
}

static bool nvs_read_flag(void)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) {
        return false;
    }
    bool on = false;
    uint8_t u8;
    int32_t i32;
    char str[8];
    size_t len = sizeof(str);
    if (nvs_get_u8(h, NVS_KEY, &u8) == ESP_OK) {
        on = u8 != 0;
    } else if (nvs_get_i32(h, NVS_KEY, &i32) == ESP_OK) {
        on = i32 != 0;
    } else if (nvs_get_str(h, NVS_KEY, str, &len) == ESP_OK) {
        on = str[0] == '1' || str[0] == 't' || str[0] == 'T' || str[0] == 'y';
    }
    nvs_close(h);
    return on;
}

static void nvs_write_flag(bool on)
{
    nvs_handle_t h;
    if (nvs_open(NVS_NAMESPACE, NVS_READWRITE, &h) != ESP_OK) {
        ESP_LOGW(TAG, "cannot open nvs to save the debug flag");
        return;
    }
    nvs_set_u8(h, NVS_KEY, on ? 1 : 0);
    nvs_commit(h);
    nvs_close(h);
}

void ww_clip_init(void)
{
    s_debug = nvs_read_flag();
    ESP_LOGI(TAG, "debug clips %s (nvs %s/%s)", s_debug ? "on" : "off", NVS_NAMESPACE, NVS_KEY);
}

void orion_wakeword_set_debug_clips(bool on)
{
    s_debug = on;
    nvs_write_flag(on);
}

bool orion_wakeword_debug_clips(void)
{
    return s_debug;
}

esp_err_t ww_clip_dump_now(const char *name)
{
    int16_t *pcm = heap_caps_malloc(CLIP_SAMPLES * sizeof(int16_t), MALLOC_CAP_SPIRAM);
    size_t b64_len = 4 * ((CLIP_SAMPLES * sizeof(int16_t) + 2) / 3) + 1;
    char *b64 = heap_caps_malloc(b64_len, MALLOC_CAP_SPIRAM);
    if (!pcm || !b64) {
        free(pcm);
        free(b64);
        return ESP_ERR_NO_MEM;
    }
    size_t n = orion_audio_mic_history(pcm, CLIP_SAMPLES);
    size_t len = base64((const uint8_t *) pcm, n * sizeof(int16_t), b64);

    printf("ORION_CLIP_BEGIN %s %d\n", name, ORION_AUDIO_SAMPLE_RATE);
    fflush(stdout);
    write(fileno(stdout), b64, len);
    printf("\nORION_CLIP_END\n");
    fflush(stdout);

    free(pcm);
    free(b64);
    ESP_LOGI(TAG, "clip %s: %u samples, %u base64 bytes", name, (unsigned) n, (unsigned) len);
    return ESP_OK;
}

static void clip_task(void *arg)
{
    uint8_t avg = (uint8_t) (uintptr_t) arg;
    // Let the half second after the detection land in the ring first.
    vTaskDelay(pdMS_TO_TICKS(CLIP_AFTER_MS));
    char name[48];
    snprintf(name, sizeof(name), "wake_%03u_p%u_%us", (unsigned) ++s_seq, avg,
             (unsigned) (esp_timer_get_time() / 1000000));
    ww_clip_dump_now(name);
    vTaskDelete(NULL);
}

void ww_clip_on_detection(uint8_t avg_prob)
{
    if (!s_debug) {
        return;
    }
    if (xTaskCreate(clip_task, "wwclip", 4096, (void *) (uintptr_t) avg_prob, 1, NULL) != pdPASS) {
        ESP_LOGW(TAG, "no task for the clip");
    }
}
