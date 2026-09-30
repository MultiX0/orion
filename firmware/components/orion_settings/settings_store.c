// NVS in and out. Keys are the table in docs/DEVICE_PROTOCOL.md; a version 1
// key fills in when its version 2 key is missing, so a board provisioned
// before config v2 keeps working.
#include "settings_priv.h"

#include <stdio.h>
#include <string.h>

#include "esp_log.h"

#include "orion_config.h"

static const char *TAG = "orion_settings";

#define DEEPINFRA_URL   "https://api.deepinfra.com/v1/openai"
#define DEFAULT_LLM     "google/gemma-4-31B-it-turbo"
#define DEFAULT_STT     "transcribe-1"
#define DEFAULT_ASR     "Qwen/Qwen3-ASR-1.7B"
#define DEFAULT_TTS     "s2.1-pro-free"
#define DEFAULT_VOICE   "9a68c1d739134940a4297c996c5ca6a1"   // Orion Voice

// Reads key, then the version 1 key, then the default.
static void read(const char *key, const char *v1, const char *dflt, char *out, size_t len)
{
    if (orion_config_copy_str(key, out, len, NULL) > 0) {
        return;
    }
    if (v1 && orion_config_copy_str(v1, out, len, NULL) > 0) {
        return;
    }
    strlcpy(out, dflt ? dflt : "", len);
}

void settings_load(settings_t *s)
{
    memset(s, 0, sizeof(*s));
    read(ORION_CFG_DEVICE_NAME, NULL, "Orion", s->device_name, sizeof(s->device_name));
    // UTC until an app says where the board is; the apps set it from the
    // phone's or the PC's own zone.
    read("tz", NULL, "UTC0", s->tz, sizeof(s->tz));
    s->volume = 70;
    orion_config_get_i32(ORION_CFG_VOLUME, &s->volume);
    s->wake_word = orion_config_get_bool("ww_enabled", true);

    read("llm_prov", NULL, "deepinfra", s->llm.provider, SET_PROVIDER);
    read("llm_url", NULL, DEEPINFRA_URL, s->llm.url, SET_URL);
    read("llm_key", ORION_CFG_DEEPINFRA_KEY, "", s->llm.key, SET_KEY);
    read(ORION_CFG_LLM_MODEL, NULL, DEFAULT_LLM, s->llm.model, SET_MODEL);

    // Version 1 said "fish" or "deepinfra" for the speech engine; the second
    // is an OpenAI compatible endpoint with the DeepInfra key and asr_model.
    char asr[16];
    orion_config_copy_str(ORION_CFG_ASR_PROVIDER, asr, sizeof(asr), "fish");
    bool v1_di = strcmp(asr, "deepinfra") == 0;
    read("stt_prov", NULL, v1_di ? "openai_compatible" : "fish", s->stt.provider, SET_PROVIDER);
    read("stt_url", NULL, v1_di ? DEEPINFRA_URL : "", s->stt.url, SET_URL);
    read("stt_key", v1_di ? ORION_CFG_DEEPINFRA_KEY : ORION_CFG_FISH_KEY, "", s->stt.key, SET_KEY);
    read("stt_model", v1_di ? ORION_CFG_ASR_MODEL : NULL, v1_di ? DEFAULT_ASR : DEFAULT_STT,
         s->stt.model, SET_MODEL);

    read("tts_prov", NULL, "fish", s->tts.provider, SET_PROVIDER);
    read("tts_url", NULL, "", s->tts.url, SET_URL);
    read("tts_key", ORION_CFG_FISH_KEY, "", s->tts.key, SET_KEY);
    read(ORION_CFG_TTS_MODEL, NULL, DEFAULT_TTS, s->tts.model, SET_MODEL);
    read("tts_voice", ORION_CFG_FISH_VOICE, DEFAULT_VOICE, s->tts.voice, SET_VOICE);

    s->pc.enabled = orion_config_get_bool("pc_enabled", false);
    read("pc_url", NULL, "", s->pc.url, SET_URL);
    read("pc_token", NULL, "", s->pc.token, SET_TOKEN);
    read("pc_approval", NULL, "ask", s->pc.approval, sizeof(s->pc.approval));
}

static esp_err_t put_str(esp_err_t acc, const char *key, const char *old, const char *neu)
{
    if (strcmp(old, neu) == 0) {
        return acc;
    }
    esp_err_t err = orion_config_set_str(key, neu);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "store %s: %s", key, esp_err_to_name(err));
        return err;
    }
    return acc;
}

static esp_err_t put_i32(esp_err_t acc, const char *key, int32_t old, int32_t neu)
{
    if (old == neu) {
        return acc;
    }
    esp_err_t err = orion_config_set_i32(key, neu);
    return err == ESP_OK ? acc : err;
}

static esp_err_t put_stage(esp_err_t acc, const char *prefix, const stage_t *o, const stage_t *n,
                           const char *model_key, bool voice)
{
    char k[16];
    snprintf(k, sizeof(k), "%s_prov", prefix);
    acc = put_str(acc, k, o->provider, n->provider);
    snprintf(k, sizeof(k), "%s_url", prefix);
    acc = put_str(acc, k, o->url, n->url);
    snprintf(k, sizeof(k), "%s_key", prefix);
    acc = put_str(acc, k, o->key, n->key);
    acc = put_str(acc, model_key, o->model, n->model);
    if (voice) {
        snprintf(k, sizeof(k), "%s_voice", prefix);
        acc = put_str(acc, k, o->voice, n->voice);
    }
    return acc;
}

static bool di_stt(const settings_t *s)
{
    return strcmp(s->stt.provider, "openai_compatible") == 0 && strcmp(s->stt.url, DEEPINFRA_URL) == 0;
}

// orion_cloud falls back to a version 1 key when its version 2 key is empty,
// so the version 1 keys follow along: a cleared or replaced key never comes
// back through the fallback.
static esp_err_t mirror_v1(esp_err_t acc, const settings_t *o, const settings_t *n)
{
    if (strcmp(n->llm.url, DEEPINFRA_URL) == 0) {
        acc = put_str(acc, ORION_CFG_DEEPINFRA_KEY, o->llm.key, n->llm.key);
    }
    if (strcmp(n->tts.provider, "fish") == 0) {
        acc = put_str(acc, ORION_CFG_FISH_KEY, o->tts.key, n->tts.key);
        acc = put_str(acc, ORION_CFG_FISH_VOICE, o->tts.voice, n->tts.voice);
    }
    acc = put_str(acc, ORION_CFG_ASR_PROVIDER, di_stt(o) ? "deepinfra" : "fish",
                  di_stt(n) ? "deepinfra" : "fish");
    if (di_stt(n)) {
        acc = put_str(acc, ORION_CFG_ASR_MODEL, o->stt.model, n->stt.model);
    }
    return acc;
}

// Writes only what changed. Keys are logged by name, never by value.
esp_err_t settings_save(const settings_t *o, const settings_t *n)
{
    esp_err_t acc = mirror_v1(ESP_OK, o, n);
    acc = put_str(acc, ORION_CFG_DEVICE_NAME, o->device_name, n->device_name);
    acc = put_str(acc, "tz", o->tz, n->tz);
    acc = put_i32(acc, ORION_CFG_VOLUME, o->volume, n->volume);
    acc = put_i32(acc, "ww_enabled", o->wake_word, n->wake_word);
    acc = put_stage(acc, "llm", &o->llm, &n->llm, ORION_CFG_LLM_MODEL, false);
    acc = put_stage(acc, "stt", &o->stt, &n->stt, "stt_model", false);
    acc = put_stage(acc, "tts", &o->tts, &n->tts, ORION_CFG_TTS_MODEL, true);
    acc = put_i32(acc, "pc_enabled", o->pc.enabled, n->pc.enabled);
    acc = put_str(acc, "pc_url", o->pc.url, n->pc.url);
    acc = put_str(acc, "pc_token", o->pc.token, n->pc.token);
    acc = put_str(acc, "pc_approval", o->pc.approval, n->pc.approval);
    return acc;
}
