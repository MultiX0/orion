// Feature frontend: the TFLM microfrontend as packaged by kahrendt for
// microWakeWord. Every setting matches ESPHome's preprocessor_settings.h,
// which is what the models were trained with. Change nothing here without
// retraining.
#include "ww_priv.h"

#include <string.h>
#include "esp_log.h"
#include "frontend.h"
#include "frontend_util.h"

static const char *TAG = "ww_frontend";

#define SAMPLE_RATE 16000
#define WINDOW_MS   30

static struct FrontendConfig s_cfg;
static struct FrontendState s_state;
static bool s_ready;

esp_err_t ww_frontend_init(int step_ms)
{
    memset(&s_cfg, 0, sizeof(s_cfg));
    s_cfg.window.size_ms = WINDOW_MS;
    s_cfg.window.step_size_ms = step_ms;
    s_cfg.filterbank.num_channels = WW_FEATURES;
    s_cfg.filterbank.lower_band_limit = 125.0f;
    s_cfg.filterbank.upper_band_limit = 7500.0f;
    s_cfg.noise_reduction.smoothing_bits = 10;
    s_cfg.noise_reduction.even_smoothing = 0.025f;
    s_cfg.noise_reduction.odd_smoothing = 0.06f;
    s_cfg.noise_reduction.min_signal_remaining = 0.05f;
    s_cfg.pcan_gain_control.enable_pcan = 1;
    s_cfg.pcan_gain_control.strength = 0.95f;
    s_cfg.pcan_gain_control.offset = 80.0f;
    s_cfg.pcan_gain_control.gain_bits = 21;
    s_cfg.log_scale.enable_log = 1;
    s_cfg.log_scale.scale_shift = 6;

    if (s_ready) {
        FrontendFreeStateContents(&s_state);
        s_ready = false;
    }
    if (!FrontendPopulateState(&s_cfg, &s_state, SAMPLE_RATE)) {
        ESP_LOGE(TAG, "FrontendPopulateState failed");
        return ESP_FAIL;
    }
    s_ready = true;
    ESP_LOGI(TAG, "%d mel channels, %d ms window, %d ms step", WW_FEATURES, WINDOW_MS, step_ms);
    return ESP_OK;
}

bool ww_frontend_process(const int16_t *samples, size_t n, size_t *consumed, int8_t *out)
{
    struct FrontendOutput o = FrontendProcessSamples(&s_state, samples, n, consumed);
    if (o.size == 0) {
        return false;
    }
    // Same scaling as training: the frontend gives roughly 0 to 670, training
    // divided by 25.6 and quantized with scale 0.1016 and zero point -128.
    for (size_t i = 0; i < o.size && i < WW_FEATURES; i++) {
        int32_t v = ((int32_t) o.values[i] * 256 + 333) / 666 - 128;
        out[i] = (int8_t) (v < -128 ? -128 : (v > 127 ? 127 : v));
    }
    return true;
}

void ww_frontend_reset(void)
{
    if (s_ready) {
        FrontendReset(&s_state);
    }
}
