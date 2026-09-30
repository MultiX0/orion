// The pipeline task: mic ring -> frontend -> model -> sliding window -> callback.
#include "orion_wakeword.h"

#include <math.h>

#include <string.h>
// FreeRTOS.h must come first: esp_freertos_hooks.h pulls in portmacro.h on its
// own, and after that FreeRTOS.h finds the guard already set and never defines
// portYIELD_CORE, which is a hard #error on a dual core target.
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_check.h"
#include "esp_freertos_hooks.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "orion_audio.h"
#include "ww_priv.h"

static const char *TAG = "wakeword";

#define TASK_STACK    8192
#define TASK_PRIO     5
#define TASK_CORE     1
#define BUF_SAMPLES   480       // one 30 ms window

static const uint8_t *s_model_data;
static size_t s_model_len;
static ww_manifest_t s_mf;
static ww_model_t *s_model;
static orion_mic_reader_t *s_reader;
static TaskHandle_t s_task;
static volatile bool s_running;
static orion_wakeword_cb_t s_cb;
static void *s_cb_ctx;

static uint32_t s_steps, s_inferences, s_detections;
static uint64_t s_feature_us, s_invoke_us;
static uint32_t s_invoke_max;
static uint8_t s_last_avg, s_last_max;

// Idle hooks that refuse to sleep while a measurement runs, so the count
// rate tracks free CPU instead of tick rate.
static volatile uint32_t s_idle_count[2];
static volatile bool s_idle_spin;
static uint32_t s_idle_base[2];

static bool idle_hook_0(void)
{
    s_idle_count[0]++;
    return !s_idle_spin;
}

static bool idle_hook_1(void)
{
    s_idle_count[1]++;
    return !s_idle_spin;
}

static void measure_idle(uint32_t ms, uint32_t out[2])
{
    uint32_t c0 = s_idle_count[0], c1 = s_idle_count[1];
    s_idle_spin = true;
    vTaskDelay(pdMS_TO_TICKS(ms));
    s_idle_spin = false;
    out[0] = (s_idle_count[0] - c0) * 1000 / ms;
    out[1] = (s_idle_count[1] - c1) * 1000 / ms;
}

void orion_wakeword_cpu_load(uint32_t ms, float load[2])
{
    uint32_t now[2];
    measure_idle(ms, now);
    for (int i = 0; i < 2; i++) {
        load[i] = s_idle_base[i] ? 1.0f - (float) now[i] / (float) s_idle_base[i] : 0;
        load[i] = load[i] < 0 ? 0 : load[i];
    }
}

// Energy gate. A model trained without silence and room noise as negatives
// can fire in a silent room. A real "Orion" is loud against the noise floor,
// so a detection only counts if the last 1.5 s held sound well above it.
#define GATE_SLOTS      15      // 100 ms each
#define GATE_FLOOR_MULT 2
#define GATE_MIN_RMS    30      // silence reads 4 to 13, speech 40 to 180

static int32_t s_gate_peak[GATE_SLOTS];
static int s_gate_slot;
static int32_t s_gate_acc_max;
static size_t s_gate_acc_n;
static uint32_t s_gated;

static void gate_feed(const int16_t *x, size_t n)
{
    int64_t sum = 0, sq = 0;
    for (size_t i = 0; i < n; i++) {
        sum += x[i];
        sq += (int32_t) x[i] * x[i];
    }
    if (n == 0) {
        return;
    }
    float mean = (float) sum / (float) n;
    int32_t rms = (int32_t) sqrtf((float) sq / (float) n - mean * mean);
    if (rms > s_gate_acc_max) {
        s_gate_acc_max = rms;
    }
    s_gate_acc_n += n;
    if (s_gate_acc_n >= ORION_AUDIO_SAMPLE_RATE / 10) {
        s_gate_peak[s_gate_slot] = s_gate_acc_max;
        s_gate_slot = (s_gate_slot + 1) % GATE_SLOTS;
        s_gate_acc_max = 0;
        s_gate_acc_n = 0;
    }
}

static bool gate_open(int32_t *peak_out, int32_t *need_out)
{
    int32_t peak = s_gate_acc_max;
    for (int i = 0; i < GATE_SLOTS; i++) {
        peak = s_gate_peak[i] > peak ? s_gate_peak[i] : peak;
    }
    int32_t need = orion_audio_noise_floor() * GATE_FLOOR_MULT;
    need = need < GATE_MIN_RMS ? GATE_MIN_RMS : need;
    *peak_out = peak;
    *need_out = need;
    return peak >= need;
}

static void on_detection(uint8_t avg, uint8_t max)
{
    int32_t peak, need;
    if (!gate_open(&peak, &need)) {
        s_gated++;
        ESP_LOGI(TAG, "gated: model avg %u, but loudest 100 ms in 1.5 s was rms %d, need %d (#%u)",
                 avg, (int) peak, (int) need, (unsigned) s_gated);
        ww_model_reset(s_model);
        return;
    }
    s_detections++;
    s_last_avg = avg;
    s_last_max = max;
    ESP_LOGI(TAG, "DETECTED \"%s\" #%u avg %u max %u", s_mf.wake_word, (unsigned) s_detections, avg, max);
    ww_model_reset(s_model);
    ww_clip_on_detection(avg);
    if (s_cb) {
        s_cb(s_cb_ctx);
    }
}

static void process(int16_t *buf, size_t *have)
{
    int8_t features[WW_FEATURES];
    size_t used = 0;
    while (used < *have) {
        size_t consumed = 0;
        int64_t t0 = esp_timer_get_time();
        bool slice = ww_frontend_process(buf + used, *have - used, &consumed, features);
        s_feature_us += (uint64_t) (esp_timer_get_time() - t0);
        if (consumed == 0) {
            break;
        }
        used += consumed;
        if (!slice) {
            continue;
        }
        s_steps++;
        uint32_t inv = 0;
        if (ww_model_feed(s_model, features, &inv)) {
            s_inferences++;
            s_invoke_us += inv;
            if (inv > s_invoke_max) {
                s_invoke_max = inv;
            }
            uint8_t avg, max;
            if (ww_model_detected(s_model, &avg, &max)) {
                on_detection(avg, max);
            }
        }
    }
    memmove(buf, buf + used, (*have - used) * sizeof(int16_t));
    *have -= used;
}

static void ww_task(void *arg)
{
    int16_t buf[BUF_SAMPLES];
    size_t have = 0;
    while (true) {
        if (!s_running) {
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            have = 0;
            continue;
        }
        size_t n = orion_audio_mic_reader_read(s_reader, buf + have, BUF_SAMPLES - have, 100);
        if (n == 0) {
            continue;
        }
        gate_feed(buf + have, n);
        have += n;
        process(buf, &have);
    }
}

esp_err_t orion_wakeword_init(void)
{
    ESP_RETURN_ON_ERROR(ww_partition_map(&s_model_data, &s_model_len, &s_mf), TAG, "model partition");
    ESP_RETURN_ON_ERROR(ww_frontend_init(s_mf.feature_step_size), TAG, "frontend");

    uint8_t cutoff = (uint8_t) (s_mf.probability_cutoff * 255.0f);
    s_model = ww_model_create(s_model_data, s_mf.tensor_arena_size, cutoff, s_mf.sliding_window_size);
    ESP_RETURN_ON_FALSE(s_model, ESP_FAIL, TAG, "model load");

    ww_clip_init();

    esp_register_freertos_idle_hook_for_cpu(idle_hook_0, 0);
    esp_register_freertos_idle_hook_for_cpu(idle_hook_1, 1);
    measure_idle(500, s_idle_base);
    ESP_LOGI(TAG, "idle baseline %u / %u loops per second (core 0 / 1)",
             (unsigned) s_idle_base[0], (unsigned) s_idle_base[1]);

    if (xTaskCreatePinnedToCore(ww_task, "wakeword", TASK_STACK, NULL, TASK_PRIO, &s_task, TASK_CORE) != pdPASS) {
        return ESP_ERR_NO_MEM;
    }
    return ESP_OK;
}

esp_err_t orion_wakeword_start(orion_wakeword_cb_t cb, void *ctx)
{
    ESP_RETURN_ON_FALSE(s_task, ESP_ERR_INVALID_STATE, TAG, "not initialised");
    s_cb = cb;
    s_cb_ctx = ctx;
    if (s_running) {
        return ESP_OK;
    }
    // Jump to live audio and forget whatever the model was thinking.
    if (s_reader) {
        orion_audio_mic_reader_close(s_reader);
    }
    s_reader = orion_audio_mic_reader_open();
    ESP_RETURN_ON_FALSE(s_reader, ESP_ERR_NO_MEM, TAG, "mic reader");
    ww_frontend_reset();
    ww_model_reset(s_model);
    s_running = true;
    xTaskNotifyGive(s_task);
    ESP_LOGI(TAG, "listening for \"%s\"", s_mf.wake_word);
    return ESP_OK;
}

esp_err_t orion_wakeword_stop(void)
{
    s_running = false;
    return ESP_OK;
}

bool orion_wakeword_is_running(void)
{
    return s_running;
}

const char *orion_wakeword_phrase(void)
{
    return s_mf.wake_word;
}

uint32_t orion_wakeword_step_us(void)
{
    if (s_steps == 0) {
        return 0;
    }
    return (uint32_t) ((s_feature_us + s_invoke_us) / s_steps);
}

void orion_wakeword_get_stats(orion_wakeword_stats_t *out)
{
    memset(out, 0, sizeof(*out));
    out->steps = s_steps;
    out->inferences = s_inferences;
    out->detections = s_detections;
    out->feature_us_avg = s_steps ? (uint32_t) (s_feature_us / s_steps) : 0;
    out->invoke_us_avg = s_inferences ? (uint32_t) (s_invoke_us / s_inferences) : 0;
    out->invoke_us_max = s_invoke_max;
    out->last_avg_prob = s_last_avg;
    out->last_max_prob = s_last_max;
    if (s_model) {
        out->arena_used = ww_model_arena_used(s_model);
        out->arena_size = (s_mf.tensor_arena_size + 15) & ~15;
    }
}

ww_model_t *ww_current_model(void)
{
    return s_model;
}
