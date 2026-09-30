// What the app asks the board to do, and what the board remembers of it:
// POST /api/talk, /api/talk/snapshot, /api/say and /api/stop, and
// GET /api/history. The contract is docs/DEVICE_PROTOCOL.md.
#include "api_priv.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_heap_caps.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "orion_api.h"

#define HISTORY_TURNS 40
#define TEXT_CAP      400
#define REPLY_CAP     1000

typedef struct {
    uint32_t turn;
    char at[24];
    char source[16];
    char transcript[TEXT_CAP];
    char reply[REPLY_CAP];
    uint32_t total_ms;
} turn_rec_t;

static orion_api_request_cb_t s_cb;
static const char *s_source = "wake";
static turn_rec_t *s_hist;          // PSRAM ring, newest at s_head - 1
static int s_head;
static int s_count;
static SemaphoreHandle_t s_mu;

void orion_api_on_request(orion_api_request_cb_t cb)
{
    s_cb = cb;
}

void api_set_source(const char *source)
{
    s_source = source;
}

const char *api_take_source(void)
{
    const char *s = s_source;
    s_source = "wake";
    return s;
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------
static bool hist_ready(void)
{
    if (!s_mu) {
        s_mu = xSemaphoreCreateMutex();
    }
    if (!s_hist) {
        s_hist = heap_caps_calloc(HISTORY_TURNS, sizeof(turn_rec_t), MALLOC_CAP_SPIRAM);
    }
    return s_mu && s_hist;
}

static turn_rec_t *find(uint32_t turn)
{
    for (int i = 0; i < s_count; i++) {
        turn_rec_t *r = &s_hist[(s_head - 1 - i + HISTORY_TURNS) % HISTORY_TURNS];
        if (r->turn == turn) {
            return r;
        }
    }
    return NULL;
}

void api_history_turn_start(uint32_t turn, const char *source)
{
    if (!hist_ready()) {
        return;
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    turn_rec_t *r = &s_hist[s_head];
    memset(r, 0, sizeof(*r));
    r->turn = turn;
    api_iso_time(r->at, sizeof(r->at));
    strlcpy(r->source, source, sizeof(r->source));
    s_head = (s_head + 1) % HISTORY_TURNS;
    if (s_count < HISTORY_TURNS) {
        s_count++;
    }
    xSemaphoreGive(s_mu);
}

void api_history_text(uint32_t turn, bool user, const char *text)
{
    if (!hist_ready()) {
        return;
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    turn_rec_t *r = find(turn);
    if (r) {
        if (user) {
            strlcpy(r->transcript, text, sizeof(r->transcript));
        } else {
            strlcpy(r->reply, text, sizeof(r->reply));
        }
    }
    xSemaphoreGive(s_mu);
}

void api_history_turn_end(uint32_t turn, uint32_t total_ms)
{
    if (!hist_ready()) {
        return;
    }
    xSemaphoreTake(s_mu, portMAX_DELAY);
    turn_rec_t *r = find(turn);
    if (r) {
        r->total_ms = total_ms;
    }
    xSemaphoreGive(s_mu);
}

static esp_err_t h_history(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char q[64] = "";
    char v[16] = "";
    int limit = 20;
    uint32_t before = UINT32_MAX;
    httpd_req_get_url_query_str(req, q, sizeof(q));
    if (httpd_query_key_value(q, "limit", v, sizeof(v)) == ESP_OK) {
        limit = atoi(v);
    }
    if (httpd_query_key_value(q, "before", v, sizeof(v)) == ESP_OK && v[0] == 't') {
        before = (uint32_t) strtoul(v + 2, NULL, 10);
    }
    if (limit < 1 || limit > HISTORY_TURNS) {
        limit = 20;
    }

    cJSON *root = cJSON_CreateObject();
    cJSON *turns = cJSON_AddArrayToObject(root, "turns");
    uint32_t last = 0;
    int n = 0;
    if (hist_ready()) {
        xSemaphoreTake(s_mu, portMAX_DELAY);
        for (int i = 0; i < s_count && n < limit; i++) {
            const turn_rec_t *r = &s_hist[(s_head - 1 - i + HISTORY_TURNS) % HISTORY_TURNS];
            // A turn that never got a word from either side is a wake word
            // that heard nothing: not a conversation.
            if (r->turn >= before || (!r->transcript[0] && !r->reply[0])) {
                continue;
            }
            char id[16];
            snprintf(id, sizeof(id), "t_%05u", (unsigned) r->turn);
            cJSON *t = cJSON_CreateObject();
            cJSON_AddStringToObject(t, "id", id);
            cJSON_AddStringToObject(t, "started_at", r->at);
            cJSON_AddStringToObject(t, "transcript", r->transcript);
            cJSON_AddStringToObject(t, "reply", r->reply);
            cJSON_AddBoolToObject(t, "had_image", strcmp(r->source, "app_snapshot") == 0);
            cJSON_AddArrayToObject(t, "tool_calls");
            cJSON *timings = cJSON_AddObjectToObject(t, "timings_ms");
            cJSON_AddNumberToObject(timings, "total", r->total_ms);
            cJSON_AddItemToArray(turns, t);
            last = r->turn;
            n++;
        }
        xSemaphoreGive(s_mu);
    }
    if (n == limit && last > 1) {
        char id[16];
        snprintf(id, sizeof(id), "t_%05u", (unsigned) last);
        cJSON_AddStringToObject(root, "next_before", id);
    } else {
        cJSON_AddNullToObject(root, "next_before");
    }
    char *json = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    api_send_json(req, "200 OK", json ? json : "{\"turns\":[]}");
    free(json);
    return ESP_OK;
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------
// The body's "text", when there is one. False on a body that is not JSON.
static bool body_text(httpd_req_t *req, char *out, size_t len)
{
    out[0] = '\0';
    if (req->content_len == 0) {
        return true;
    }
    if (req->content_len >= 1024) {
        return false;
    }
    char body[1024];
    int got = httpd_req_recv(req, body, req->content_len);
    if (got <= 0) {
        return false;
    }
    body[got] = '\0';
    cJSON *root = cJSON_Parse(body);
    if (!root) {
        return false;
    }
    const cJSON *t = cJSON_GetObjectItem(root, "text");
    if (cJSON_IsString(t)) {
        strlcpy(out, t->valuestring, len);
    }
    cJSON_Delete(root);
    return true;
}

static esp_err_t ask(httpd_req_t *req, orion_api_request_t what)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char text[512];
    if (!body_text(req, text, sizeof(text))) {
        api_send_json(req, "400 Bad Request", "{\"error\":\"bad_request\",\"message\":\"body must be JSON\"}");
        return ESP_OK;
    }
    if (what == ORION_API_SAY && !text[0]) {
        api_send_json(req, "400 Bad Request", "{\"error\":\"bad_request\",\"message\":\"text is required\"}");
        return ESP_OK;
    }
    const uint32_t turn = api_next_turn();
    if (what == ORION_API_TALK || what == ORION_API_SNAPSHOT) {
        api_set_source(what == ORION_API_SNAPSHOT ? "app_snapshot" : "app");
    }
    if (!s_cb || !s_cb(what, text[0] ? text : NULL)) {
        api_set_source("wake");
        api_send_json(req, "409 Conflict", "{\"error\":\"busy\",\"message\":\"Orion is in the middle of a turn\"}");
        return ESP_OK;
    }
    char out[48];
    if (what == ORION_API_STOP || what == ORION_API_SAY) {
        snprintf(out, sizeof(out), "{\"ok\":true}");
    } else {
        snprintf(out, sizeof(out), "{\"turn_id\":\"t_%05u\"}", (unsigned) turn);
    }
    api_send_json(req, "200 OK", out);
    return ESP_OK;
}

static esp_err_t h_talk(httpd_req_t *req)     { return ask(req, ORION_API_TALK); }
static esp_err_t h_snapshot(httpd_req_t *req) { return ask(req, ORION_API_SNAPSHOT); }
static esp_err_t h_say(httpd_req_t *req)      { return ask(req, ORION_API_SAY); }
static esp_err_t h_stop(httpd_req_t *req)     { return ask(req, ORION_API_STOP); }

void api_talk_register(httpd_handle_t hd)
{
    hist_ready();
    const httpd_uri_t uris[] = {
        { .uri = "/api/talk",          .method = HTTP_POST, .handler = h_talk },
        { .uri = "/api/talk/snapshot", .method = HTTP_POST, .handler = h_snapshot },
        { .uri = "/api/say",           .method = HTTP_POST, .handler = h_say },
        { .uri = "/api/stop",          .method = HTTP_POST, .handler = h_stop },
        { .uri = "/api/history",       .method = HTTP_GET,  .handler = h_history },
    };
    for (size_t i = 0; i < sizeof(uris) / sizeof(uris[0]); i++) {
        httpd_register_uri_handler(hd, &uris[i]);
    }
}
