// microWakeWord model from the model partition, run with TFLite Micro.
// The pipeline is ESPHome's micro_wake_word: 40 mel features per 10 ms step,
// a streaming model that runs every third step, and a sliding window mean
// over the last few probabilities against the manifest's cutoff.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

// Called from the wake word task right after a detection. Keep it short.
typedef void (*orion_wakeword_cb_t)(void *ctx);

// Maps the model partition, parses the manifest, loads the model.
esp_err_t orion_wakeword_init(void);

// Start and stop are cheap: the task stays alive, stop just parks it and
// start jumps to live audio and forgets the model's old state.
esp_err_t orion_wakeword_start(orion_wakeword_cb_t cb, void *ctx);
esp_err_t orion_wakeword_stop(void);
bool orion_wakeword_is_running(void);

// From the manifest, for example "Okay Nabu".
const char *orion_wakeword_phrase(void);

// Average microseconds of CPU per 10 ms feature step, features plus the
// share of the model inference. 1000 here means 10 percent of one core.
uint32_t orion_wakeword_step_us(void);

typedef struct {
    uint32_t steps;
    uint32_t inferences;
    uint32_t detections;
    uint32_t feature_us_avg;
    uint32_t invoke_us_avg;
    uint32_t invoke_us_max;
    uint8_t last_avg_prob;      // 0..255 at the last detection
    uint8_t last_max_prob;
    size_t arena_used;
    size_t arena_size;
} orion_wakeword_stats_t;

void orion_wakeword_get_stats(orion_wakeword_stats_t *out);

// Whole-chip load over ms milliseconds, per core, 0.0 to 1.0. Measured
// against the idle rate sampled at init before the pipeline started.
void orion_wakeword_cpu_load(uint32_t ms, float load[2]);

// When on, every detection dumps 2 s of audio around it over serial as
// base64 between ORION_CLIP_BEGIN and ORION_CLIP_END, which
// tools/serial_capture.py turns into logs/wake_clips/*.wav. Persisted in NVS
// under orion/debug_clips.
void orion_wakeword_set_debug_clips(bool on);
bool orion_wakeword_debug_clips(void);

// Console command "ww" with sub commands: stats, start, stop, debug, clip, cutoff.
esp_err_t orion_wakeword_register_cmds(void);
