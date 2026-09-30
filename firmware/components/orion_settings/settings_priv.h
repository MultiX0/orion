// Private to orion_settings.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "esp_err.h"

#define SET_PROVIDER 24
#define SET_URL      129
#define SET_KEY      201    // OpenAI project keys run past 160 characters
#define SET_MODEL    97
#define SET_VOICE    65
#define SET_NAME     33
#define SET_TOKEN    65
#define SET_TZ       48     // a POSIX TZ string, "<+03>-3" or "CET-1CEST,M3.5.0,M10.5.0/3"

typedef struct {
    char provider[SET_PROVIDER];
    char url[SET_URL];
    char key[SET_KEY];
    char model[SET_MODEL];
    char voice[SET_VOICE];      // tts only
} stage_t;

typedef struct {
    char device_name[SET_NAME];
    int32_t volume;
    bool wake_word;
    char tz[SET_TZ];
    stage_t llm;
    stage_t stt;
    stage_t tts;
    struct {
        bool enabled;
        char url[SET_URL];
        char token[SET_TOKEN];
        char approval[8];
    } pc;
} settings_t;

// settings_store.c: NVS in and out, with the version 1 fallbacks.
void settings_load(settings_t *s);
esp_err_t settings_save(const settings_t *old, const settings_t *neu);

// settings_json.c: a partial POST body onto a copy, and the masked render.
// merge returns false with a message in err when a value is out of range.
bool settings_merge(settings_t *s, const char *json, size_t len, char *err, size_t err_len);
void settings_render(const settings_t *s, char *out, size_t out_len);
