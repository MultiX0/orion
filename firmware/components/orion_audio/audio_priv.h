// Internal to orion_audio.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

esp_err_t audio_spk_init(void);

esp_err_t audio_mic_init(void);

// Playback holds the mic while the speaker is on. Muted chunks never reach
// the ring, and the first 100 ms after unmute are dropped too for the room tail.
void audio_mic_set_muted(bool muted);

// Keep the mic open while the speaker plays, so the ring records what the
// speaker put into the room. Self-tests, and the wake chime.
void audio_mic_hold_open(bool hold);

void audio_mic_stats(uint32_t *chunks, uint32_t *muted_chunks, uint32_t *dropped);

// Loudness pipeline, audio_dsp.c. begin() at every play_begin with the stream
// rate and the linear volume, process() on every chunk, latency() samples of
// zeros flushed at the end so the look-ahead delay line drains.
typedef struct {
    float in_peak, out_peak;      // 0..1 of full scale
    double in_sq, out_sq;         // sum of squares, rms = sqrt(sq / samples)
    uint32_t samples;
    uint32_t clipped;             // samples that hit the rails after the limiter
    float min_lim_gain;           // deepest limiter gain, 1.0 means it never worked
    float min_guard_db;
    uint32_t guard_trips;         // samples spent above the sustained power line
} audio_dsp_stats_t;

void audio_dsp_begin(uint32_t rate, float volume);
void audio_dsp_process(const int16_t *in, int16_t *out, size_t n);
size_t audio_dsp_latency(void);
void audio_dsp_set_enabled(bool on);
bool audio_dsp_enabled(void);
void audio_dsp_set_makeup_db(float db);
float audio_dsp_makeup_db(void);
void audio_dsp_set_presence_db(float db);
float audio_dsp_presence_db(void);
void audio_dsp_set_treble_db(float db);
// raw: the voice as it comes, times the volume. clean: that, without the
// bass a small speaker cannot use, 3 dB down and limited at -6 dBFS.
// boost: the full loudness chain, for a strong supply.
typedef enum { AUDIO_DSP_RAW, AUDIO_DSP_CLEAN, AUDIO_DSP_BOOST } audio_dsp_mode_t;
void audio_dsp_set_mode(audio_dsp_mode_t mode);
audio_dsp_mode_t audio_dsp_mode(void);
void audio_spk_set_silent(bool on);
bool audio_spk_silent(void);
esp_err_t audio_spk_set_capture(bool on);
void audio_spk_dump(void);
float audio_dsp_treble_db(void);
void audio_dsp_set_hpf_hz(float hz);
float audio_dsp_hpf_hz(void);
void audio_dsp_set_mud_db(float db);
float audio_dsp_mud_db(void);
float audio_dsp_guard_db(void);
void audio_dsp_get_stats(audio_dsp_stats_t *out);

// Test only: send the mono sample to both I2S slots (what playback uses) or
// the left one (the IDF default), to measure the 6 dB the amp's L/2 + R/2
// mix costs.
esp_err_t audio_spk_set_both_slots(bool both);
bool audio_spk_both_slots(void);

// Console command "spk". Lives next to the pipeline, registered by audio_cmds.c.
esp_err_t audio_spk_register_cmd(void);

// The PSRAM ring behind the readers in orion_audio.h. Only the mic task writes.
esp_err_t audio_ring_init(size_t samples);
void audio_ring_write(const int16_t *src, size_t n);
uint32_t audio_ring_dropped(void);

// The ring's write position, and a reader that starts there instead of at now.
// A position more than half the ring back is too old and opens at now.
uint32_t audio_ring_wpos(void);
struct orion_mic_reader *audio_mic_reader_open_at(uint32_t pos);

// Mounts the assets partition at /assets once. Safe to call repeatedly.
esp_err_t audio_assets_mount(void);
