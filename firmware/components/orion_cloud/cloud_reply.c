// The streaming chat completion, run on the LLM worker.
//
// Tokens arrive over SSE, go into the chunker, and every piece the chunker lets
// go is handed to the TTS worker at once, so Orion starts speaking on the first
// clause instead of after the last word.
//
// Vision: a question that asks for the camera in so many words (LOOK_WORDS)
// takes a JPEG first, and the request carries it as an image part. No tools
// are offered.

#include "cloud_private.h"

#include <ctype.h>
#include <string.h>
#include <time.h>

#include "esp_log.h"

#include "cloud_chunk.h"
#include "cloud_json.h"
#include "cloud_sse.h"
#include "orion_camera.h"

static const char *TAG = "cloud_reply";

#define MAX_TOKENS 200
// A model that thinks before it answers spends its thinking out of the limit:
// Claude when it cannot stop, and OpenAI's reasoning models, which count it in
// max_completion_tokens.
#define MAX_TOKENS_THINKING 2000
#define READ_BUF   2048
// esp_http_client_read() does not return until it has the whole length asked
// for or the response ends. Asked for READ_BUF, a short answer's first token
// sits in the buffer until the last one arrives (llm_first_ms 880 against
// llm_ms 883). One SSE event is about 300 bytes, so a small ask returns per
// token.
#define SSE_READ   128

// Not offered: see tool_mode in cloud_reply_run.
static const char *LOOK_TOOL =
    "[{\"type\":\"function\",\"function\":{\"name\":\"look\",\"description\":"
    "\"Take a picture with the camera and look at what is in front of the device. "
    "Call this whenever the user asks about something you can see.\","
    "\"parameters\":{\"type\":\"object\",\"properties\":{}}}}]";

// The camera is used only when the user asks for it in so many words: take
// a photo, look at this, what do you see. The model is never offered a look
// tool to call on its own judgement, and a question merely about "this" is
// not enough. Latin letters match without case.
static const char *LOOK_WORDS[] = {
    "take a photo", "take a picture", "take a pic", "snap a photo", "snap a picture",
    "take photo", "take picture", "use the camera", "use your camera", "with the camera",
    "with your camera", "look at this", "look at that",
    "what do you see", "what can you see", "what are you seeing", "what am i holding",
    "in front of you", "read this for me",
    // Whole phrases: a bare صور is also inside قصور، تصور، منصور.
    "صوّر", "صوّري", "صورني", "صوّرني", "صور هذا", "صوري هذا", "صور لي", "صوري لي",
    "خذ صورة", "خذي صورة", "التقط صورة", "التقطي صورة", "افتح الكاميرا", "استخدم الكاميرا",
    "بالكاميرا", "شوف هذا", "شوف هاد", "شوفي هذا", "انظر إلى هذا", "انظري إلى هذا", "انظر الى هذا",
    "ماذا ترى", "ماذا ترين", "شو بتشوف", "شو بتشوفي", "شو شايف", "شو شايفة", "قدامك", "أمامك",
};

// A phrase counts only where a word starts, since صور هذا is also the end
// of تصور هذا (imagine this). A byte from 0x80 up counts as part of a word.
static bool word_start(const char *low, const char *at)
{
    const unsigned char b = at > low ? (unsigned char) at[-1] : ' ';
    return b < 0x80 && !isalnum(b);
}

static bool wants_camera(const char *text)
{
    char low[256];
    size_t n = 0;
    for (; text[n] && n < sizeof(low) - 1; n++) {
        low[n] = (char) tolower((unsigned char) text[n]);
    }
    low[n] = '\0';
    for (size_t i = 0; i < sizeof(LOOK_WORDS) / sizeof(LOOK_WORDS[0]); i++) {
        for (const char *m = strstr(low, LOOK_WORDS[i]); m; m = strstr(m + 1, LOOK_WORDS[i])) {
            if (word_start(low, m)) return true;
        }
    }
    return false;
}

// What the board's own model is told when it answers alone, so it never says
// it opened, closed or played something it cannot reach. Without it, asked to
// close Spotify with no PC connected, the model says it did.
static const char *NOTE_ALONE =
    "\n\nNo Orion Hub, PC or phone is connected to you right now. You cannot open, close, play or change "
    "anything on a computer or phone, and you cannot search the web. If asked to, say in one short "
    "sentence that the Orion app has to be open on the PC first, or on the phone for something on "
    "the phone, for example: افتح تطبيق Orion على الكمبيوتر أولاً، وبعدها أفعلها لك. "
    "Never say you did it.";
static const char *NOTE_NO_ANSWER =
    "\n\nThe Orion Hub, PC or phone connected to you did not answer just now, so you cannot act on "
    "it this time and you cannot search the web. If asked to open, close or play something, say in "
    "one short sentence that it did not answer and to try again, for example: "
    "لم يصلني رد الآن، جرّب مرة ثانية. Never say you did it.";

void cloud_reply_append(cloud_reply_state_t *st, const char *delta)
{
    const size_t n = strlen(delta);
    if (st->reply_len + n + 1 < CLOUD_REPLY_MAX) {
        memcpy(st->reply + st->reply_len, delta, n + 1);
        st->reply_len += n;
    }
}

static void message(jw_t *w, const char *role, const char *content)
{
    jw_raw(w, ",{");
    jw_kv_str(w, "role", role);
    jw_raw(w, ",");
    jw_kv_str(w, "content", content);
    jw_raw(w, "}");
}

// The board's clock (SNTP, started by orion_net), so "what time is it" has an
// answer without a PC. Empty until the first sync. The PC brain adds its own.
static void now_line(char *out, size_t len)
{
    out[0] = '\0';
    const time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    if (tm.tm_year + 1900 < 2025) return;
    // With the part of the day spelled out: given only "23:40" the model says
    // "the twenty first hour".
    static const char *PART[] = { "at night", "in the morning", "in the afternoon", "in the evening" };
    const int part = tm.tm_hour < 5 ? 0 : tm.tm_hour < 12 ? 1 : tm.tm_hour < 17 ? 2 : tm.tm_hour < 21 ? 3 : 0;
    char when[96];
    strftime(when, sizeof(when), "%A %d %B %Y, %I:%M", &tm);
    snprintf(out, len, "\n\nCurrent local date and time: %s %s (%02d:%02d).", when, PART[part],
             tm.tm_hour, tm.tm_min);
}

static const char *think_field(const cloud_cfg_t *cfg)
{
    switch (cfg->llm_think) {
    case LLM_THINK_DISABLED: return ",\"thinking\":{\"type\":\"disabled\"}";
    case LLM_THINK_BETWEEN_TOOLS: return ",\"thinking\":{\"type\":\"between_tools\"}";
    default: return "";
    }
}

static bool build(jw_t *w, const char *text, bool tools, const uint8_t *jpeg, size_t jpeg_len,
                  const char *note)
{
    const cloud_cfg_t *cfg = cloud_cfg();
    char now[160];
    now_line(now, sizeof(now));
    const char *prompt = cloud_system_prompt();
    const size_t cap = strlen(prompt) + sizeof(now) + strlen(note) + 1;
    char *system = cloud_psram_alloc(cap);
    if (system) {
        snprintf(system, cap, "%s%s%s", prompt, now, note);
        prompt = system;
    }
    size_t need = 1024 + jw_escaped_len(prompt) + 2 * jw_escaped_len(text);
    for (int i = 0; i < cloud_history_count(); i++) {
        need += 64 + jw_escaped_len(cloud_history_user(i)) + jw_escaped_len(cloud_history_reply(i));
    }
    need += jpeg ? (jpeg_len + 2) / 3 * 4 + 64 : 0;
    if (!jw_init(w, need)) {
        free(system);
        return false;
    }

    jw_raw(w, "{");
    jw_kv_str(w, "model", cfg->llm.model);
    char nums[160];
    snprintf(nums, sizeof(nums), ",\"stream\":true,\"%s\":%d%s%s",
             cfg->llm_mct ? "max_completion_tokens" : "max_tokens",
             (cfg->llm_think == LLM_THINK_ROOM || cfg->llm_mct) ? MAX_TOKENS_THINKING : MAX_TOKENS,
             cfg->llm_no_temp ? "" : ",\"temperature\":0.6", think_field(cfg));
    jw_raw(w, nums);
    jw_raw(w, ",\"messages\":[{");
    jw_kv_str(w, "role", "system");
    jw_raw(w, ",");
    jw_kv_str(w, "content", prompt);
    jw_raw(w, "}");
    free(system);
    for (int i = 0; i < cloud_history_count(); i++) {
        message(w, "user", cloud_history_user(i));
        message(w, "assistant", cloud_history_reply(i));
    }
    if (jpeg) {
        jw_raw(w, ",{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":");
        jw_str(w, text);
        jw_raw(w, "},{\"type\":\"image_url\",\"image_url\":{\"url\":");
        jw_data_url_jpeg(w, jpeg, jpeg_len);
        jw_raw(w, "}}]}");
    } else {
        message(w, "user", text);
    }
    jw_raw(w, "]");
    if (tools) {
        jw_raw(w, ",\"tools\":");
        jw_raw(w, LOOK_TOOL);
        jw_raw(w, ",\"tool_choice\":\"auto\"");
    }
    jw_raw(w, "}");
    return !w->overflow;
}

typedef struct {
    const char *body;
    size_t len;
} body_t;

static esp_err_t write_body(esp_http_client_handle_t c, void *ctx)
{
    const body_t *b = ctx;
    // In pieces: with a photo attached the body runs past 70 KB.
    for (size_t off = 0; off < b->len;) {
        const size_t take = (b->len - off) > 4096 ? 4096 : (b->len - off);
        const int n = esp_http_client_write(c, b->body + off, (int) take);
        if (n <= 0) return ESP_FAIL;
        off += (size_t) n;
    }
    return ESP_OK;
}


// One streamed request, to the board's model or the PC brain.
// ESP_ERR_NOT_FINISHED means the model asked to look.
static esp_err_t stream_once(const jw_t *w, cloud_reply_state_t *st, cloud_slot_t slot)
{
    const cloud_stage_cfg_t *stage = cloud_slot_stage(slot);
    body_t body = { .body = w->buf, .len = w->len };
    cloud_req_t req = {
        .url = stage->url, .method = HTTP_METHOD_POST,
        .auth = stage->auth[0] ? stage->auth : NULL,
        .content_type = "application/json", .body_len = (int) w->len,
        .write_body = write_body, .ctx = &body,
    };
    cloud_resp_t resp;
    const uint32_t t0 = cloud_now_ms();
    esp_err_t err = cloud_send(slot, &req, &resp);
    if (err != ESP_OK) return err;
    st->llm_connect_ms += resp.connect_ms;

    if (resp.status != 200) {
        char *msg = NULL;
        size_t n = 0;
        cloud_read_all(&resp, &msg, &n, 512);
        ESP_LOGE(TAG, "chat http %d: %.160s", resp.status, msg ? msg : "");
        // A provider the board has no rule for, refusing a field: learn it,
        // and the caller sends the same turn again without it.
        bool learned = false;
        if (slot == CLOUD_SLOT_LLM && resp.status == 400 && msg) {
            const cloud_cfg_t *cfg = cloud_cfg();
            const bool temp = !cfg->llm_no_temp && strstr(msg, "temperature");
            const bool mct = !cfg->llm_mct && strstr(msg, "max_tokens") &&
                             strstr(msg, "max_completion_tokens");
            const bool think = cfg->llm_think != LLM_THINK_ASIS && cfg->llm_think != LLM_THINK_ROOM &&
                               strstr(msg, "thinking");
            if (temp || mct) {
                cloud_cfg_llm_learned(temp, mct);
                ESP_LOGW(TAG, "the model refused %s, sending the turn again",
                         temp ? "temperature" : "max_tokens");
                learned = true;
            } else if (think) {
                cloud_cfg_llm_thinks(msg);
                ESP_LOGW(TAG, "the model will think, sending the turn again with room for it");
                learned = true;
            }
        }
        free(msg);
        cloud_finish(slot, &resp, false);
        return learned ? ESP_ERR_INVALID_VERSION : ESP_FAIL;
    }

    char *io = cloud_psram_alloc(READ_BUF + 1024 + CLOUD_CHUNK_MAX + 1024);
    char *chunk_store = cloud_psram_alloc(CLOUD_CHUNK_MAX * 2);
    if (!io || !chunk_store) {
        free(io);
        free(chunk_store);
        cloud_finish(slot, &resp, false);
        return ESP_ERR_NO_MEM;
    }
    char *line = io + READ_BUF;               // 1 KB SSE line
    char *piece = line + 1024;                // one chunker piece
    char *delta = piece + CLOUD_CHUNK_MAX;    // one decoded token
    sse_t sse;
    sse_init(&sse, line, 1024);
    cloud_chunker_t ck;
    chunker_init(&ck, chunk_store, CLOUD_CHUNK_MAX * 2);

    // An Orion Hub sends each thing it says whole, in one burst: a filler
    // while it works, then the answer. Cut at every comma and full stop like
    // a token stream, each piece became its own TTS request, with its own
    // intonation and a silence at every join. So from the hub the text is
    // held and spoken in one request when the stream goes quiet: the hub
    // sends a ": working" keep-alive right after each burst, or the end.
    const bool whole = slot == CLOUD_SLOT_HUB;
    bool done = false;
    err = ESP_OK;
    while (!done && !cloud_cancelled()) {
        int n = cloud_read(&resp, io, SSE_READ);
        if (n <= 0) break;
        cloud_progress();
        const char *p = io;
        size_t left = (size_t) n;
        sse_kind_t kind;
        while ((kind = sse_feed(&sse, &p, &left, delta, 1024)) != SSE_NONE) {
            if (kind == SSE_DONE) { done = true; break; }
            if (kind == SSE_ERROR) { err = ESP_FAIL; done = true; break; }
            if (kind == SSE_TEXT) {
                if (!st->llm_first_ms) st->llm_first_ms = cloud_now_ms() - t0;
                cloud_reply_append(st, delta);
                chunker_feed(&ck, delta);
                sse.quiet = false;
                // A long answer still goes by sentences: one piece holds 1 KB.
                while ((!whole || ck.len > 900) && chunker_next(&ck, piece, CLOUD_CHUNK_MAX)) {
                    cloud_speak_piece(st, piece);
                }
            }
        }
        if (whole && sse.quiet && !done && chunker_finish(&ck, piece, CLOUD_CHUNK_MAX)) {
            cloud_speak_piece(st, piece);
        }
    }

    const bool looked = sse.tool && strcmp(sse.tool_name, "look") == 0;
    if (sse.listen && slot != CLOUD_SLOT_LLM) {
        st->listen = true;
        ESP_LOGI(TAG, "the brain asked a question: the reply needs no wake word");
    }
    if (!looked && err == ESP_OK && done && chunker_finish(&ck, piece, CLOUD_CHUNK_MAX)) {
        cloud_speak_piece(st, piece);
    }
    st->llm_ms = cloud_now_ms() - t0;
    free(io);
    free(chunk_store);
    cloud_finish(slot, &resp, done && err == ESP_OK);

    if (cloud_cancelled()) return ESP_ERR_INVALID_STATE;
    if (err != ESP_OK) return err;
    if (!done) return ESP_FAIL;
    if (looked) return ESP_ERR_NOT_FINISHED;
    if (sse.tool) ESP_LOGW(TAG, "model called an unknown tool '%s'", sse.tool_name);
    return ESP_OK;
}

// The smallest real completion, for orion_cloud_test: one token, no stream.
esp_err_t cloud_llm_ping(void)
{
    // A second try when the server names max_completion_tokens: learned for
    // the turns too.
    for (int attempt = 0; attempt < 3; attempt++) {
        const cloud_cfg_t *cfg = cloud_cfg();
        jw_t w;
        if (!jw_init(&w, 256 + strlen(cfg->llm.model))) {
            return ESP_ERR_NO_MEM;
        }
        jw_raw(&w, "{");
        jw_kv_str(&w, "model", cfg->llm.model);
        // OpenAI's newer models spend tokens thinking first: one is not enough there.
        jw_raw(&w, cfg->llm_mct ? ",\"max_completion_tokens\":16" : ",\"max_tokens\":1");
        jw_raw(&w, think_field(cfg));
        jw_raw(&w, ",\"stream\":false,\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}");
        body_t body = { .body = w.buf, .len = w.len };
        cloud_req_t req = {
            .url = cfg->llm.url, .method = HTTP_METHOD_POST,
            .auth = cfg->llm.auth[0] ? cfg->llm.auth : NULL,
            .content_type = "application/json", .body_len = (int) w.len,
            .write_body = write_body, .ctx = &body,
        };
        cloud_resp_t resp;
        esp_err_t err = cloud_send(CLOUD_SLOT_LLM, &req, &resp);
        jw_free(&w);
        if (err != ESP_OK) {
            return err;
        }
        const int status = resp.status;
        if (status == 400) {
            char *msg = NULL;
            size_t n = 0;
            cloud_read_all(&resp, &msg, &n, 512);
            const bool mct = !cfg->llm_mct && msg && strstr(msg, "max_tokens") &&
                             strstr(msg, "max_completion_tokens");
            const bool think = cfg->llm_think != LLM_THINK_ASIS && cfg->llm_think != LLM_THINK_ROOM &&
                               msg && strstr(msg, "thinking");
            if (think) cloud_cfg_llm_thinks(msg);
            free(msg);
            cloud_finish(CLOUD_SLOT_LLM, &resp, false);
            if (mct) {
                cloud_cfg_llm_learned(false, true);
                continue;
            }
            if (think) {
                continue;
            }
            return ESP_FAIL;
        }
        cloud_finish(CLOUD_SLOT_LLM, &resp, true);
        return status == 200 ? ESP_OK : ESP_FAIL;
    }
    return ESP_FAIL;
}

static const char *brain_name(cloud_slot_t slot)
{
    return slot == CLOUD_SLOT_HUB ? "hub" : slot == CLOUD_SLOT_PC ? "pc" : "phone";
}

// An Orion Hub answers first, then the PC brain, then the phone's, then the
// board's own model.
// A brain that fails before a word has been spoken hands the same turn to the
// next one: a PC or a phone being off or busy must never leave Orion silent.
// The body is built for each target: a brain adds what it knows itself, the
// board's own model is told that it has no hands this turn.
static esp_err_t stream_turn(const char *text, bool tools, const uint8_t *jpeg, size_t jpeg_len,
                             cloud_reply_state_t *st)
{
    static const cloud_slot_t brains[] = { CLOUD_SLOT_HUB, CLOUD_SLOT_PC, CLOUD_SLOT_PHONE };
    bool tried = false;
    jw_t w;
    esp_err_t err;
    for (size_t i = 0; i < sizeof(brains) / sizeof(brains[0]); i++) {
        if (!cloud_brain_ready(brains[i])) {
            continue;
        }
        tried = true;
        if (!build(&w, text, tools, jpeg, jpeg_len, "")) {
            jw_free(&w);
            return ESP_ERR_NO_MEM;
        }
        err = stream_once(&w, st, brains[i]);
        jw_free(&w);
        if (err == ESP_OK || err == ESP_ERR_NOT_FINISHED || err == ESP_ERR_INVALID_STATE ||
            st->reply_len > 0) {
            return err;
        }
        ESP_LOGW(TAG, "%s brain failed (%s), trying the next", brain_name(brains[i]), esp_err_to_name(err));
        cloud_brain_failed(brains[i]);
        st->llm_first_ms = 0;
    }
    // Twice more at most: a server can refuse one field, then the other.
    for (int attempt = 0; attempt < 3; attempt++) {
        if (!build(&w, text, tools, jpeg, jpeg_len, tried ? NOTE_NO_ANSWER : NOTE_ALONE)) {
            jw_free(&w);
            return ESP_ERR_NO_MEM;
        }
        err = stream_once(&w, st, CLOUD_SLOT_LLM);
        jw_free(&w);
        if (err != ESP_ERR_INVALID_VERSION) return err;
    }
    return ESP_FAIL;
}

static volatile bool s_look_next;
static void (*s_progress)(void);
static uint32_t s_progress_ms;

void orion_cloud_on_progress(void (*cb)(void))
{
    s_progress = cb;
}

// At most every two seconds: anything read from the stream, a keep-alive
// comment from a brain that is still clicking through an app included.
// Also called while a reply plays: a long answer is a sign of life too.
void cloud_progress(void)
{
    const uint32_t now = cloud_now_ms();
    if (s_progress && now - s_progress_ms > 2000) {
        s_progress_ms = now;
        s_progress();
    }
}

void orion_cloud_look_next(void)
{
    s_look_next = true;
}

esp_err_t cloud_reply_run(const char *text, cloud_reply_state_t *st)
{
    const cloud_cfg_t *cfg = cloud_cfg();
    // Never "tool": a model with a look tool took pictures it was not asked for.
    // "off" turns even the words off; anything else is the words.
    const bool tool_mode = false;
    const bool asked = s_look_next;
    s_look_next = false;
    const bool look_first = asked || (strcmp(cfg->vision_mode, "off") != 0 && wants_camera(text));
    esp_err_t err = ESP_ERR_NOT_FINISHED;

    if (!look_first) {
        err = stream_turn(text, tool_mode, NULL, 0, st);
        if (err != ESP_ERR_NOT_FINISHED) return err;
        ESP_LOGI(TAG, "model called look after %u ms", (unsigned) st->llm_ms);
    } else {
        ESP_LOGI(TAG, "a question about what is in front: picture first");
    }

    uint8_t *jpeg = NULL;
    size_t jpeg_len = 0;
    if (orion_camera_capture_jpeg(&jpeg, &jpeg_len) != ESP_OK || !jpeg_len) {
        ESP_LOGW(TAG, "camera unavailable, answering without the picture");
        jpeg = NULL;
        jpeg_len = 0;
    } else {
        st->used_camera = true;
        ESP_LOGI(TAG, "%u byte jpeg for the model", (unsigned) jpeg_len);
    }
    // A copy, so the camera is free again while the model reads it: the frame
    // buffer is also what a viewer's stream is waiting on.
    uint8_t *copy = NULL;
    if (jpeg) {
        copy = cloud_psram_alloc(jpeg_len);
        if (copy) memcpy(copy, jpeg, jpeg_len);
        orion_camera_release();
        if (!copy) jpeg_len = 0;
    }
    err = stream_turn(text, false, copy, jpeg_len, st);
    free(copy);
    return err == ESP_ERR_NOT_FINISHED ? ESP_FAIL : err;
}
