// Config version 2 from docs/DEVICE_PROTOCOL.md: the llm, stt, tts and pc
// blocks, validated, merged field by field, stored through orion_config and
// rendered with every key masked. Shared by the LAN API (POST /api/config)
// and Bluetooth setup mode (the orion-config endpoint).
//
// The settings live in a RAM copy loaded once from NVS. Reads never touch
// flash, so a task whose stack is in PSRAM (the HTTP server) may render.
// Writes run on the default event loop task, which has an internal stack.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#define ORION_SETTINGS_CONFIG_VERSION 2
#define ORION_SETTINGS_PROVIDERS \
    "{\"llm\":[\"openai_compatible\"],\"stt\":[\"fish\",\"openai_compatible\"]," \
    "\"tts\":[\"fish\",\"openai_compatible\"]}"

// Loads the RAM copy. Idempotent. Call from a task with an internal stack
// (main, or the event loop) before anything else here.
esp_err_t orion_settings_init(void);

// From here on a stored change reloads the cloud stages (or starts them on a
// board that booted without keys). Called by the LAN API from main.
void orion_settings_use_cloud(void);

// The masked config, as GET /api/config returns it.
esp_err_t orion_settings_render(char *out, size_t out_len);

// A partial POST body. ESP_OK: out holds the merged, masked config and the
// change is stored; the cloud stages are told to reload. ESP_ERR_INVALID_ARG:
// out holds {"error":"invalid_config","message":...} and nothing was stored.
esp_err_t orion_settings_apply(const char *json, size_t len, char *out, size_t out_len);

// POST /api/config/test. out gets {"ok":true,"ms":n} or {"ok":false,...}.
// Blocks up to 30 s while a task with an internal stack makes the request.
esp_err_t orion_settings_test(const char *stage, char *out, size_t out_len);

// What /api/state and the beacon show. From the RAM copy.
void orion_settings_basic(char *name, size_t name_len, int32_t *volume, bool *wake_word);

// Called after a change is stored, on the event loop task: the wake word
// switch and the time zone take effect at once.
void orion_settings_on_change(void (*cb)(void));
