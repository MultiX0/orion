// /ws: the app connects with ?token=, gets a full state event, then deltas
// pushed by orion_api_publish_*. The server's socket table says which fds are
// WebSockets. On top of that, ?client=pc|phone makes the socket a link: the
// screen shows which apps are here, and a phone that adds ?brain=host:port
// answers turns while it stays linked.
#include "api_priv.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

#include "orion_api.h"

static const char *TAG = "orion_api";

// Which sockets passed the token check at the handshake. lwIP fds are
// integers below FD_SETSIZE (its socket offset is FD_SETSIZE minus the
// socket count).
static bool s_auth[FD_SETSIZE];

static bool fd_ok(int fd)
{
    return fd >= 0 && fd < (int) (sizeof(s_auth) / sizeof(s_auth[0]));
}

// ---------------------------------------------------------------------------
// Links
// ---------------------------------------------------------------------------
#define LINKS_MAX      4
#define LINK_SILENT_US (15 * 1000000LL)   // the apps ping every 5 s

enum { KIND_NONE = 0, KIND_PC, KIND_PHONE };

typedef struct {
    int fd;
    uint8_t kind;
    int64_t seen_us;
    char brain[48];
    char token[65];
} link_t;

static link_t s_links[LINKS_MAX];
static SemaphoreHandle_t s_mu;
static esp_timer_handle_t s_watch;
static orion_api_links_t s_last;
static orion_api_links_cb_t s_links_cb;

void orion_api_on_links(orion_api_links_cb_t cb)
{
    s_links_cb = cb;
}

// In place: "%3A" to ":" and "+" to " ". httpd_query_key_value hands the
// value back still encoded, and Dart encodes the colon of host:port.
static void url_decode(char *s)
{
    char *out = s;
    for (const char *p = s; *p; p++) {
        if (*p == '%' && isxdigit((unsigned char) p[1]) && isxdigit((unsigned char) p[2])) {
            const char hex[3] = { p[1], p[2], 0 };
            *out++ = (char) strtol(hex, NULL, 16);
            p += 2;
        } else {
            *out++ = *p == '+' ? ' ' : *p;
        }
    }
    *out = '\0';
}

// host:port, a dotted name or address and a port, nothing else.
static bool brain_ok(const char *b)
{
    if (!b[0] || !strchr(b, ':')) {
        return false;
    }
    for (const char *p = b; *p; p++) {
        if (!isalnum((unsigned char) *p) && *p != '.' && *p != ':' && *p != '-') {
            return false;
        }
    }
    return true;
}

// Works out who is here and tells main when that changed. Any task.
static void publish_links(void)
{
    orion_api_links_t now = {0};
    xSemaphoreTake(s_mu, portMAX_DELAY);
    for (int i = 0; i < LINKS_MAX; i++) {
        const link_t *l = &s_links[i];
        if (l->kind == KIND_PC) {
            now.pc = true;
        } else if (l->kind == KIND_PHONE) {
            now.phone = true;
            if (l->brain[0] && !now.phone_brain[0]) {
                strlcpy(now.phone_brain, l->brain, sizeof(now.phone_brain));
                strlcpy(now.phone_token, l->token, sizeof(now.phone_token));
            }
        }
    }
    const bool changed = now.pc != s_last.pc || now.phone != s_last.phone ||
                         strcmp(now.phone_brain, s_last.phone_brain) != 0 ||
                         strcmp(now.phone_token, s_last.phone_token) != 0;
    s_last = now;
    xSemaphoreGive(s_mu);
    if (changed) {
        ESP_LOGI(TAG, "links: pc %s, phone %s%s%s", now.pc ? "on" : "off", now.phone ? "on" : "off",
                 now.phone_brain[0] ? ", brain " : "", now.phone_brain);
        if (s_links_cb) {
            s_links_cb(&now);
        }
    }
    memset(&now, 0, sizeof(now));
}

static void link_add(int fd, uint8_t kind, const char *brain, const char *token)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    link_t *slot = NULL;
    for (int i = 0; i < LINKS_MAX && !slot; i++) {
        if (s_links[i].kind && s_links[i].fd == fd) {
            slot = &s_links[i];
        }
    }
    for (int i = 0; i < LINKS_MAX && !slot; i++) {
        if (!s_links[i].kind) {
            slot = &s_links[i];
        }
    }
    if (slot) {
        memset(slot, 0, sizeof(*slot));
        slot->fd = fd;
        slot->kind = kind;
        slot->seen_us = esp_timer_get_time();
        if (brain_ok(brain)) {
            strlcpy(slot->brain, brain, sizeof(slot->brain));
            strlcpy(slot->token, token, sizeof(slot->token));
        }
    }
    xSemaphoreGive(s_mu);
    publish_links();
}

static void link_seen(int fd)
{
    xSemaphoreTake(s_mu, portMAX_DELAY);
    for (int i = 0; i < LINKS_MAX; i++) {
        if (s_links[i].kind && s_links[i].fd == fd) {
            s_links[i].seen_us = esp_timer_get_time();
        }
    }
    xSemaphoreGive(s_mu);
}

// Once a second: a link whose socket closed goes at once, a silent one after
// 15 s, since a phone that lost Wi-Fi never says goodbye.
static void watch(void *arg)
{
    (void) arg;
    httpd_handle_t hd = api_http_handle();
    const int64_t now = esp_timer_get_time();
    int stale[LINKS_MAX];
    int n_stale = 0;
    xSemaphoreTake(s_mu, portMAX_DELAY);
    for (int i = 0; i < LINKS_MAX; i++) {
        link_t *l = &s_links[i];
        if (!l->kind) {
            continue;
        }
        const bool open = hd && httpd_ws_get_fd_info(hd, l->fd) == HTTPD_WS_CLIENT_WEBSOCKET;
        const bool silent = now - l->seen_us > LINK_SILENT_US;
        if (!open || silent) {
            if (open) {
                stale[n_stale++] = l->fd;
            }
            memset(l, 0, sizeof(*l));
        }
    }
    xSemaphoreGive(s_mu);
    for (int i = 0; i < n_stale; i++) {
        httpd_sess_trigger_close(hd, stale[i]);
    }
    publish_links();
}

void api_ws_links_start(void)
{
    if (!s_mu) {
        s_mu = xSemaphoreCreateMutex();
    }
    if (!s_watch) {
        const esp_timer_create_args_t a = { .callback = watch, .name = "ws_links" };
        esp_timer_create(&a, &s_watch);
    }
    if (s_watch) {
        esp_timer_start_periodic(s_watch, 1000000);
    }
}

void api_ws_links_stop(void)
{
    if (s_watch) {
        esp_timer_stop(s_watch);
    }
    if (s_mu) {
        xSemaphoreTake(s_mu, portMAX_DELAY);
        memset(s_links, 0, sizeof(s_links));
        xSemaphoreGive(s_mu);
        publish_links();
    }
}

static esp_err_t send_text(httpd_req_t *req, const char *json)
{
    httpd_ws_frame_t f = {
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *) json,
        .len = strlen(json),
    };
    return httpd_ws_send_frame(req, &f);
}

// Handshake done. The token rides in the query because browsers and most
// WebSocket clients cannot set headers. ESP-IDF 5.5 no longer calls the URI
// handler for the handshake, only this callback, so the token check lives
// here. Without it no link passes the check and the first ping closes every
// socket.
static esp_err_t ws_open(httpd_req_t *req)
{
    char q[256] = "";
    char tok[80] = "";
    char client[12] = "";
    char brain[48] = "";
    httpd_req_get_url_query_str(req, q, sizeof(q));
    httpd_query_key_value(q, "token", tok, sizeof(tok));
    httpd_query_key_value(q, "client", client, sizeof(client));
    httpd_query_key_value(q, "brain", brain, sizeof(brain));
    url_decode(tok);
    url_decode(client);
    url_decode(brain);
    int fd = httpd_req_to_sockfd(req);
    bool ok = api_token_ok(tok);
    if (fd_ok(fd)) {
        s_auth[fd] = ok;
    }
    if (!ok) {
        send_text(req, "{\"type\":\"error\",\"code\":\"unauthorized\",\"message\":\"bad token\"}");
        httpd_sess_trigger_close(req->handle, fd);
        return ESP_OK;
    }
    char ts[24];
    char fields[240];
    char body[300];
    api_iso_time(ts, sizeof(ts));
    api_state_fields(fields, sizeof(fields));
    snprintf(body, sizeof(body), "{\"type\":\"state\",\"ts\":\"%s\",%s}", ts, fields);
    ESP_LOGI(TAG, "ws client on fd %d%s%s", fd, client[0] ? ", " : "", client);
    esp_err_t err = send_text(req, body);
    if (strcmp(client, "pc") == 0) {
        link_add(fd, KIND_PC, "", "");
    } else if (strcmp(client, "phone") == 0) {
        link_add(fd, KIND_PHONE, brain, tok);
    }
    memset(tok, 0, sizeof(tok));
    return err;
}

static esp_err_t h_ws(httpd_req_t *req)
{
    if (req->method == HTTP_GET) {
        return ws_open(req);   // an IDF that still calls the handler for it
    }

    int fd = httpd_req_to_sockfd(req);
    if (!fd_ok(fd) || !s_auth[fd]) {
        httpd_sess_trigger_close(req->handle, fd);
        return ESP_OK;
    }
    httpd_ws_frame_t f = { .type = HTTPD_WS_TYPE_TEXT };
    esp_err_t err = httpd_ws_recv_frame(req, &f, 0);
    if (err != ESP_OK) {
        return err;
    }
    char buf[128] = "";
    if (f.len > 0 && f.len < sizeof(buf)) {
        f.payload = (uint8_t *) buf;
        err = httpd_ws_recv_frame(req, &f, f.len);
        if (err != ESP_OK) {
            return err;
        }
        buf[f.len] = '\0';
    }
    link_seen(fd);
    if (f.type == HTTPD_WS_TYPE_TEXT && strstr(buf, "\"ping\"")) {
        return send_text(req, "{\"type\":\"pong\"}");
    }
    return ESP_OK;
}

void api_ws_broadcast(const char *json)
{
    httpd_handle_t hd = api_http_handle();
    if (!hd) {
        return;
    }
    int fds[CONFIG_LWIP_MAX_SOCKETS];
    size_t n = CONFIG_LWIP_MAX_SOCKETS;
    if (httpd_get_client_list(hd, &n, fds) != ESP_OK) {
        return;
    }
    httpd_ws_frame_t f = {
        .type = HTTPD_WS_TYPE_TEXT,
        .payload = (uint8_t *) json,
        .len = strlen(json),
    };
    for (size_t i = 0; i < n; i++) {
        if (httpd_ws_get_fd_info(hd, fds[i]) == HTTPD_WS_CLIENT_WEBSOCKET &&
            fd_ok(fds[i]) && s_auth[fds[i]]) {
            httpd_ws_send_data(hd, fds[i], &f);
        }
    }
}

esp_err_t api_ws_register(httpd_handle_t hd)
{
    // Before the handler exists, so no handshake can find it missing.
    if (!s_mu) {
        s_mu = xSemaphoreCreateMutex();
    }
    const httpd_uri_t ws = {
        .uri = "/ws",
        .method = HTTP_GET,
        .handler = h_ws,
        .is_websocket = true,
        .ws_post_handshake_cb = ws_open,
    };
    return httpd_register_uri_handler(hd, &ws);
}
