// Speech to text, the language model and text to speech, for one turn.
// Every request verifies TLS against the ESP-IDF certificate bundle.
//
// One connection per host is kept alive between requests, and
// orion_cloud_prewarm opens them early, so a TLS handshake (1.5 to 2.4 s each
// on this chip, measured) is never on the path between the user finishing a
// sentence and Orion answering it.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

// Called for each PCM chunk, 16 bit mono little endian at
// orion_cloud_tts_rate(), as soon as it exists. May block, which is how
// playback paces the stream. Return false to stop: the rest of the turn is
// abandoned.
typedef bool (*orion_tts_sink_t)(const void *pcm, size_t bytes, void *ctx);

// Called once, on the caller's task, when the reply text is complete. The
// audio for it may still be playing. The text keeps its [tags]: stripping them
// for display is the screen's job.
typedef void (*orion_reply_cb_t)(const char *reply, void *ctx);

esp_err_t orion_cloud_init(void);

// Opens or refreshes the TLS connections every stage of a turn will use, on
// the cloud workers, and returns at once. Call it when the wake word fires.
void orion_cloud_prewarm(void);

esp_err_t orion_cloud_asr(const int16_t *pcm, size_t samples,
                          char *out, size_t out_len);

// The same, while the user is still talking: begin when speech starts, write
// each piece as it is recorded, end when it stops. Only the last piece and the
// server's own time are left after the last word. Fish only: begin returns
// ESP_ERR_NOT_SUPPORTED otherwise. A failed write or end leaves nothing open,
// and the caller still has the recording for orion_cloud_asr.
esp_err_t orion_cloud_asr_stream_begin(void);
esp_err_t orion_cloud_asr_stream_write(const int16_t *pcm, size_t samples);
esp_err_t orion_cloud_asr_stream_end(char *out, size_t out_len);
void orion_cloud_asr_stream_abort(void);

// The answer, streamed end to end. The model streams its reply; the reply is
// cut at the first clause and then at sentences; each piece is synthesized
// while the model is still writing the next; PCM reaches sink, on the calling
// task, as soon as there is any. Blocks until the last PCM has gone to sink.
// reply receives the full text, tags included. on_reply may be NULL.
// If the model calls the look tool, a photo is taken and the answer continues.
// Called now and then while a reply stream is alive, a PC or phone brain
// working through tools included: the turn's deadline counts from the last
// sign of life, not from the wake word. From the LLM worker task.
void orion_cloud_on_progress(void (*cb)(void));

// The next reply looks through the camera first, whatever the text says:
// the app's "ask about this". Any task.
void orion_cloud_look_next(void);

esp_err_t orion_cloud_reply(const char *text, char *reply, size_t reply_len,
                            orion_tts_sink_t sink, void *sink_ctx,
                            orion_reply_cb_t on_reply, void *reply_ctx);

// The text of the answer only, without speaking it.
esp_err_t orion_cloud_llm(const char *text, char *out, size_t out_len);

// The sample rate the TTS delivers, for orion_audio_play_begin: 32000 from
// Fish by default, 24000 from an OpenAI compatible server. It can change on
// orion_cloud_reload, so read it at the start of each reply.
uint32_t orion_cloud_tts_rate(void);

// One piece of text spoken as it is, on the calling task.
esp_err_t orion_cloud_tts(const char *text, orion_tts_sink_t sink, void *ctx);

void orion_cloud_history_reset(void);

// True while the PC brain answers (PC control on, and its last check passed).
// host gets "192.168.1.20:7331" when a PC is configured, "" otherwise.
bool orion_cloud_pc_online(char *host, size_t host_len);

// The phone's brain while it is linked, "192.168.1.23:7331" and the token it
// paired with; NULL or "" when it left. Any task.
void orion_cloud_set_phone_brain(const char *host_port, const char *token);

// Rereads the stored settings after the API changed them, and drops any kept
// alive connection whose host changed. Applies from the next turn, no reboot.
// Returns ESP_ERR_INVALID_STATE while a turn (or a test) is running: retry
// after it. Reads NVS, so call it from a task whose stack is in internal RAM.
esp_err_t orion_cloud_reload(void);

// The smallest real request for one stage with the stored settings: "llm" a
// one token completion, "stt" one second of silence, "tts" two words. ms gets
// the time taken. On failure err gets "http_<status>", "timeout" or
// "unreachable" (and "busy" while a turn runs, "invalid_stage" for a bad name).
// Blocks for the length of the request.
esp_err_t orion_cloud_test(const char *stage, uint32_t *ms, char *err, size_t err_len);

// Adds talk, asr_test, prewarm, cloud_status and cloud_selftest to the console.
esp_err_t orion_cloud_register_console(void);

// Filled in by the last turn, for the per turn log line.
typedef struct {
    uint32_t asr_ms;
    uint32_t asr_connect_ms;    // TLS setup inside asr_ms; 0 when the socket was warm
    uint32_t llm_ms;            // chat request to the last token
    uint32_t llm_first_ms;      // chat request to the first token
    uint32_t llm_connect_ms;
    uint32_t tts_first_ms;      // first piece handed to TTS to its first PCM
    uint32_t tts_connect_ms;
    uint32_t tts_total_ms;
    uint32_t first_audio_ms;    // orion_cloud_reply called to the first PCM at sink
    uint32_t gap_ms;            // time the speaker ran out between pieces
    uint8_t pieces;
    bool used_camera;
} orion_cloud_timing_t;

void orion_cloud_last_timing(orion_cloud_timing_t *out);
