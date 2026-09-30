// Private to orion_api.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "esp_http_server.h"

#define API_PORT        80
#define API_BEACON_PORT 7332

// Identity and time, orion_api.c
const char *api_device_id(void);
void api_device_name(char *out, size_t len);
const char *api_fw_version(void);
void api_iso_time(char *out, size_t len);
// Writes src into dst as a JSON string body (no quotes), escaping as needed.
void api_json_escape(char *dst, size_t len, const char *src);
// The fields of GET /api/state without the braces, shared with the ws state event.
void api_state_fields(char *out, size_t len);

// Token, orion_api.c
bool api_token_ok(const char *token);

// New credentials from POST /api/provision. Handed to the default event loop,
// whose task has an internal stack, because the HTTP task's stack is in PSRAM
// and a flash write must not run on it.
typedef struct {
    char ssid[33];
    char pass[65];
    char token[65];
    char name[33];
} api_provision_t;
esp_err_t api_post_provision(const api_provision_t *m);
// A token from POST /api/pair joins the paired list, on the event loop.
esp_err_t api_post_token(const char *token);

// Talk, say, stop and the history, api_talk.c
void api_talk_register(httpd_handle_t hd);
void api_history_turn_start(uint32_t turn, const char *source);
void api_history_text(uint32_t turn, bool user, const char *text);
void api_history_turn_end(uint32_t turn, uint32_t total_ms);
// The source the next turn.start reports: "app" or "app_snapshot" once after
// an app request, then "wake" again.
void api_set_source(const char *source);
const char *api_take_source(void);
uint32_t api_next_turn(void);

// Pairing with a code on the screen, api_pair.c
esp_err_t api_pair_handler(httpd_req_t *req);

// HTTP server, api_http.c
esp_err_t api_http_start(void);
void api_http_stop(void);
httpd_handle_t api_http_handle(void);
void api_send_json(httpd_req_t *req, const char *status, const char *json);
// Header X-Orion-Token, or ?token= for things a browser fetches. Answers 401
// itself and returns false when the token is missing or wrong.
bool api_authorized(httpd_req_t *req);

// Config, api_config.c
void api_config_register(httpd_handle_t hd);
void api_settings_changed(void);

// WebSocket, api_ws.c
esp_err_t api_ws_register(httpd_handle_t hd);
void api_ws_broadcast(const char *json);
// Starts and stops the link watch that drops silent apps.
void api_ws_links_start(void);
void api_ws_links_stop(void);

// Camera, api_cam.c
esp_err_t api_cam_register(httpd_handle_t hd);
// Ends a running MJPEG stream and waits for its task. Before httpd_stop.
void api_cam_stop(void);
