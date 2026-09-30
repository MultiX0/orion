// The HTTP server and the REST handlers: /api/info, /api/state,
// /api/provision, /api/restart (config is in api_config.c, pairing in
// api_pair.c). The task stack is in PSRAM, which is why the provisioning
// write is handed to the event loop instead of done here.
#include "api_priv.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_timer.h"

#include "orion_net.h"
#include "orion_settings.h"

static const char *TAG = "orion_api";

static httpd_handle_t s_hd;

httpd_handle_t api_http_handle(void)
{
    return s_hd;
}

void api_send_json(httpd_req_t *req, const char *status, const char *json)
{
    httpd_resp_set_status(req, status);
    httpd_resp_set_type(req, HTTPD_TYPE_JSON);
    httpd_resp_send(req, json, HTTPD_RESP_USE_STRLEN);
}

static void send_error(httpd_req_t *req, const char *status, const char *code, const char *msg)
{
    char body[160];
    snprintf(body, sizeof(body), "{\"error\":\"%s\",\"message\":\"%s\"}", code, msg);
    api_send_json(req, status, body);
}

bool api_authorized(httpd_req_t *req)
{
    char tok[80] = "";
    if (httpd_req_get_hdr_value_str(req, "X-Orion-Token", tok, sizeof(tok)) != ESP_OK) {
        char q[128] = "";
        httpd_req_get_url_query_str(req, q, sizeof(q));
        httpd_query_key_value(q, "token", tok, sizeof(tok));
    }
    if (api_token_ok(tok)) {
        return true;
    }
    send_error(req, "401 Unauthorized", "unauthorized", "missing or wrong X-Orion-Token");
    return false;
}

// No token: discovery confirms a board with this before the app holds one,
// right after Bluetooth setup included, and it says nothing the mDNS record
// does not already advertise. Everything else needs X-Orion-Token.
static esp_err_t h_info(httpd_req_t *req)
{
    char ip[16] = "";
    char name[33];
    char esc[80];
    orion_net_ip(ip, sizeof(ip));
    api_device_name(name, sizeof(name));
    api_json_escape(esc, sizeof(esc), name);
    char body[512];
    snprintf(body, sizeof(body),
             "{\"device_id\":\"%s\",\"name\":\"%s\",\"fw_version\":\"%s\",\"hw\":\"t-cameraplus-s3\","
             "\"ip\":\"%s\",\"uptime_s\":%lld,\"has_camera\":true,\"config_version\":%d,"
             "\"providers\":%s,\"source\":\"https://github.com/MultiX0\"}",
             api_device_id(), esc, api_fw_version(), ip, esp_timer_get_time() / 1000000,
             ORION_SETTINGS_CONFIG_VERSION, ORION_SETTINGS_PROVIDERS);
    api_send_json(req, "200 OK", body);
    return ESP_OK;
}

static esp_err_t h_state(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char fields[240];
    char body[256];
    api_state_fields(fields, sizeof(fields));
    snprintf(body, sizeof(body), "{%s}", fields);
    api_send_json(req, "200 OK", body);
    return ESP_OK;
}

// Copies a JSON string field when it is within [min, max] bytes.
static bool take_str(const cJSON *root, const char *key, char *out, size_t out_len,
                     size_t min, size_t max)
{
    const cJSON *v = cJSON_GetObjectItem(root, key);
    if (!cJSON_IsString(v)) {
        return false;
    }
    size_t n = strlen(v->valuestring);
    if (n < min || n > max || n >= out_len) {
        return false;
    }
    strlcpy(out, v->valuestring, out_len);
    return true;
}

static esp_err_t h_provision(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char body[512];
    if (req->content_len == 0 || req->content_len >= sizeof(body)) {
        send_error(req, "400 Bad Request", "bad_request", "body must be under 512 bytes");
        return ESP_OK;
    }
    int got = httpd_req_recv(req, body, req->content_len);
    if (got <= 0) {
        return ESP_FAIL;
    }
    body[got] = '\0';

    api_provision_t m = {0};
    cJSON *root = cJSON_Parse(body);
    bool ok = take_str(root, "wifi_ssid", m.ssid, sizeof(m.ssid), 1, 32);
    take_str(root, "wifi_password", m.pass, sizeof(m.pass), 0, 63);
    const cJSON *tok = cJSON_GetObjectItem(root, "app_token");
    if (tok && !take_str(root, "app_token", m.token, sizeof(m.token), 8, 64)) {
        ok = false;
    }
    take_str(root, "device_name", m.name, sizeof(m.name), 1, 32);
    cJSON_Delete(root);
    memset(body, 0, sizeof(body));

    if (!ok) {
        memset(&m, 0, sizeof(m));
        send_error(req, "400 Bad Request", "bad_request",
                   "wifi_ssid 1 to 32 chars, wifi_password up to 63, app_token 8 to 64");
        return ESP_OK;
    }
    esp_err_t err = api_post_provision(&m);
    memset(&m, 0, sizeof(m));
    if (err != ESP_OK) {
        send_error(req, "503 Service Unavailable", "busy", "could not queue the change");
        return ESP_OK;
    }
    char out[80];
    snprintf(out, sizeof(out), "{\"device_id\":\"%s\",\"ok\":true}", api_device_id());
    api_send_json(req, "200 OK", out);
    return ESP_OK;
}

static void restart_cb(void *arg)
{
    (void) arg;
    esp_restart();
}

static esp_err_t h_restart(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    api_send_json(req, "200 OK", "{\"ok\":true}");
    // Let the response leave the socket before the chip resets.
    static esp_timer_handle_t t;
    const esp_timer_create_args_t a = { .callback = restart_cb, .name = "api_restart" };
    if (t || esp_timer_create(&a, &t) == ESP_OK) {
        esp_timer_start_once(t, 300000);
    }
    return ESP_OK;
}

esp_err_t api_http_start(void)
{
    if (s_hd) {
        return ESP_OK;
    }
    httpd_config_t c = HTTPD_DEFAULT_CONFIG();
    c.server_port = API_PORT;
    c.stack_size = 8192;
    c.task_caps = MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT;
    // A phone and a PC each hold a /ws link and a keep-alive socket, and the
    // camera stream is one more. With 5 sockets the LRU purge closes live links.
    c.max_open_sockets = 8;
    c.max_uri_handlers = 24;
    c.lru_purge_enable = true;
    esp_err_t err = httpd_start(&s_hd, &c);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "httpd start: %s", esp_err_to_name(err));
        s_hd = NULL;
        return err;
    }
    const httpd_uri_t uris[] = {
        { .uri = "/api/info",      .method = HTTP_GET,  .handler = h_info },
        { .uri = "/api/state",     .method = HTTP_GET,  .handler = h_state },
        { .uri = "/api/provision", .method = HTTP_POST, .handler = h_provision },
        { .uri = "/api/restart",   .method = HTTP_POST, .handler = h_restart },
        { .uri = "/api/pair",      .method = HTTP_POST, .handler = api_pair_handler },
    };
    for (size_t i = 0; i < sizeof(uris) / sizeof(uris[0]); i++) {
        httpd_register_uri_handler(s_hd, &uris[i]);
    }
    api_config_register(s_hd);
    api_talk_register(s_hd);
    api_ws_register(s_hd);
    api_cam_register(s_hd);
    ESP_LOGI(TAG, "http on port %d", API_PORT);
    return ESP_OK;
}

void api_http_stop(void)
{
    if (!s_hd) {
        return;
    }
    api_cam_stop();
    httpd_stop(s_hd);
    s_hd = NULL;
}
