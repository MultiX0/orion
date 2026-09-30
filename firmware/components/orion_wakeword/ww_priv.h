// Internal to orion_wakeword. C API on both sides so the C++ model wrapper
// stays contained in ww_model.cpp.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

#define WW_FEATURES 40

typedef struct {
    char wake_word[48];
    int version;
    float probability_cutoff;
    int feature_step_size;
    int sliding_window_size;
    int tensor_arena_size;
} ww_manifest_t;

// Maps the "model" partition and parses the header and JSON manifest written
// by tools/pack_model.py. The model pointer stays valid forever.
esp_err_t ww_partition_map(const uint8_t **model, size_t *model_len, ww_manifest_t *mf);

typedef struct ww_model ww_model_t;

ww_model_t *ww_model_create(const uint8_t *flatbuffer, size_t arena_size, uint8_t cutoff,
                            size_t window);
// Feeds one feature slice. Returns true when this slice triggered an inference,
// and then invoke_us holds how long it took.
bool ww_model_feed(ww_model_t *m, const int8_t *features, uint32_t *invoke_us);
// True once per inference whose sliding window mean crossed the cutoff.
bool ww_model_detected(ww_model_t *m, uint8_t *avg, uint8_t *max);
void ww_model_reset(ww_model_t *m);
void ww_model_set_cutoff(ww_model_t *m, uint8_t cutoff);
uint8_t ww_model_cutoff(ww_model_t *m);
size_t ww_model_arena_used(ww_model_t *m);
int ww_model_stride(ww_model_t *m);

esp_err_t ww_frontend_init(int step_ms);
// Consumes up to one step of samples. Returns true when out holds a new slice.
bool ww_frontend_process(const int16_t *samples, size_t n, size_t *consumed, int8_t *out);
void ww_frontend_reset(void);

void ww_clip_init(void);
void ww_clip_on_detection(uint8_t avg_prob);
esp_err_t ww_clip_dump_now(const char *name);

#ifdef __cplusplus
}
#endif
