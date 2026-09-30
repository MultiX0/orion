// The one task that owns the assistant's state. Everything else, the wake
// word task, the button timer, the touch callback, the Wi-Fi handler and the
// turn worker, only ever posts events here.
#pragma once

#include <stdint.h>
#include "esp_err.h"
#include "orion_state.h"

typedef enum {
    EV_WAKE,        // wake word fired
    EV_BUTTON,      // short press on KEY1
    EV_TAP,         // touch anywhere on the idle screen
    EV_ASK,         // console: run a turn on typed text, see turn_set_pending_text
    EV_SPEECH_END,  // arg: ms of audio recorded
    EV_ASR_DONE,
    EV_LLM_DONE,
    EV_TTS_CHUNK,   // first audio arrived, the speaker is running
    EV_TTS_DONE,
    EV_ERROR,       // arg: orion_error_t
    EV_NET_UP,
    EV_NET_DOWN,
    EV_TIMEOUT,     // the 30 s turn deadline
    EV_CANCEL,      // long press, or a tap while speaking
    EV_PC_INFO,     // heartbeat: show whether the PC brain answers
    EV_SETTINGS,    // a stored setting changed: the wake word switch
    EV_SAY,         // the app: speak the pending text, no model
    EV_PROGRESS,    // the reply stream is alive: the deadline starts again
} orion_event_t;

typedef enum {
    ERR_NONE = 0,
    ERR_OFFLINE,    // no network when asked to listen
    ERR_NO_SPEECH,  // nobody spoke, or ASR heard nothing
    ERR_ASR,
    ERR_LLM,
    ERR_TTS,
    ERR_TIMEOUT,
} orion_error_t;

esp_err_t sm_start(void);

// Safe from any task, including the esp_timer task. Never blocks. Not for ISRs.
void sm_post(orion_event_t ev, int32_t arg);

orion_state_t sm_state(void);
uint32_t sm_turn_count(void);
