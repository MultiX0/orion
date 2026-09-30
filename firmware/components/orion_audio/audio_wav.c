// WAV playback from the assets partition (SPIFFS, label "assets", at /assets).
#include "orion_audio.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "audio_priv.h"
#include "esp_check.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_spiffs.h"
#include "esp_timer.h"

static const char *TAG = "wav";

#define READ_SAMPLES 1024

typedef struct {
    uint16_t channels;
    uint32_t rate;
    uint16_t bits;
    uint32_t data_bytes;
} wav_info_t;

esp_err_t audio_assets_mount(void)
{
    static bool mounted;
    if (mounted) {
        return ESP_OK;
    }
    esp_vfs_spiffs_conf_t conf = {
        .base_path = "/assets",
        .partition_label = "assets",
        .max_files = 4,
        .format_if_mount_failed = false,
    };
    esp_err_t err = esp_vfs_spiffs_register(&conf);
    if (err == ESP_ERR_INVALID_STATE) {
        // Someone else mounted it first. Fine.
        err = ESP_OK;
    }
    ESP_RETURN_ON_ERROR(err, TAG, "mount assets");
    mounted = true;

    size_t total = 0, used = 0;
    esp_spiffs_info("assets", &total, &used);
    ESP_LOGI(TAG, "assets mounted at /assets, %u of %u bytes used", (unsigned) used, (unsigned) total);
    return ESP_OK;
}

static uint32_t le32(const uint8_t *p)
{
    return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t) p[3] << 24);
}

static uint16_t le16(const uint8_t *p)
{
    return p[0] | (p[1] << 8);
}

// Walks the RIFF chunks until the data chunk. Leaves the file at the first sample.
static esp_err_t read_header(FILE *f, wav_info_t *w)
{
    uint8_t h[12];
    ESP_RETURN_ON_FALSE(fread(h, 1, 12, f) == 12, ESP_ERR_INVALID_SIZE, TAG, "short header");
    ESP_RETURN_ON_FALSE(!memcmp(h, "RIFF", 4) && !memcmp(h + 8, "WAVE", 4), ESP_ERR_INVALID_ARG, TAG, "not a wav");

    memset(w, 0, sizeof(*w));
    uint8_t c[8];
    while (fread(c, 1, 8, f) == 8) {
        uint32_t size = le32(c + 4);
        if (!memcmp(c, "fmt ", 4)) {
            uint8_t fmt[16];
            ESP_RETURN_ON_FALSE(size >= 16 && fread(fmt, 1, 16, f) == 16, ESP_ERR_INVALID_SIZE, TAG, "fmt chunk");
            ESP_RETURN_ON_FALSE(le16(fmt) == 1, ESP_ERR_NOT_SUPPORTED, TAG, "not pcm");
            w->channels = le16(fmt + 2);
            w->rate = le32(fmt + 4);
            w->bits = le16(fmt + 14);
            fseek(f, (long) (size - 16 + (size & 1)), SEEK_CUR);
        } else if (!memcmp(c, "data", 4)) {
            w->data_bytes = size;
            ESP_RETURN_ON_FALSE(w->bits == 16, ESP_ERR_NOT_SUPPORTED, TAG, "%u bit, want 16", w->bits);
            ESP_RETURN_ON_FALSE(w->channels == 1 || w->channels == 2, ESP_ERR_NOT_SUPPORTED, TAG, "%u channels", w->channels);
            return ESP_OK;
        } else {
            fseek(f, (long) (size + (size & 1)), SEEK_CUR);
        }
    }
    return ESP_ERR_NOT_FOUND;
}

esp_err_t orion_audio_play_asset(const char *name)
{
    ESP_RETURN_ON_ERROR(audio_assets_mount(), TAG, "mount");

    char path[80];
    snprintf(path, sizeof(path), "/assets/%s", name);
    FILE *f = fopen(path, "rb");
    ESP_RETURN_ON_FALSE(f, ESP_ERR_NOT_FOUND, TAG, "no %s", path);

    wav_info_t w;
    esp_err_t err = read_header(f, &w);
    if (err != ESP_OK) {
        fclose(f);
        return err;
    }
    // Fish TTS writes 4294967076 in the size fields. Never trust them past
    // the end of the file.
    long first = ftell(f);
    fseek(f, 0, SEEK_END);
    long left = ftell(f) - first;
    fseek(f, first, SEEK_SET);
    if (left > 0 && w.data_bytes > (uint32_t) left) {
        ESP_LOGW(TAG, "%s: data chunk says %u bytes, file has %ld, using the file", name,
                 (unsigned) w.data_bytes, left);
        w.data_bytes = (uint32_t) left;
    }

    int16_t *buf = heap_caps_malloc(READ_SAMPLES * sizeof(int16_t), MALLOC_CAP_DEFAULT);
    if (!buf) {
        fclose(f);
        return ESP_ERR_NO_MEM;
    }

    int64_t t0 = esp_timer_get_time();
    err = orion_audio_play_begin(w.rate);
    bool began = err == ESP_OK;
    uint32_t remaining = w.data_bytes;
    while (err == ESP_OK && remaining >= sizeof(int16_t)) {
        size_t want = remaining / sizeof(int16_t);
        if (want > READ_SAMPLES) {
            want = READ_SAMPLES;
        }
        size_t n = fread(buf, sizeof(int16_t), want, f);
        if (n == 0) {
            break;
        }
        remaining -= n * sizeof(int16_t);
        if (w.channels == 2) {
            for (size_t i = 0; i < n / 2; i++) {
                buf[i] = (int16_t) (((int32_t) buf[2 * i] + buf[2 * i + 1]) / 2);
            }
            n /= 2;
        }
        err = orion_audio_play_write(buf, n * sizeof(int16_t));
    }
    // Only end what this call began. If play_begin timed out because another
    // task holds the speaker, is_playing() is true for that task, and ending
    // it here would give back a mutex this task never took:
    // xTaskPriorityDisinherit asserts and the board reboots mid turn.
    if (began) {
        orion_audio_play_end();
    }
    free(buf);
    fclose(f);

    uint32_t audio_ms = w.data_bytes / (w.channels * sizeof(int16_t)) * 1000 / w.rate;
    ESP_LOGI(TAG, "%s: %u Hz %u ch, %u ms of audio, took %u ms, %s", name, (unsigned) w.rate,
             w.channels, (unsigned) audio_ms, (unsigned) ((esp_timer_get_time() - t0) / 1000),
             esp_err_to_name(err));
    return err;
}

esp_err_t orion_audio_play_asset_mic_open(const char *name)
{
    audio_mic_hold_open(true);
    esp_err_t err = orion_audio_play_asset(name);
    audio_mic_hold_open(false);
    return err;
}
