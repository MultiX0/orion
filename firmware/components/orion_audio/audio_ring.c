// The 4 s PSRAM ring the mic task writes into. Readers each keep their own
// position and are woken with a task notification, so the wake word and a
// recorder can both follow the same stream without copying it twice.
#include "orion_audio.h"

#include <string.h>
#include "audio_priv.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ring";

#define MAX_READERS 4

struct orion_mic_reader {
    bool used;
    uint32_t pos;
    uint32_t dropped;
    TaskHandle_t waiter;
};

static int16_t *s_ring;
static uint32_t s_size;
static volatile uint32_t s_wpos;
static struct orion_mic_reader s_readers[MAX_READERS];

esp_err_t audio_ring_init(size_t samples)
{
    s_ring = heap_caps_calloc(samples, sizeof(int16_t), MALLOC_CAP_SPIRAM);
    if (!s_ring) {
        ESP_LOGE(TAG, "%u samples in psram: no memory", (unsigned) samples);
        return ESP_ERR_NO_MEM;
    }
    s_size = samples;
    return ESP_OK;
}

void audio_ring_write(const int16_t *src, size_t n)
{
    uint32_t idx = s_wpos % s_size;
    size_t first = s_size - idx;
    if (first > n) {
        first = n;
    }
    memcpy(&s_ring[idx], src, first * sizeof(int16_t));
    if (n > first) {
        memcpy(s_ring, src + first, (n - first) * sizeof(int16_t));
    }
    s_wpos += n;

    for (int i = 0; i < MAX_READERS; i++) {
        TaskHandle_t w = s_readers[i].waiter;
        if (s_readers[i].used && w) {
            xTaskNotifyGive(w);
        }
    }
}

uint32_t audio_ring_dropped(void)
{
    uint32_t dropped = 0;
    for (int i = 0; i < MAX_READERS; i++) {
        if (s_readers[i].used) {
            dropped += s_readers[i].dropped;
        }
    }
    return dropped;
}

static size_t ring_copy(uint32_t from, int16_t *dst, size_t n)
{
    uint32_t idx = from % s_size;
    size_t first = s_size - idx;
    if (first > n) {
        first = n;
    }
    memcpy(dst, &s_ring[idx], first * sizeof(int16_t));
    if (n > first) {
        memcpy(dst + first, s_ring, (n - first) * sizeof(int16_t));
    }
    return n;
}

orion_mic_reader_t *orion_audio_mic_reader_open(void)
{
    for (int i = 0; i < MAX_READERS; i++) {
        if (!s_readers[i].used) {
            s_readers[i].pos = s_wpos;
            s_readers[i].dropped = 0;
            s_readers[i].waiter = NULL;
            s_readers[i].used = true;
            return &s_readers[i];
        }
    }
    ESP_LOGW(TAG, "no free reader");
    return NULL;
}

uint32_t audio_ring_wpos(void)
{
    return s_wpos;
}

orion_mic_reader_t *audio_mic_reader_open_at(uint32_t pos)
{
    orion_mic_reader_t *r = orion_audio_mic_reader_open();
    if (r && s_wpos - pos <= s_size / 2) {
        r->pos = pos;
    }
    return r;
}

void orion_audio_mic_reader_close(orion_mic_reader_t *r)
{
    if (r) {
        r->waiter = NULL;
        r->used = false;
    }
}

size_t orion_audio_mic_reader_read(orion_mic_reader_t *r, int16_t *dst, size_t max_samples,
                                   uint32_t wait_ms)
{
    if (!r || !s_ring || max_samples == 0) {
        return 0;
    }
    TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(wait_ms);

    while (true) {
        uint32_t avail = s_wpos - r->pos;
        if (avail > s_size) {
            // Fell behind. Keep the newest half so the writer cannot lap us mid copy.
            uint32_t keep = s_size / 2;
            r->dropped += avail - keep;
            r->pos = s_wpos - keep;
            avail = keep;
        }
        if (avail > 0) {
            size_t n = avail < max_samples ? avail : max_samples;
            ring_copy(r->pos, dst, n);
            r->pos += n;
            return n;
        }
        TickType_t now = xTaskGetTickCount();
        if ((int32_t) (deadline - now) <= 0) {
            return 0;
        }
        // Register before re-checking: a notification sent between the check
        // and the wait is not lost, it just makes the wait return at once.
        r->waiter = xTaskGetCurrentTaskHandle();
        if (s_wpos == r->pos) {
            ulTaskNotifyTake(pdTRUE, deadline - now);
        }
        r->waiter = NULL;
    }
}

size_t orion_audio_mic_history(int16_t *dst, size_t samples)
{
    if (!s_ring) {
        return 0;
    }
    uint32_t w = s_wpos;
    if (samples > s_size) {
        samples = s_size;
    }
    if (samples > w) {
        samples = w;
    }
    return ring_copy(w - samples, dst, samples);
}
