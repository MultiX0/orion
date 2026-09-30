// LAN API for the phone app: mDNS _orion._tcp, a UDP beacon on 7332, REST on
// port 80 behind X-Orion-Token, /ws state events, /capture and /stream.
// The contract is docs/DEVICE_PROTOCOL.md, which comes from the app project
// and is not edited here.
#pragma once

#include <stdbool.h>

#include "esp_err.h"
#include "orion_state.h"

// Registers with orion_net and serves whenever the station is up. The HTTP
// server task lives on a PSRAM stack; nothing it runs writes flash directly.
esp_err_t orion_api_start(void);
esp_err_t orion_api_stop(void);

// Called by the state machine on every transition. Pushed to every open /ws
// client as state, turn.start, tts.start, tts.end and turn.end events.
void orion_api_publish_state(orion_state_t state);
// role "user" is the transcript, "assistant" the reply.
void orion_api_publish_text(const char *role, const char *text);

// What the app asks the board to do (POST /api/talk, /api/talk/snapshot,
// /api/say, /api/stop). text is NULL for a plain talk. Called on the HTTP
// task; main posts to the state machine and says whether it took it: false
// means the board is busy with a turn.
typedef enum {
    ORION_API_TALK = 0,
    ORION_API_SNAPSHOT,
    ORION_API_SAY,
    ORION_API_STOP,
} orion_api_request_t;
typedef bool (*orion_api_request_cb_t)(orion_api_request_t what, const char *text);
void orion_api_on_request(orion_api_request_cb_t cb);

// A pairing code for the screen (POST /api/pair), shown for seconds, or NULL
// to take it down. Called on the HTTP server task.
typedef void (*orion_api_pair_cb_t)(const char *code, int seconds);
void orion_api_on_pair_code(orion_api_pair_cb_t cb);

// The apps holding a live /ws link right now. A link is dropped the moment its
// socket closes, or 15 s after its last frame (the apps ping every 5 s).
// phone_brain is the phone's own brain, "192.168.1.23:7331", with the token it
// paired with; empty when no phone offers one. Called on every change.
typedef struct {
    bool pc;
    bool phone;
    char phone_brain[48];
    char phone_token[65];
} orion_api_links_t;
typedef void (*orion_api_links_cb_t)(const orion_api_links_t *links);
void orion_api_on_links(orion_api_links_cb_t cb);
