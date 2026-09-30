// A JSON writer into one PSRAM buffer, internal to orion_cloud.
#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    char *buf;
    size_t len;
    size_t cap;
    bool overflow;      // set once anything did not fit; the body is then unusable
} jw_t;

bool jw_init(jw_t *w, size_t cap);
void jw_free(jw_t *w);

// Appends as is: punctuation, numbers, literals.
void jw_raw(jw_t *w, const char *s);

// Appends a quoted, escaped string. UTF-8 passes through untouched.
void jw_str(jw_t *w, const char *s);

// "key":"value"
void jw_kv_str(jw_t *w, const char *key, const char *value);

// "data:image/jpeg;base64,...", encoded straight into the buffer.
void jw_data_url_jpeg(jw_t *w, const uint8_t *jpeg, size_t len);

// How many bytes jw_str would write for s, for sizing the buffer up front.
size_t jw_escaped_len(const char *s);
