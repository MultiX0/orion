// Every setting the cloud calls need, read from NVS and kept in PSRAM.
// Config version 2 (docs/DEVICE_PROTOCOL.md): the language model, speech to
// text and text to speech each have their own provider, URL, key and model.
//
// A version 2 key that is missing falls back to its version 1 key, so a board
// provisioned before version 2 behaves exactly as it did. With nothing
// stored at all, the defaults are the contract's: Fish transcribe-1, Fish
// s2.1-pro-free, Gemma 4 31B turbo on DeepInfra.
//
// Read once at init and again on orion_cloud_reload, on a task whose stack is
// in internal RAM: the cloud workers keep theirs in PSRAM, and an NVS read
// disables the flash cache, which asserts on such a stack.

#include "cloud_private.h"

#include <ctype.h>
#include <string.h>

#include "esp_heap_caps.h"
#include "esp_log.h"

#include "orion_config.h"

static const char *TAG = "cloud_cfg";

#define DEEPINFRA      "https://api.deepinfra.com/v1/openai"
#define OPENAI_TTS_DEFAULT "Qwen/Qwen3-TTS"     // the one that speaks Arabic, measured

// Orion's voice on Fish when none is set: "Orion Voice", designed for this
// project and unlisted, so any Fish key can use it and every board sounds the
// same out of the box. Only a Fish TTS reads it; another provider has its own
// voice names.
#define FISH_DEFAULT_VOICE "9a68c1d739134940a4297c996c5ca6a1"

static cloud_cfg_t *s_cfg;
// The rate asked of Fish. 16 kHz stops at 8 kHz, where a soft voice keeps
// much of its consonants. The MAX98357A cannot lock to 24 kHz at all (its
// datasheet lists it among the rates it cannot take). 32 kHz keeps
// everything the voice has, which sits below about 10 kHz.
static uint32_t s_fish_rate = 32000;

// The first key that is set, else fallback. out gets "" for a NULL fallback.
static void first_of(const char *k1, const char *k2, char *out, size_t len, const char *fallback)
{
    if (orion_config_get_str(k1, out, len) == ESP_OK && out[0]) return;
    if (k2 && orion_config_get_str(k2, out, len) == ESP_OK && out[0]) return;
    strlcpy(out, fallback ? fallback : "", len);
}

static void bearer(const char *k1, const char *k2, char *out, size_t len)
{
    char key[256];
    first_of(k1, k2, key, sizeof(key), NULL);
    if (key[0]) snprintf(out, len, "Bearer %s", key);
    else out[0] = '\0';
    memset(key, 0, sizeof(key));
}

static cloud_prov_t prov_of(const char *s)
{
    return strcmp(s, "fish") == 0 ? CLOUD_PROV_FISH : CLOUD_PROV_OPENAI;
}

// "https://host:port/path" -> url without trailing slash, origin "https://host:port".
static void set_url(cloud_stage_cfg_t *st, const char *base, const char *path)
{
    char b[160];
    strlcpy(b, base, sizeof(b));
    size_t n = strlen(b);
    while (n && b[n - 1] == '/') b[--n] = '\0';
    snprintf(st->url, sizeof(st->url), "%s%s", b, path);
    const char *host = strstr(b, "://");
    host = host ? host + 3 : b;
    const char *slash = strchr(host, '/');
    const size_t origin_len = slash ? (size_t) (slash - b) : strlen(b);
    snprintf(st->origin, sizeof(st->origin), "%.*s", (int) origin_len, b);
    for (char *p = st->origin; *p; p++) *p = (char) tolower((unsigned char) *p);
}

static void load_llm(cloud_stage_cfg_t *st)
{
    char base[160];
    first_of(ORION_CFG_LLM_URL, NULL, base, sizeof(base), DEEPINFRA);
    st->prov = CLOUD_PROV_OPENAI;
    set_url(st, base, "/chat/completions");
    bearer(ORION_CFG_LLM_KEY, ORION_CFG_DEEPINFRA_KEY, st->auth, sizeof(st->auth));
    first_of(ORION_CFG_LLM_MODEL, NULL, st->model, sizeof(st->model),
             "google/gemma-4-31B-it-turbo");
}

static void load_stt(cloud_stage_cfg_t *st)
{
    char prov[24];
    if (orion_config_get_str(ORION_CFG_STT_PROV, prov, sizeof(prov)) != ESP_OK || !prov[0]) {
        // Version 1 said "fish" or "deepinfra".
        first_of(ORION_CFG_ASR_PROVIDER, NULL, prov, sizeof(prov), "fish");
    }
    st->prov = prov_of(prov);
    if (st->prov == CLOUD_PROV_FISH) {
        set_url(st, FISH_ASR_URL, "");
        bearer(ORION_CFG_STT_KEY, ORION_CFG_FISH_KEY, st->auth, sizeof(st->auth));
        first_of(ORION_CFG_STT_MODEL, NULL, st->model, sizeof(st->model), "transcribe-1");
    } else {
        char base[160];
        first_of(ORION_CFG_STT_URL, NULL, base, sizeof(base), DEEPINFRA);
        set_url(st, base, "/audio/transcriptions");
        bearer(ORION_CFG_STT_KEY, ORION_CFG_DEEPINFRA_KEY, st->auth, sizeof(st->auth));
        first_of(ORION_CFG_STT_MODEL, ORION_CFG_ASR_MODEL, st->model, sizeof(st->model),
                 DI_ASR_MODEL);
    }
}

static void load_tts(cloud_stage_cfg_t *st)
{
    char prov[24];
    first_of(ORION_CFG_TTS_PROV, NULL, prov, sizeof(prov), "fish");
    st->prov = prov_of(prov);
    first_of(ORION_CFG_TTS_MODEL, NULL, st->model, sizeof(st->model), NULL);
    if (st->prov == CLOUD_PROV_FISH) {
        set_url(st, FISH_TTS_URL, "");
        bearer(ORION_CFG_TTS_KEY, ORION_CFG_FISH_KEY, st->auth, sizeof(st->auth));
        if (!st->model[0]) strlcpy(st->model, "s2.1-pro-free", sizeof(st->model));
        first_of(ORION_CFG_TTS_VOICE, ORION_CFG_FISH_VOICE, st->voice, sizeof(st->voice),
                 FISH_DEFAULT_VOICE);
        return;
    }
    char base[160];
    first_of(ORION_CFG_TTS_URL, NULL, base, sizeof(base), DEEPINFRA);
    set_url(st, base, "/audio/speech");
    bearer(ORION_CFG_TTS_KEY, ORION_CFG_DEEPINFRA_KEY, st->auth, sizeof(st->auth));
    // tts_model is shared with version 1. A Fish model name left behind from
    // before the switch would be rejected by the new server, so it is replaced.
    if (!st->model[0] || strncmp(st->model, "s1", 2) == 0 || strncmp(st->model, "s2", 2) == 0) {
        strlcpy(st->model, OPENAI_TTS_DEFAULT, sizeof(st->model));
    }
    first_of(ORION_CFG_TTS_VOICE, NULL, st->voice, sizeof(st->voice), NULL);
    // A 32 character Fish voice id means nothing to another server: omit it.
    if (strlen(st->voice) == 32 && strspn(st->voice, "0123456789abcdef") == 32) {
        st->voice[0] = '\0';
    }
}

// pc_enabled, pc_url and pc_token are written by the desktop app through
// POST /api/config when the user turns PC control on (orion_settings).
static void load_pc(cloud_stage_cfg_t *st)
{
    char url[160] = "";
    char token[96] = "";
    memset(st, 0, sizeof(*st));
    st->prov = CLOUD_PROV_OPENAI;
    if (!orion_config_get_bool("pc_enabled", false)) return;
    orion_config_get_str("pc_url", url, sizeof(url));
    orion_config_get_str("pc_token", token, sizeof(token));
    if (url[0] && token[0]) {
        set_url(st, url, "/v1/chat/completions");
        snprintf(st->auth, sizeof(st->auth), "Bearer %s", token);
    }
    memset(token, 0, sizeof(token));
}

esp_err_t cloud_cfg_load(void)
{
    if (!s_cfg) {
        s_cfg = heap_caps_calloc(1, sizeof(*s_cfg), MALLOC_CAP_SPIRAM);
        if (!s_cfg) return ESP_ERR_NO_MEM;
    }
    cloud_cfg_t *c = s_cfg;
    load_llm(&c->llm);
    load_stt(&c->stt);
    load_tts(&c->tts);
    load_pc(&c->pc);
    c->tts_rate = c->tts.prov == CLOUD_PROV_FISH ? s_fish_rate : 24000;
    orion_config_copy_str(ORION_CFG_VISION_MODE, c->vision_mode, sizeof(c->vision_mode), "tool");

    ESP_LOGI(TAG, "llm %s at %s, key %s", c->llm.model, c->llm.origin,
             c->llm.auth[0] ? "set" : "none");
    ESP_LOGI(TAG, "stt %s %s at %s, key %s", c->stt.prov == CLOUD_PROV_FISH ? "fish" : "openai",
             c->stt.model, c->stt.origin, c->stt.auth[0] ? "set" : "none");
    ESP_LOGI(TAG, "tts %s %s voice %s at %s, %u Hz, key %s",
             c->tts.prov == CLOUD_PROV_FISH ? "fish" : "openai", c->tts.model,
             c->tts.voice[0] ? c->tts.voice : "(default)", c->tts.origin,
             (unsigned) c->tts_rate, c->tts.auth[0] ? "set" : "none");
    ESP_LOGI(TAG, "pc brain %s", c->pc.url[0] ? c->pc.origin : "off");
    return ESP_OK;
}

const cloud_cfg_t *cloud_cfg(void)
{
    return s_cfg;
}

void cloud_cfg_set_fish_rate(uint32_t hz)
{
    if (hz != 16000 && hz != 24000 && hz != 32000 && hz != 44100) {
        return;
    }
    s_fish_rate = hz;
    if (s_cfg && s_cfg->tts.prov == CLOUD_PROV_FISH) {
        s_cfg->tts_rate = hz;
    }
}

const cloud_stage_cfg_t *cloud_slot_stage(cloud_slot_t slot)
{
    switch (slot) {
    case CLOUD_SLOT_LLM: return &s_cfg->llm;
    case CLOUD_SLOT_STT: return &s_cfg->stt;
    case CLOUD_SLOT_PC:  return &s_cfg->pc;
    case CLOUD_SLOT_PHONE: return cloud_phone_stage();
    default:             return &s_cfg->tts;
    }
}
