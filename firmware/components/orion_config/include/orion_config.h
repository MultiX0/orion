// Typed reads of the NVS keys that tools/cloud/provision.py writes from .env.
// Secrets live here and nowhere else. They are never compiled into the binary.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

#define ORION_CFG_NAMESPACE     "orion"

#define ORION_CFG_WIFI_SSID     "wifi_ssid"
#define ORION_CFG_WIFI_PASS     "wifi_pass"
#define ORION_CFG_FISH_KEY      "fish_key"
#define ORION_CFG_FISH_VOICE    "fish_voice"
#define ORION_CFG_DEEPINFRA_KEY "di_key"
#define ORION_CFG_LLM_MODEL     "llm_model"
#define ORION_CFG_WAKE_PHRASE   "wake_phrase"
#define ORION_CFG_VOLUME        "volume"
#define ORION_CFG_DEBUG_CLIPS   "debug_clips"

// The TTS model is a setting, not a constant: switching Fish models is one
// word in .env plus a reflash of the nvs partition, with no rebuild.
#define ORION_CFG_TTS_MODEL     "tts_model"

// "fish" or "deepinfra". Fish ASR is the real one; the second is a standby that
// speaks the same multipart shape and returns the same JSON field.
#define ORION_CFG_ASR_PROVIDER  "asr_provider"

// "tool", "keyword" or "off". How the model is offered the camera.
#define ORION_CFG_VISION_MODE   "vision_mode"

// Written by the phone during Bluetooth setup (orion_prov), or by
// provision.py from APP_TOKEN in .env. The token gates the LAN API.
#define ORION_CFG_APP_TOKEN     "app_token"
#define ORION_CFG_DEVICE_NAME   "device_name"
// Every app paired with this board, newest first, comma separated, up to four:
// a phone and a PC each hold their own. app_token above is always the newest.
#define ORION_CFG_APP_TOKENS    "app_tokens"

// 1 means the next boot goes straight into Bluetooth setup mode. orion_prov
// sets it from a running system and clears it once it has been read.
#define ORION_CFG_PROV_BOOT     "prov_boot"

// The DeepInfra speech model, when asr_provider is deepinfra.
#define ORION_CFG_ASR_MODEL     "asr_model"

// Config version 2: each stage of a turn has its own provider, see
// docs/DEVICE_PROTOCOL.md. llm_model and tts_model keep their version 1 names;
// the other version 1 keys above are read only when these are missing.
#define ORION_CFG_LLM_PROV      "llm_prov"
#define ORION_CFG_LLM_URL       "llm_url"
#define ORION_CFG_LLM_KEY       "llm_key"
#define ORION_CFG_STT_PROV      "stt_prov"
#define ORION_CFG_STT_URL       "stt_url"
#define ORION_CFG_STT_KEY       "stt_key"
#define ORION_CFG_STT_MODEL     "stt_model"
#define ORION_CFG_TTS_PROV      "tts_prov"
#define ORION_CFG_TTS_URL       "tts_url"
#define ORION_CFG_TTS_KEY       "tts_key"
#define ORION_CFG_TTS_VOICE     "tts_voice"

esp_err_t orion_config_init(void);

esp_err_t orion_config_get_str(const char *key, char *out, size_t out_len);
esp_err_t orion_config_get_i32(const char *key, int32_t *out);
bool orion_config_get_bool(const char *key, bool fallback);

esp_err_t orion_config_set_str(const char *key, const char *value);
esp_err_t orion_config_set_i32(const char *key, int32_t value);

// Removes a key, so the reader falls back to its default or version 1 key.
esp_err_t orion_config_erase(const char *key);

// Factory reset: every key in the namespace, Wi-Fi, keys, tokens and
// settings. The next boot has no network and goes into setup mode.
esp_err_t orion_config_erase_all(void);

// Reads a string, falling back to a default. Returns the length written.
size_t orion_config_copy_str(const char *key, char *out, size_t out_len,
                             const char *fallback);

bool orion_config_has(const char *key);

// True when every key the voice loop needs is present.
bool orion_config_is_provisioned(void);

// Logs which keys are set. Secrets are reported by length, never by value.
void orion_config_report(void);
