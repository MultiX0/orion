// The RAM copy of config v2 and the write path. A write needs an internal
// stack (NVS runs with the flash cache off), so a caller on a PSRAM stack,
// the HTTP server, hands it to the default event loop task and waits.
#include "orion_settings.h"
#include "settings_priv.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_memory_utils.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "orion_audio.h"
#include "orion_cloud.h"

static const char *TAG = "orion_settings";

ESP_EVENT_DEFINE_BASE(ORION_SETTINGS_EVENT);

static settings_t *s_cur;
static void (*s_on_change)(void);

void orion_settings_on_change(void (*cb)(void))
{
    s_on_change = cb;
}

// Local time for the clock on screen and the time line the model gets.
static void apply_tz(const char *tz)
{
    setenv("TZ", tz[0] ? tz : "UTC0", 1);
    tzset();
    const time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    // Before the first SNTP sync the clock reads 1970 and there is no time to show.
    if (tm.tm_year + 1900 >= 2025) {
        ESP_LOGI(TAG, "time zone %s, local time %02d:%02d", tz[0] ? tz : "UTC0", tm.tm_hour, tm.tm_min);
    } else {
        ESP_LOGI(TAG, "time zone %s", tz[0] ? tz : "UTC0");
    }
}

static SemaphoreHandle_t s_lock;
static SemaphoreHandle_t s_done;
static esp_timer_handle_t s_retry;
static esp_err_t s_write_err;
static bool s_use_cloud;
static bool s_cloud_ok;

static void log_heap(const char *step)
{
    ESP_LOGI(TAG, "%s: heap int %u (largest %u) psram %u", step,
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
}

static bool on_internal_stack(void)
{
    int probe = 0;
    return esp_ptr_internal(&probe);
}

// The cloud refuses a reload during a turn; try again every second.
static void reload(void)
{
    // Setup mode runs before the cloud exists; its boot reads the new keys.
    // A board that booted without keys starts the cloud here.
    if (s_use_cloud && !s_cloud_ok) {
        s_cloud_ok = orion_cloud_init() == ESP_OK;
    }
    if (!s_cloud_ok) {
        ESP_LOGI(TAG, "cloud not running, the stored config applies when it starts");
        return;
    }
    esp_err_t err = orion_cloud_reload();
    if (err == ESP_ERR_INVALID_STATE) {
        ESP_LOGI(TAG, "cloud busy, reload after the turn");
        esp_timer_stop(s_retry);
        esp_timer_start_once(s_retry, 1000000);
    } else if (err != ESP_OK) {
        ESP_LOGW(TAG, "cloud reload: %s", esp_err_to_name(err));
    }
}

static void retry_cb(void *arg)
{
    (void) arg;
    esp_event_post(ORION_SETTINGS_EVENT, 1, NULL, 0, 0);
}

// Stores neu, then swaps it in. Runs on an internal stack.
static esp_err_t write(const settings_t *neu)
{
    esp_err_t err = settings_save(s_cur, neu);
    if (err == ESP_OK) {
        bool vol = s_cur->volume != neu->volume;
        bool tz = strcmp(s_cur->tz, neu->tz) != 0;
        xSemaphoreTake(s_lock, portMAX_DELAY);
        memcpy(s_cur, neu, sizeof(*s_cur));
        xSemaphoreGive(s_lock);
        if (vol) {
            orion_audio_set_volume((uint8_t) neu->volume);
        }
        if (tz) {
            apply_tz(neu->tz);
        }
        reload();
        if (s_on_change) {
            s_on_change();
        }
    }
    return err;
}

static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;
    if (id == 1) {
        reload();
        return;
    }
    s_write_err = write(*(settings_t **) data);
    xSemaphoreGive(s_done);
}

esp_err_t orion_settings_init(void)
{
    if (s_cur) {
        return ESP_OK;
    }
    s_cur = heap_caps_calloc(1, sizeof(*s_cur), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    s_lock = xSemaphoreCreateMutex();
    s_done = xSemaphoreCreateBinary();
    const esp_timer_create_args_t ta = { .callback = retry_cb, .name = "set_retry" };
    if (!s_cur || !s_lock || !s_done || esp_timer_create(&ta, &s_retry) != ESP_OK) {
        return ESP_ERR_NO_MEM;
    }
    settings_load(s_cur);
    apply_tz(s_cur->tz);
    esp_event_handler_register(ORION_SETTINGS_EVENT, ESP_EVENT_ANY_ID, on_event, NULL);
    ESP_LOGI(TAG, "loaded: llm %s, stt %s, tts %s", s_cur->llm.provider, s_cur->stt.provider,
             s_cur->tts.provider);
    return ESP_OK;
}

void orion_settings_use_cloud(void)
{
    s_use_cloud = true;
    s_cloud_ok = orion_cloud_init() == ESP_OK;
}

esp_err_t orion_settings_render(char *out, size_t out_len)
{
    if (!s_cur) {
        return ESP_ERR_INVALID_STATE;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    settings_render(s_cur, out, out_len);
    xSemaphoreGive(s_lock);
    return ESP_OK;
}

esp_err_t orion_settings_apply(const char *json, size_t len, char *out, size_t out_len)
{
    if (!s_cur) {
        return ESP_ERR_INVALID_STATE;
    }
    log_heap("apply start");
    settings_t *neu = heap_caps_malloc(sizeof(*neu), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!neu) {
        return ESP_ERR_NO_MEM;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    memcpy(neu, s_cur, sizeof(*neu));
    xSemaphoreGive(s_lock);

    char why[96];
    if (!settings_merge(neu, json, len, why, sizeof(why))) {
        snprintf(out, out_len, "{\"error\":\"invalid_config\",\"message\":\"%s\"}", why);
        ESP_LOGW(TAG, "rejected, nothing stored: %s", why);
        heap_caps_free(neu);
        return ESP_ERR_INVALID_ARG;
    }

    esp_err_t err;
    if (on_internal_stack()) {
        err = write(neu);
    } else {
        xSemaphoreTake(s_done, 0);
        err = esp_event_post(ORION_SETTINGS_EVENT, 0, &neu, sizeof(neu), pdMS_TO_TICKS(500));
        if (err == ESP_OK) {
            err = xSemaphoreTake(s_done, pdMS_TO_TICKS(5000)) == pdTRUE ? s_write_err
                                                                        : ESP_ERR_TIMEOUT;
        }
    }
    // A timed out write may still be reading neu; leak it rather than race.
    if (err != ESP_ERR_TIMEOUT) {
        memset(neu, 0, sizeof(*neu));
        heap_caps_free(neu);
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "store: %s", esp_err_to_name(err));
        return err;
    }
    log_heap("apply stored");
    return orion_settings_render(out, out_len);
}

esp_err_t orion_settings_test(const char *stage, char *out, size_t out_len)
{
    uint32_t ms = 0;
    char err[24] = "";
    if (strcmp(stage, "llm") != 0 && strcmp(stage, "stt") != 0 && strcmp(stage, "tts") != 0) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!s_cloud_ok) {
        snprintf(out, out_len, "{\"ok\":false,\"error\":\"unreachable\",\"message\":\"cloud not running\"}");
        return ESP_FAIL;
    }
    esp_err_t e = orion_cloud_test(stage, &ms, err, sizeof(err));
    if (e == ESP_OK) {
        snprintf(out, out_len, "{\"ok\":true,\"ms\":%u}", (unsigned) ms);
    } else if (strcmp(err, "busy") == 0) {
        snprintf(out, out_len, "{\"ok\":false,\"error\":\"busy\",\"message\":\"a turn is running\"}");
    } else {
        if (!err[0]) {
            strlcpy(err, "unreachable", sizeof(err));
        }
        snprintf(out, out_len, "{\"ok\":false,\"error\":\"%s\",\"message\":\"%s test failed after %u ms\"}",
                 err, stage, (unsigned) ms);
    }
    log_heap("test done");
    return e;
}

void orion_settings_basic(char *name, size_t name_len, int32_t *volume, bool *wake_word)
{
    if (!s_cur) {
        return;
    }
    xSemaphoreTake(s_lock, portMAX_DELAY);
    if (name) {
        strlcpy(name, s_cur->device_name, name_len);
    }
    if (volume) {
        *volume = s_cur->volume;
    }
    if (wake_word) {
        *wake_word = s_cur->wake_word;
    }
    xSemaphoreGive(s_lock);
}
