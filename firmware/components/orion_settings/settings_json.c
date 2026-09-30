// A partial POST body merged onto a copy of the settings, field by field,
// every value checked before anything is kept; and the masked render.
#include "settings_priv.h"

#include <stdio.h>
#include <ctype.h>
#include <string.h>

#include "cJSON.h"

static const char *LLM_PROVIDERS[] = {
    "deepinfra", "openai", "anthropic", "groq", "openrouter", "ollama", "custom", NULL
};
static const char *STAGE_PROVIDERS[] = { "fish", "openai_compatible", NULL };

static bool one_of(const char *v, const char **list)
{
    for (int i = 0; list[i]; i++) {
        if (strcmp(v, list[i]) == 0) {
            return true;
        }
    }
    return false;
}

static bool fail(char *err, size_t len, const char *what, const char *why)
{
    snprintf(err, len, "%s: %s", what, why);
    return false;
}

// Copies obj[key] into dst when present. A JSON null clears it when nullable.
// Missing keeps dst. Length is checked against [min, max].
static bool take(const cJSON *obj, const char *key, char *dst, size_t cap, size_t min,
                 bool nullable, const char *what, char *err, size_t err_len)
{
    const cJSON *v = cJSON_GetObjectItem(obj, key);
    if (!v) {
        return true;
    }
    if (cJSON_IsNull(v)) {
        if (!nullable) {
            return fail(err, err_len, what, "cannot be null");
        }
        dst[0] = '\0';
        return true;
    }
    if (!cJSON_IsString(v)) {
        return fail(err, err_len, what, "must be a string");
    }
    size_t n = strlen(v->valuestring);
    if (n < min || n >= cap) {
        return fail(err, err_len, what, n < min ? "too short" : "too long");
    }
    // The render writes values without escaping, so quotes never get in.
    for (const unsigned char *p = (const unsigned char *) v->valuestring; *p; p++) {
        if (*p < 0x20 || *p == '"' || *p == '\\') {
            return fail(err, err_len, what, "has a quote, backslash or control character");
        }
    }
    strlcpy(dst, v->valuestring, cap);
    return true;
}

static bool is_url(const char *u)
{
    return strncmp(u, "http://", 7) == 0 || strncmp(u, "https://", 8) == 0;
}

// api_key: omitted keeps, "" clears, anything else replaces.
static bool stage(const cJSON *root, const char *name, stage_t *s, bool is_llm,
                  char *err, size_t err_len)
{
    const cJSON *o = cJSON_GetObjectItem(root, name);
    if (!o) {
        return true;
    }
    if (!cJSON_IsObject(o)) {
        return fail(err, err_len, name, "must be an object");
    }
    char what[32];
    snprintf(what, sizeof(what), "%s.provider", name);
    if (!take(o, "provider", s->provider, SET_PROVIDER, 1, false, what, err, err_len)) {
        return false;
    }
    if (!one_of(s->provider, is_llm ? LLM_PROVIDERS : STAGE_PROVIDERS)) {
        return fail(err, err_len, what, "unknown provider");
    }
    snprintf(what, sizeof(what), "%s.base_url", name);
    if (!take(o, "base_url", s->url, SET_URL, 0, true, what, err, err_len)) {
        return false;
    }
    snprintf(what, sizeof(what), "%s.api_key", name);
    if (!take(o, "api_key", s->key, SET_KEY, 0, true, what, err, err_len)) {
        return false;
    }
    snprintf(what, sizeof(what), "%s.model", name);
    if (!take(o, "model", s->model, SET_MODEL, 1, false, what, err, err_len)) {
        return false;
    }
    if (!is_llm) {
        snprintf(what, sizeof(what), "%s.voice", name);
        if (!take(o, "voice", s->voice, SET_VOICE, 0, true, what, err, err_len)) {
            return false;
        }
    }
    bool fish = strcmp(s->provider, "fish") == 0;
    if (!fish && !is_url(s->url)) {
        snprintf(what, sizeof(what), "%s.base_url", name);
        return fail(err, err_len, what, "must start with http:// or https://");
    }
    if (fish && strcmp(name, "stt") == 0 && strcmp(s->model, "transcribe-1") != 0 &&
        strcmp(s->model, "transcribe-1-pro") != 0) {
        return fail(err, err_len, "stt.model", "fish takes transcribe-1 or transcribe-1-pro");
    }
    if (strcmp(name, "tts") == 0 && s->voice[0] == '\0') {
        return fail(err, err_len, "tts.voice", "needed for text to speech");
    }
    return true;
}

// Version 1 fields, still accepted: fish.* feeds tts (and stt when fish).
static bool legacy(const cJSON *root, settings_t *s, char *err, size_t err_len)
{
    const cJSON *f = cJSON_GetObjectItem(root, "fish");
    if (!cJSON_IsObject(f)) {
        return true;
    }
    if (!take(f, "api_key", s->tts.key, SET_KEY, 0, true, "fish.api_key", err, err_len) ||
        !take(f, "voice_id", s->tts.voice, SET_VOICE, 1, false, "fish.voice_id", err, err_len) ||
        !take(f, "tts_model", s->tts.model, SET_MODEL, 1, false, "fish.tts_model", err, err_len)) {
        return false;
    }
    if (cJSON_GetObjectItem(f, "api_key") && strcmp(s->stt.provider, "fish") == 0) {
        strlcpy(s->stt.key, s->tts.key, SET_KEY);
    }
    return true;
}

static bool basics(const cJSON *root, settings_t *s, char *err, size_t err_len)
{
    const cJSON *tz = cJSON_GetObjectItem(root, "time_zone");
    if (tz) {
        // A POSIX TZ string. Only the characters the format uses, so nothing
        // odd reaches setenv.
        bool ok = cJSON_IsString(tz) && tz->valuestring[0] && strlen(tz->valuestring) < SET_TZ;
        for (const char *c = ok ? tz->valuestring : ""; ok && *c; c++) {
            ok = isalnum((unsigned char) *c) || strchr("<>+-:,./", *c);
        }
        if (!ok) {
            return fail(err, err_len, "time_zone", "a POSIX TZ string such as <+03>-3");
        }
        strlcpy(s->tz, tz->valuestring, sizeof(s->tz));
    }
    if (!take(root, "device_name", s->device_name, SET_NAME, 1, false, "device_name", err, err_len)) {
        return false;
    }
    const cJSON *v = cJSON_GetObjectItem(root, "volume");
    if (v) {
        if (!cJSON_IsNumber(v) || v->valueint < 0 || v->valueint > 100) {
            return fail(err, err_len, "volume", "0 to 100");
        }
        s->volume = v->valueint;
    }
    const cJSON *w = cJSON_GetObjectItem(root, "wake_word_enabled");
    if (w) {
        if (!cJSON_IsBool(w)) {
            return fail(err, err_len, "wake_word_enabled", "true or false");
        }
        s->wake_word = cJSON_IsTrue(w);
    }
    const cJSON *pc = cJSON_GetObjectItem(root, "pc");
    if (pc) {
        if (!cJSON_IsObject(pc)) {
            return fail(err, err_len, "pc", "must be an object");
        }
        const cJSON *en = cJSON_GetObjectItem(pc, "enabled");
        if (en) {
            if (!cJSON_IsBool(en)) {
                return fail(err, err_len, "pc.enabled", "true or false");
            }
            s->pc.enabled = cJSON_IsTrue(en);
        }
        if (!take(pc, "base_url", s->pc.url, SET_URL, 0, true, "pc.base_url", err, err_len) ||
            !take(pc, "token", s->pc.token, SET_TOKEN, 0, true, "pc.token", err, err_len) ||
            !take(pc, "approval", s->pc.approval, sizeof(s->pc.approval), 1, false, "pc.approval",
                  err, err_len)) {
            return false;
        }
        if (strcmp(s->pc.approval, "ask") != 0 && strcmp(s->pc.approval, "auto") != 0) {
            return fail(err, err_len, "pc.approval", "ask or auto");
        }
        if (s->pc.enabled && !is_url(s->pc.url)) {
            return fail(err, err_len, "pc.base_url", "must start with http:// or https://");
        }
    }
    return true;
}

bool settings_merge(settings_t *s, const char *json, size_t len, char *err, size_t err_len)
{
    cJSON *root = cJSON_ParseWithLength(json, len);
    if (!cJSON_IsObject(root)) {
        cJSON_Delete(root);
        return fail(err, err_len, "body", "not a JSON object");
    }
    bool ok = basics(root, s, err, err_len) &&
              stage(root, "llm", &s->llm, true, err, err_len) &&
              stage(root, "stt", &s->stt, false, err, err_len) &&
              stage(root, "tts", &s->tts, false, err, err_len) &&
              legacy(root, s, err, err_len);
    cJSON_Delete(root);
    return ok;
}

// "...4f2a", or null when no key is stored.
static void masked(const char *key, char *out, size_t len)
{
    size_t n = strlen(key);
    if (n == 0) {
        strlcpy(out, "null", len);
    } else {
        snprintf(out, len, "\"...%s\"", key + (n > 4 ? n - 4 : 0));
    }
}

static int render_stage(char *out, size_t len, const char *name, const stage_t *s, bool voice)
{
    char k[16];
    masked(s->key, k, sizeof(k));
    int n = snprintf(out, len, "\"%s\":{\"provider\":\"%s\",\"base_url\":", name, s->provider);
    if (s->url[0]) {
        n += snprintf(out + n, len - n, "\"%s\"", s->url);
    } else {
        n += snprintf(out + n, len - n, "null");
    }
    n += snprintf(out + n, len - n, ",\"api_key\":%s,\"model\":\"%s\"", k, s->model);
    if (voice) {
        n += snprintf(out + n, len - n, ",\"voice\":\"%s\"", s->voice);
    }
    n += snprintf(out + n, len - n, "}");
    return n;
}

void settings_render(const settings_t *s, char *out, size_t len)
{
    char t[16];
    masked(s->pc.token, t, sizeof(t));
    int n = snprintf(out, len, "{\"device_name\":\"%s\",\"volume\":%d,\"wake_word_enabled\":%s,"
                     "\"time_zone\":\"%s\",",
                     s->device_name, (int) s->volume, s->wake_word ? "true" : "false", s->tz);
    n += render_stage(out + n, len - n, "llm", &s->llm, false);
    n += snprintf(out + n, len - n, ",");
    n += render_stage(out + n, len - n, "stt", &s->stt, false);
    n += snprintf(out + n, len - n, ",");
    n += render_stage(out + n, len - n, "tts", &s->tts, true);
    snprintf(out + n, len - n, ",\"pc\":{\"enabled\":%s,\"base_url\":\"%s\",\"token\":%s,\"approval\":\"%s\"}}",
             s->pc.enabled ? "true" : "false", s->pc.url, t, s->pc.approval);
}
