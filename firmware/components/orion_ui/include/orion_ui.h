// The 240x240 face of the product. main/ calls only what is in this header.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"
#include "orion_state.h"

typedef void (*ui_tap_cb_t)(void *ctx);

esp_err_t ui_init(void);

void ui_set_state(orion_state_t state);

// 0.0 to 1.0 mic level, drives the listening animation.
void ui_set_level(float level);

// UTF-8. Arabic is shaped and laid out right to left by LVGL.
void ui_set_text(const char *text);

void ui_on_tap(ui_tap_cb_t cb, void *ctx);

// Menu, network card. ssid and ip may be NULL when offline.
void ui_set_net_info(bool online, const char *ssid, const char *ip, int rssi);

// Menu, PC card. main fills it from the PC brain's health check.
void ui_set_pc_info(bool found, bool connected, const char *name, const char *ip);

// Menu, PC card refresh button. main re-runs its discovery when it fires.
void ui_on_pc_refresh(ui_tap_cb_t cb, void *ctx);

// Menu, camera card. main wires orion_camera in so orion_ui needs no
// dependency on it. get returns a JPEG in PSRAM, release frees that frame.
typedef esp_err_t (*ui_jpeg_get_t)(uint8_t **jpeg, size_t *len);
typedef void (*ui_jpeg_release_t)(void);
void ui_set_camera_source(ui_jpeg_get_t get, ui_jpeg_release_t release);

// Menu, camera card, preferred source: RGB565 straight from the sensor, no
// decode. Same shape as orion_camera_capture_preview, pass it directly. Wins
// over the JPEG source when both are set.
typedef esp_err_t (*ui_rgb565_get_t)(uint16_t w, uint16_t h, uint8_t **rgb565, size_t *len,
                                     uint16_t *out_w, uint16_t *out_h);
void ui_set_camera_preview(ui_rgb565_get_t get, ui_jpeg_release_t release);

// Bluetooth Wi-Fi setup, full screen over everything: open the Orion app and
// pick device_name, with the six digit code set large. Arabic first.
void ui_show_setup(const char *device_name, const char *code);

// Setup progress. detail is shown only on UI_SETUP_FAILED, e.g. "wrong password".
// UI_SETUP_DONE hides the setup view by itself after 2.5 s.
enum { UI_SETUP_WAITING = 0, UI_SETUP_CONNECTING, UI_SETUP_FAILED, UI_SETUP_DONE };
void ui_set_setup_status(int status, const char *detail);

void ui_hide_setup(void);

// Menu, network card "Wi-Fi setup" button. The menu closes, then cb runs.
void ui_on_wifi_setup(ui_tap_cb_t cb, void *ctx);

// Menu, reset card, after its second tap. main erases everything and restarts
// into setup mode.
void ui_on_reset(ui_tap_cb_t cb, void *ctx);

// Idle screen: which apps hold a live link to the board right now.
void ui_set_links(bool pc, bool phone);

// The idle line: "say Orion, or touch the screen", or only "touch the
// screen to talk" when the wake word is off.
void ui_set_wake_word(bool on);

// An app pairing over the LAN: the six digit code, full screen, for seconds.
// NULL code takes it down.
void ui_show_pair_code(const char *code, int seconds);

uint32_t ui_fps(void);
