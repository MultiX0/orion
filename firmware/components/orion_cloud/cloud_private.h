// Shared inside orion_cloud only. Nothing outside the component includes this.
#pragma once

#include "orion_cloud.h"

#include "esp_http_client.h"

#define FISH_TTS_URL  "https://api.fish.audio/v1/tts"
#define FISH_ASR_URL  "https://api.fish.audio/v1/asr"

// Measured against every speech model DeepInfra serves, tools/cloud/asr_speed.py.
#define DI_ASR_MODEL  "Qwen/Qwen3-ASR-1.7B"

#define ASSETS_BASE   "/assets"

#define CLOUD_REPLY_MAX 1536

// ---- settings, read from NVS once, see cloud_cfg.c ----

typedef enum {
    CLOUD_PROV_FISH = 0,        // Fish Audio's own API
    CLOUD_PROV_OPENAI,          // anything that speaks the OpenAI shape
} cloud_prov_t;

// One stage of a turn: where it goes, with what key, which model.
typedef struct {
    cloud_prov_t prov;
    char url[192];              // the endpoint itself, ready to POST to
    char origin[128];           // scheme://host:port, one connection per origin
    char auth[288];             // "Bearer <key>", or "" for a server that wants none
    char model[96];
    char voice[64];             // tts only
} cloud_stage_cfg_t;

typedef struct {
    cloud_stage_cfg_t llm;
    cloud_stage_cfg_t stt;
    cloud_stage_cfg_t tts;
    // The PC brain (docs/HARNESS.md): the desktop app's OpenAI style endpoint.
    // url is empty unless pc.enabled with an address and a token.
    cloud_stage_cfg_t pc;
    uint32_t tts_rate;          // 32000 from Fish by default, 24000 from an OpenAI style server
    char vision_mode[12];
} cloud_cfg_t;

esp_err_t cloud_cfg_load(void);
const cloud_cfg_t *cloud_cfg(void);
// Console only: the rate asked of Fish TTS, 16000, 24000, 32000 or 44100.
void cloud_cfg_set_fish_rate(uint32_t hz);

// ---- one kept alive connection per stage, see cloud_net.c ----

typedef enum {
    CLOUD_SLOT_LLM = 0,
    CLOUD_SLOT_STT,
    CLOUD_SLOT_TTS,
    CLOUD_SLOT_PC,          // plain HTTP on the LAN, only in PC mode
    CLOUD_SLOT_PHONE,       // plain HTTP on the LAN, while a phone is linked
    CLOUD_SLOT_COUNT,
} cloud_slot_t;

typedef struct {
    const char *url;
    esp_http_client_method_t method;
    const char *auth;
    const char *content_type;   // NULL: none
    const char *model;          // Fish's model header, NULL: none
    int body_len;
    // Writes exactly body_len bytes. Called a second time, from the start, if
    // a kept alive socket turns out to be dead and the request goes again.
    esp_err_t (*write_body)(esp_http_client_handle_t c, void *ctx);
    void *ctx;
} cloud_req_t;

typedef struct {
    esp_http_client_handle_t c;
    int status;
    bool head;
    bool reused;            // went out on a kept alive socket
    uint32_t connect_ms;    // TCP and TLS setup, 0 when reused
    uint32_t send_ms;       // setup, request and response headers
    uint32_t t0;            // when the request started
} cloud_resp_t;

esp_err_t cloud_net_init(void);

// Takes the slot and sends. On ESP_OK the slot stays held until cloud_finish;
// on failure it has already been released.
esp_err_t cloud_send(cloud_slot_t slot, const cloud_req_t *req, cloud_resp_t *resp);
int cloud_read(cloud_resp_t *resp, char *buf, int len);

// A request whose body is not known yet: takes the slot and sends the request
// line and headers with Transfer-Encoding: chunked. The caller writes chunk
// framing and data itself with esp_http_client_write, ends with the zero
// chunk, then cloud_stream_response for the status. cloud_finish releases the
// slot either way. On failure the slot has already been released.
esp_err_t cloud_open_stream(cloud_slot_t slot, const cloud_req_t *req, cloud_resp_t *resp);
esp_err_t cloud_stream_response(cloud_resp_t *resp);
esp_err_t cloud_read_all(cloud_resp_t *resp, char **out, size_t *len, size_t cap);

// keep: everything went right and the response was read to its end, so the
// socket stays open for the next request.
void cloud_finish(cloud_slot_t slot, cloud_resp_t *resp, bool keep);

// Status and error of the slot's last request, for orion_cloud_test.
void cloud_last_result(cloud_slot_t slot, int *status, esp_err_t *err);

// A turn, a test or a stream in progress. orion_cloud_reload refuses while any is.
bool cloud_busy_enter(void);
void cloud_busy_exit(void);
// Held by a reload while it rewrites the settings.
bool cloud_gate_lock(uint32_t wait_ms);
void cloud_gate_unlock(void);

// A one token chat completion with the stored settings, for orion_cloud_test.
esp_err_t cloud_llm_ping(void);

// Runs fn on a 12 KB PSRAM stack and waits. fn must never touch flash.
bool cloud_run_big(void (*fn)(void *arg), void *arg);
bool cloud_workers_idle(uint32_t wait_ms);

// Opens or refreshes the slot's connection. Returns ms, 0 on failure.
uint32_t cloud_prewarm_slot(cloud_slot_t slot);

// Binds each stage to a connection from cloud_cfg(): at init and after a
// reload. Closes the connections whose host changed or that nobody uses now.
void cloud_net_bind(void);

// True when this stage uses another stage's connection (same host).
bool cloud_net_shared(cloud_slot_t stage);
void cloud_net_set_timeout(cloud_slot_t stage, int ms);

// The extended brains, cloud_pc.c: the PC (checked on every prewarm) and the
// phone (while linked). slot is CLOUD_SLOT_PC or CLOUD_SLOT_PHONE. LLM worker.
void cloud_pc_check(void);
bool cloud_brain_ready(cloud_slot_t slot);
void cloud_brain_failed(cloud_slot_t slot);
const cloud_stage_cfg_t *cloud_phone_stage(void);

// The settings of the stage a slot serves.
const cloud_stage_cfg_t *cloud_slot_stage(cloud_slot_t slot);

// [tags] out, in place, for a TTS that would read them aloud.
void cloud_strip_tags(char *text);

// Rebuilds the system prompt the model gets: the file with its <fish> voice
// tag section kept when the TTS is Fish, or dropped and a line asking for no
// bracket tags added when it is not. Runs at init and on every reload.
void cloud_prompt_refresh(void);

// base into out (strlen(base) + 1 bytes) with the <fish> ... </fish> section
// kept without its marker lines (fish) or dropped whole (not fish).
void cloud_cut_fish_section(const char *base, bool fish, char *out);

// The <fish> cut for both providers, run by cloud_selftest.
int prompt_selftest(void);

// cfg_set, cfg_copy, cfg_del on the console, see cloud_cfg_cmds.c.
void cloud_cfg_register_cmds(void);

// ---- one reply in flight, shared by the two workers and the caller ----

typedef struct {
    char *reply;            // PSRAM, CLOUD_REPLY_MAX
    size_t reply_len;
    bool speak;             // hand pieces to the TTS worker
    bool used_camera;
    int pieces;
    uint32_t llm_first_ms;  // chat request to its first token
    uint32_t llm_ms;        // chat request to its last token
    uint32_t llm_connect_ms;
    uint32_t tts_first_ms;  // first piece handed over to its first PCM byte
    uint32_t tts_connect_ms;
    uint32_t tts_total_ms;
    esp_err_t llm_err;
    esp_err_t tts_err;
} cloud_reply_state_t;

// Runs on the LLM worker. See cloud_reply.c.
esp_err_t cloud_reply_run(const char *text, cloud_reply_state_t *st);
void cloud_reply_append(cloud_reply_state_t *st, const char *delta);
void cloud_speak_piece(cloud_reply_state_t *st, const char *piece);
bool cloud_cancelled(void);

// ---- the stages ----

esp_err_t cloud_asr_run(const int16_t *pcm, size_t samples, char *out, size_t out_len,
                        uint32_t *connect_ms);
esp_err_t cloud_asr_stream_begin(void);
esp_err_t cloud_asr_stream_write(const int16_t *pcm, size_t samples);
esp_err_t cloud_asr_stream_end(char *out, size_t out_len, uint32_t *connect_ms);
void cloud_asr_stream_abort(void);
esp_err_t cloud_tts_run(const char *text, orion_tts_sink_t sink, void *ctx,
                        uint32_t *first_ms, uint32_t *connect_ms);

// ---- the workers, see cloud_stream.c ----

esp_err_t cloud_stream_init(void);

// Audio the speaker waits for before a piece plays, in ms; 0 plays at once.
void cloud_stream_set_preroll(uint32_t ms);
uint32_t cloud_stream_preroll(void);
esp_err_t cloud_reply_stream(const char *text, char *reply, size_t reply_len,
                             orion_tts_sink_t sink, void *sink_ctx,
                             orion_reply_cb_t on_reply, void *reply_ctx);

// ---- history and prompt, see orion_cloud.c ----

#define CLOUD_HISTORY_TURNS 6
int cloud_history_count(void);
const char *cloud_history_user(int i);
const char *cloud_history_reply(int i);
void cloud_history_push(const char *user, const char *reply);
const char *cloud_system_prompt(void);
orion_cloud_timing_t *cloud_timing(void);

// ---- small things ----

void cloud_wav_header(uint8_t hdr[44], size_t pcm_bytes, uint32_t rate);
uint32_t cloud_now_ms(void);
void *cloud_psram_alloc(size_t bytes);
char *cloud_psram_strdup(const char *s);
