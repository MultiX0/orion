// Mic on I2S0 in PDM RX, speaker on I2S1 in standard TX. Not swappable: on the
// ESP32-S3 only port 0 can receive PDM.
//
// There is one microphone and no echo cancellation, so the mic is muted while
// the speaker plays. The playback calls handle that themselves.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#define ORION_AUDIO_SAMPLE_RATE 16000

// Starts the speaker clock, turns the audio path on, starts the mic task.
esp_err_t orion_audio_init(void);

// Playback. Open a stream, push chunks as they arrive, close it. The first
// and last 160 samples are faded, and the I2S clock keeps running between
// streams, which is what keeps the amp from popping. 16-bit signed mono PCM.
esp_err_t orion_audio_play_begin(uint32_t sample_rate);
// bytes 0 is a pause: the sound fades to silence and the next write fades in.
esp_err_t orion_audio_play_write(const void *pcm, size_t bytes);
esp_err_t orion_audio_play_end(void);
bool orion_audio_is_playing(void);

// Blocking helpers on top of the stream.
esp_err_t orion_audio_play_pcm(const int16_t *pcm, size_t samples, uint32_t sample_rate);
esp_err_t orion_audio_play_tone(uint32_t hz, uint32_t ms);

// Plays /assets/<name> from the assets partition. 16-bit PCM WAV, mono or
// stereo, any rate. Blocks until it finishes.
esp_err_t orion_audio_play_asset(const char *name);

// 0 to 100, square law, 100 is unity. Persisted in NVS under orion/volume.
void orion_audio_set_volume(uint8_t percent);
uint8_t orion_audio_get_volume(void);

// The loudness pipeline (high pass, presence lift, make-up gain, limiter at
// -1 dBFS, sustained power guard). On by default; off is plain volume.
void orion_audio_set_boost(bool on);
bool orion_audio_boost(void);

// Capture. The mic task runs continuously into a 4 s PSRAM ring so the wake
// word always has audio. Every consumer opens its own reader: a reader
// starts at now, never blocks another reader, and skips ahead if it falls
// more than half the ring behind.
typedef struct orion_mic_reader orion_mic_reader_t;

orion_mic_reader_t *orion_audio_mic_reader_open(void);
size_t orion_audio_mic_reader_read(orion_mic_reader_t *r, int16_t *dst,
                                   size_t max_samples, uint32_t wait_ms);
void orion_audio_mic_reader_close(orion_mic_reader_t *r);

// Convenience reader owned by the component, for quick tests.
size_t orion_audio_mic_read(int16_t *dst, size_t max_samples, uint32_t wait_ms);

// The newest samples the ring holds, ending now. Up to 4 s. For wake clips.
size_t orion_audio_mic_history(int16_t *dst, size_t samples);

esp_err_t orion_audio_mic_start(void);
esp_err_t orion_audio_mic_stop(void);

// 0.0 to 1.0, smoothed, for the listening animation.
float orion_audio_level(void);

// 0.0 to 1.0, smoothed, of what the speaker is playing. 0 when silent. Drives
// the speaking animation, since the mic is muted while Orion talks.
float orion_audio_out_level(void);

// RMS of the last 10 ms chunk, and the adaptive noise floor. The floor is
// measured over the first second after boot, then falls fast and rises slowly.
int32_t orion_audio_mic_rms(void);
int32_t orion_audio_noise_floor(void);

// Records until about 600 ms of silence follows speech, or max_ms elapses
// (10 s cap). Speech starts when two 20 ms frames exceed four times the noise
// floor. Keeps 300 ms before the speech and 400 ms after it. Allocates into
// PSRAM, caller frees with free(). ESP_ERR_NOT_FOUND if nobody spoke within
// 4 s, in which case *pcm is NULL.
esp_err_t orion_audio_record_utterance(int16_t **pcm, size_t *samples, uint32_t max_ms);

// The same, handing the audio to sink as it is recorded, from the moment
// speech starts: first everything kept so far (pre-roll or from the mark),
// then each new 20 ms frame, on the calling task. Return false to stop being
// called; the recording itself carries on and is returned as usual.
typedef bool (*orion_utterance_sink_t)(const int16_t *pcm, size_t samples, void *ctx);
esp_err_t orion_audio_record_utterance_stream(int16_t **pcm, size_t *samples, uint32_t max_ms,
                                              orion_utterance_sink_t sink, void *ctx);

// Marks now as where the next orion_audio_record_utterance() begins, instead
// of the moment it is called, so a question said straight after the wake word
// is not lost while the turn starts. Frames heard while the speaker plays, and
// 150 ms after, cannot start speech, so the wake chime itself is never taken
// for the user; speech that begins over it is kept from the mark.
void orion_audio_mark_utterance(void);

// orion_audio_play_asset with the mic left open, for the wake chime.
esp_err_t orion_audio_play_asset_mic_open(const char *name);

// Console commands: tone, wav, vol, assets, mic, micmon, loopback, record.
esp_err_t orion_audio_register_cmds(void);
