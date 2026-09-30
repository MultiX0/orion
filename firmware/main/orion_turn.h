// One turn: record, transcribe, think, speak. Runs on its own task because
// the cloud calls block for seconds and the state machine must keep taking
// events, most importantly the 30 s deadline and a cancel.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"

typedef struct {
    uint32_t record_ms;
    uint32_t asr_ms;
    uint32_t llm_ms;
    uint32_t tts_first_ms;   // from tts request to the first chunk
    uint32_t tts_total_ms;
    uint32_t total_ms;       // from turn_begin to the last chunk
    bool used_camera;
} turn_timing_t;

esp_err_t turn_task_start(void);

// Starts a voice turn: record the mic, then ASR, LLM, TTS.
void turn_begin(void);

// Starts a text turn on the pending text: LLM and TTS only.
void turn_begin_text(void);

// POST /api/say: speaks the pending text through TTS, no model.
void turn_begin_say(void);

// Console path. Stores the text, the caller then posts EV_ASK.
void turn_set_pending_text(const char *text);

// Stops the current turn at the next stage boundary and aborts TTS streaming.
void turn_cancel(void);
bool turn_is_cancelled(void);

void turn_last_timing(turn_timing_t *out);
const char *turn_last_transcript(void);
const char *turn_last_reply(void);
