// The HTTP layer every cloud call goes through: one kept alive connection
// per stage, or per host for speech to text and text to speech (see
// cloud_net_bind), a lock per connection, and one retry when a kept alive
// connection turns out to be dead.
//
// A response ends by reading it to the last byte and leaving the socket open,
// so the next open() on the same handle skips the TLS handshake.
//
// TLS always verifies against the ESP-IDF certificate bundle.

#include "cloud_private.h"

#include <ctype.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "esp_crt_bundle.h"
#include "esp_log.h"
#include "lwip/sockets.h"

static const char *TAG = "cloud_net";

// Just over 4 KB on purpose: malloc keeps anything of 4096 bytes or less in
// internal RAM (SPIRAM_MALLOC_ALWAYSINTERNAL); at this size both land in PSRAM.
#define HTTP_BUF 4352

#define HTTP_TIMEOUT_MS 30000   // a whole request, a response streaming for seconds too

typedef struct {
    esp_http_client_handle_t c;
    SemaphoreHandle_t lock;
    bool live;              // the last response left this socket open
    int last_status;        // HTTP status of the last request, 0 if none came back
    esp_err_t last_err;     // how the last request failed, when it did
    char origin[128];       // scheme://host:port the client was made for
    int timeout_ms;         // 0: HTTP_TIMEOUT_MS
} slot_t;

static slot_t s_slots[CLOUD_SLOT_COUNT];
static cloud_slot_t s_owner[CLOUD_SLOT_COUNT];  // whose connection each stage uses

static slot_t *slot_of(cloud_slot_t stage)
{
    return &s_slots[s_owner[stage]];
}

esp_err_t cloud_net_init(void)
{
    for (int i = 0; i < CLOUD_SLOT_COUNT; i++) {
        s_owner[i] = (cloud_slot_t) i;
        if (!s_slots[i].lock) {
            s_slots[i].lock = xSemaphoreCreateMutex();
            if (!s_slots[i].lock) {
                return ESP_ERR_NO_MEM;
            }
        }
    }
    cloud_net_bind();
    return ESP_OK;
}

static esp_err_t noop_event(esp_http_client_event_t *evt)
{
    (void) evt;
    return ESP_OK;
}

// "https://host:port/path" -> "https://host:port", lower case.
static void origin_of(const char *url, char *out, size_t len)
{
    const char *host = strstr(url, "://");
    host = host ? host + 3 : url;
    const char *slash = strchr(host, '/');
    const size_t n = slash ? (size_t) (slash - url) : strlen(url);
    snprintf(out, len, "%.*s", (int) n, url);
    for (char *p = out; *p; p++) *p = (char) tolower((unsigned char) *p);
}

// One client per slot, bound to one host. A request for another host, after a
// config change, gets a fresh client instead of a socket to the old one.
static esp_http_client_handle_t client_for(slot_t *s, const char *url)
{
    char origin[sizeof(s->origin)];
    origin_of(url, origin, sizeof(origin));
    if (s->c && strcmp(origin, s->origin) != 0) {
        esp_http_client_cleanup(s->c);
        s->c = NULL;
    }
    if (!s->c) {
        strlcpy(s->origin, origin, sizeof(s->origin));
        esp_http_client_config_t cfg = {
            .url = url,
            .crt_bundle_attach = esp_crt_bundle_attach,
            .keep_alive_enable = true,
            .timeout_ms = s->timeout_ms ? s->timeout_ms : HTTP_TIMEOUT_MS,
            .buffer_size = HTTP_BUF,
            .buffer_size_tx = HTTP_BUF,
            .event_handler = noop_event,
            .disable_auto_redirect = true,
        };
        s->c = esp_http_client_init(&cfg);
        s->live = false;
    } else if (esp_http_client_set_url(s->c, url) != ESP_OK) {
        return NULL;
    }
    return s->c;
}

static void drop_socket(slot_t *s)
{
    if (s->c) {
        esp_http_client_close(s->c);
    }
    s->live = false;
}

// Request line and headers out. body_len -1 sends the body chunked.
static esp_err_t open_request(slot_t *s, const cloud_req_t *req, cloud_resp_t *resp)
{
    esp_http_client_handle_t c = client_for(s, req->url);
    if (!c) {
        return ESP_ERR_NO_MEM;
    }
    esp_http_client_set_method(c, req->method);
    if (req->auth) esp_http_client_set_header(c, "Authorization", req->auth);
    if (req->content_type) esp_http_client_set_header(c, "Content-Type", req->content_type);
    else esp_http_client_delete_header(c, "Content-Type");
    if (req->model) esp_http_client_set_header(c, "model", req->model);
    else esp_http_client_delete_header(c, "model");

    resp->c = c;
    resp->reused = s->live;
    resp->t0 = cloud_now_ms();

    esp_err_t err = esp_http_client_open(c, req->body_len);
    const uint32_t opened = cloud_now_ms() - resp->t0;
    resp->connect_ms = resp->reused ? 0 : opened;
    if (err != ESP_OK) {
        return err;
    }
    // Headers and body go out as separate TLS records, the body in 4 KB pieces,
    // and each record ends in a short segment. With Nagle on, a short segment
    // waits for the ACK of everything before it: a round trip, about 200 ms
    // from here to either host, spent doing nothing.
    const int sock = esp_http_client_get_socket(c);
    if (sock >= 0) {
        const int one = 1;
        setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
    return ESP_OK;
}

static esp_err_t response_headers(cloud_resp_t *resp)
{
    if (esp_http_client_fetch_headers(resp->c) < 0) {
        return ESP_FAIL;
    }
    resp->status = esp_http_client_get_status_code(resp->c);
    resp->send_ms = cloud_now_ms() - resp->t0;
    return resp->status > 0 ? ESP_OK : ESP_FAIL;
}

// One attempt: headers, open, body, response headers.
static esp_err_t attempt(slot_t *s, const cloud_req_t *req, cloud_resp_t *resp)
{
    esp_err_t err = open_request(s, req, resp);
    if (err != ESP_OK) {
        return err;
    }
    if (req->write_body && req->body_len > 0) {
        err = req->write_body(resp->c, req->ctx);
        if (err != ESP_OK) {
            return err;
        }
    }
    return response_headers(resp);
}

esp_err_t cloud_open_stream(cloud_slot_t slot, const cloud_req_t *req, cloud_resp_t *resp)
{
    if (slot >= CLOUD_SLOT_COUNT || xSemaphoreTake(slot_of(slot)->lock,
                                                   pdMS_TO_TICKS(HTTP_TIMEOUT_MS)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    slot_t *s = slot_of(slot);
    memset(resp, 0, sizeof(*resp));
    cloud_req_t chunked = *req;
    chunked.body_len = -1;
    esp_err_t err = open_request(s, &chunked, resp);
    if (err != ESP_OK && resp->reused) {
        ESP_LOGW(TAG, "kept alive socket was dead (%s), reconnecting", esp_err_to_name(err));
        drop_socket(s);
        err = open_request(s, &chunked, resp);
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "%s: %s", req->url, esp_err_to_name(err));
        drop_socket(s);
        xSemaphoreGive(s->lock);
    }
    return err;
}

esp_err_t cloud_stream_response(cloud_resp_t *resp)
{
    return response_headers(resp);
}

esp_err_t cloud_send(cloud_slot_t slot, const cloud_req_t *req, cloud_resp_t *resp)
{
    if (slot >= CLOUD_SLOT_COUNT || xSemaphoreTake(slot_of(slot)->lock,
                                                   pdMS_TO_TICKS(HTTP_TIMEOUT_MS)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    slot_t *s = slot_of(slot);
    memset(resp, 0, sizeof(*resp));
    resp->head = req->method == HTTP_METHOD_HEAD;

    esp_err_t err = attempt(s, req, resp);
    if (err != ESP_OK && resp->reused) {
        // The server closed our idle connection. DeepInfra does that somewhere
        // between 60 and 90 s, measured. Throw it away and go again on a fresh
        // one, once: a second failure on a new socket is a real failure.
        ESP_LOGW(TAG, "kept alive socket was dead (%s), reconnecting", esp_err_to_name(err));
        drop_socket(s);
        err = attempt(s, req, resp);
    }
    s->last_status = resp->status;
    s->last_err = err;
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "%s: %s", req->url, esp_err_to_name(err));
        drop_socket(s);
        xSemaphoreGive(s->lock);
        return err;
    }
    return ESP_OK;
}

void cloud_last_result(cloud_slot_t slot, int *status, esp_err_t *err)
{
    *status = slot_of(slot)->last_status;
    *err = slot_of(slot)->last_err;
}

// The PC slot: a short timeout for its health check, so a PC that is off costs
// seconds, not the 30 of a whole request; a long one for a turn, which may run
// tools before its first word. Only the LLM worker uses that slot.
void cloud_net_set_timeout(cloud_slot_t stage, int ms)
{
    slot_t *s = slot_of(stage);
    s->timeout_ms = ms;
    if (s->c) {
        esp_http_client_set_timeout_ms(s->c, ms);
    }
}

bool cloud_net_shared(cloud_slot_t stage)
{
    return s_owner[stage] != stage;
}

// After a load or reload: which connection each stage uses. Speech to text and
// text to speech on one host share a connection, since a turn transcribes
// before it replies and a third TLS session costs about 4 KB of internal RAM,
// measured. The language model never shares: its stream and the speech
// requests overlap on every reply. A connection whose stage moved to another
// host, or that nobody uses now, closes here rather than at its next request;
// one whose host is unchanged stays warm.
void cloud_net_bind(void)
{
    for (int i = 0; i < CLOUD_SLOT_COUNT; i++) xSemaphoreTake(s_slots[i].lock, portMAX_DELAY);
    const bool share = strcmp(cloud_slot_stage(CLOUD_SLOT_STT)->origin,
                              cloud_slot_stage(CLOUD_SLOT_TTS)->origin) == 0;
    s_owner[CLOUD_SLOT_TTS] = share ? CLOUD_SLOT_STT : CLOUD_SLOT_TTS;
    for (int i = 0; i < CLOUD_SLOT_COUNT; i++) {
        slot_t *s = &s_slots[i];
        const char *origin = cloud_slot_stage((cloud_slot_t) i)->origin;
        const bool used = s_owner[i] == (cloud_slot_t) i;
        if (s->c && (!used || strcmp(s->origin, origin) != 0)) {
            ESP_LOGI(TAG, "slot %d leaves %s for %s", i, s->origin, used ? origin : "none");
            esp_http_client_cleanup(s->c);
            s->c = NULL;
            s->live = false;
        }
    }
    for (int i = CLOUD_SLOT_COUNT - 1; i >= 0; i--) xSemaphoreGive(s_slots[i].lock);
    ESP_LOGI(TAG, "speech to text and text to speech %s", share ? "share a connection" : "apart");
}

int cloud_read(cloud_resp_t *resp, char *buf, int len)
{
    return esp_http_client_read(resp->c, buf, len);
}

void cloud_finish(cloud_slot_t slot, cloud_resp_t *resp, bool keep)
{
    slot_t *s = slot_of(slot);
    if (keep && !resp->head) {
        // Anything left unread would be taken as the start of the next response,
        // so a response is only kept once it has been read to the end. Read,
        // not esp_http_client_flush_response: flushing counts the body it
        // skips into the client's cached length without keeping the bytes, and
        // outside perform() nothing resets that count, so the next response's
        // first read copies from a NULL buffer and crashes. A PC health check,
        // whose body is never read, would do exactly that.
        char scrap[256];
        while (esp_http_client_read(resp->c, scrap, sizeof(scrap)) > 0) {
        }
        keep = esp_http_client_is_complete_data_received(resp->c);
    }
    keep = keep && esp_http_client_is_persistent_connection(resp->c);
    if (keep) {
        s->live = true;
    } else {
        drop_socket(s);
    }
    xSemaphoreGive(s->lock);
}
