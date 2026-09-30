// GET and POST /api/config, POST /api/config/test. The work is in
// orion_settings; this file only moves bodies. Buffers live in PSRAM.
#include "api_priv.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"
#include "esp_heap_caps.h"
#include "esp_log.h"

#include "orion_settings.h"

static const char *TAG = "orion_api";

#define BODY_MAX 4096
#define OUT_MAX  2048

static char *psram(size_t n)
{
    return heap_caps_malloc(n, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
}

static esp_err_t h_get(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    char *out = psram(OUT_MAX);
    if (!out) {
        return httpd_resp_send_500(req);
    }
    if (orion_settings_render(out, OUT_MAX) == ESP_OK) {
        api_send_json(req, "200 OK", out);
    } else {
        api_send_json(req, "503 Service Unavailable",
                      "{\"error\":\"not_ready\",\"message\":\"settings not loaded\"}");
    }
    heap_caps_free(out);
    return ESP_OK;
}

// Reads the whole body into a PSRAM buffer, or answers 400 and returns NULL.
static char *read_body(httpd_req_t *req, size_t *len)
{
    if (req->content_len == 0 || req->content_len >= BODY_MAX) {
        api_send_json(req, "400 Bad Request",
                      "{\"error\":\"invalid_config\",\"message\":\"body must be 1 to 4095 bytes\"}");
        return NULL;
    }
    char *body = psram(req->content_len + 1);
    if (!body) {
        httpd_resp_send_500(req);
        return NULL;
    }
    size_t got = 0;
    while (got < req->content_len) {
        int r = httpd_req_recv(req, body + got, req->content_len - got);
        if (r == HTTPD_SOCK_ERR_TIMEOUT) {
            continue;
        }
        if (r <= 0) {
            heap_caps_free(body);
            return NULL;
        }
        got += (size_t) r;
    }
    body[got] = '\0';
    *len = got;
    return body;
}

static esp_err_t h_post(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    size_t len = 0;
    char *body = read_body(req, &len);
    if (!body) {
        return ESP_OK;
    }
    char *out = psram(OUT_MAX);
    if (!out) {
        heap_caps_free(body);
        return httpd_resp_send_500(req);
    }
    esp_err_t err = orion_settings_apply(body, len, out, OUT_MAX);
    memset(body, 0, len);
    heap_caps_free(body);
    if (err == ESP_OK) {
        api_settings_changed();
        api_send_json(req, "200 OK", out);
    } else if (err == ESP_ERR_INVALID_ARG) {
        api_send_json(req, "400 Bad Request", out);
    } else {
        ESP_LOGE(TAG, "config store: %s", esp_err_to_name(err));
        api_send_json(req, "503 Service Unavailable",
                      "{\"error\":\"store_failed\",\"message\":\"could not store the config\"}");
    }
    memset(out, 0, OUT_MAX);
    heap_caps_free(out);
    return ESP_OK;
}

static esp_err_t h_test(httpd_req_t *req)
{
    if (!api_authorized(req)) {
        return ESP_OK;
    }
    size_t len = 0;
    char *body = read_body(req, &len);
    if (!body) {
        return ESP_OK;
    }
    char stage[8] = "";
    cJSON *root = cJSON_ParseWithLength(body, len);
    const cJSON *s = cJSON_GetObjectItem(root, "stage");
    if (cJSON_IsString(s)) {
        strlcpy(stage, s->valuestring, sizeof(stage));
    }
    cJSON_Delete(root);
    heap_caps_free(body);

    char out[192];
    esp_err_t err = orion_settings_test(stage, out, sizeof(out));
    if (err == ESP_OK) {
        api_send_json(req, "200 OK", out);
    } else if (err == ESP_ERR_INVALID_ARG) {
        api_send_json(req, "400 Bad Request",
                      "{\"ok\":false,\"error\":\"invalid_stage\",\"message\":\"stage is llm, stt or tts\"}");
    } else if (strstr(out, "\"busy\"")) {
        api_send_json(req, "409 Conflict", out);
    } else {
        api_send_json(req, "200 OK", out);
    }
    return ESP_OK;
}

void api_config_register(httpd_handle_t hd)
{
    const httpd_uri_t uris[] = {
        { .uri = "/api/config",      .method = HTTP_GET,  .handler = h_get },
        { .uri = "/api/config",      .method = HTTP_POST, .handler = h_post },
        { .uri = "/api/config/test", .method = HTTP_POST, .handler = h_test },
    };
    for (size_t i = 0; i < sizeof(uris) / sizeof(uris[0]); i++) {
        httpd_register_uri_handler(hd, &uris[i]);
    }
}
