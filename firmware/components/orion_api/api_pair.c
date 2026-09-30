// POST /api/pair: an app joins a board that is already on the network, with
// a six digit code the board shows on its own screen. The first call, without
// a code, puts one up for two minutes; the second carries it. Five wrong codes
// drop it. Standing next to the board is the proof, as with Bluetooth setup,
// so a reinstalled app or a second device pairs without touching Wi-Fi.
#include "api_priv.h"

#include <stdio.h>
#include <string.h>

#include "cJSON.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"

#include "orion_api.h"

static const char *TAG = "orion_api";

#define CODE_S      120
#define CODE_TRIES  5

static char s_code[7];
static int64_t s_until_us;
static int s_fails;
static orion_api_pair_cb_t s_cb;

void orion_api_on_pair_code(orion_api_pair_cb_t cb)
{
    s_cb = cb;
}

static void show(const char *code, int seconds)
{
    if (s_cb) {
        s_cb(code, seconds);
    }
}

static void drop_code(void)
{
    memset(s_code, 0, sizeof(s_code));
    s_until_us = 0;
    s_fails = 0;
    show(NULL, 0);
}

static void reply(httpd_req_t *req, const char *status, const char *json)
{
    api_send_json(req, status, json);
}

esp_err_t api_pair_handler(httpd_req_t *req)
{
    char body[256];
    if (req->content_len == 0 || req->content_len >= sizeof(body)) {
        reply(req, "400 Bad Request", "{\"ok\":false,\"error\":\"bad_request\",\"message\":\"body must be under 256 bytes\"}");
        return ESP_OK;
    }
    int got = httpd_req_recv(req, body, req->content_len);
    if (got <= 0) {
        return ESP_FAIL;
    }
    body[got] = '\0';

    char token[65] = "";
    char code[8] = "";
    cJSON *root = cJSON_Parse(body);
    const cJSON *t = cJSON_GetObjectItem(root, "app_token");
    const cJSON *c = cJSON_GetObjectItem(root, "code");
    if (cJSON_IsString(t)) {
        strlcpy(token, t->valuestring, sizeof(token));
    }
    if (cJSON_IsString(c)) {
        strlcpy(code, c->valuestring, sizeof(code));
    }
    cJSON_Delete(root);
    memset(body, 0, sizeof(body));

    const size_t n = strlen(token);
    if (n < 8 || n > 64) {
        reply(req, "400 Bad Request", "{\"ok\":false,\"error\":\"bad_request\",\"message\":\"app_token 8 to 64 chars\"}");
        return ESP_OK;
    }

    const int64_t now = esp_timer_get_time();
    const bool live = s_code[0] && now < s_until_us;
    char out[192];
    if (!code[0]) {
        if (!live) {
            snprintf(s_code, sizeof(s_code), "%06u", (unsigned) (esp_random() % 1000000u));
            s_until_us = now + (int64_t) CODE_S * 1000000;
            s_fails = 0;
            ESP_LOGI(TAG, "pairing code on screen for %d s: %s", CODE_S, s_code);
        }
        const int left_s = (int) ((s_until_us - now) / 1000000);
        show(s_code, left_s);
        snprintf(out, sizeof(out), "{\"ok\":false,\"error\":\"code_required\",\"expires_s\":%d}", left_s);
        reply(req, "202 Accepted", out);
        memset(token, 0, sizeof(token));
        return ESP_OK;
    }
    if (!live) {
        if (s_code[0]) {
            drop_code();
        }
        reply(req, "403 Forbidden", "{\"ok\":false,\"error\":\"expired\",\"message\":\"That code timed out. Ask Orion for a new one.\"}");
        memset(token, 0, sizeof(token));
        return ESP_OK;
    }
    if (strcmp(code, s_code) != 0) {
        s_fails++;
        const int left = CODE_TRIES - s_fails;
        ESP_LOGW(TAG, "wrong pairing code, %d tries left", left);
        if (left <= 0) {
            drop_code();
        }
        if (left > 0) {
            snprintf(out, sizeof(out),
                     "{\"ok\":false,\"error\":\"bad_code\",\"left\":%d,"
                     "\"message\":\"That is not the code on Orion's screen. %d %s left.\"}",
                     left, left, left == 1 ? "try" : "tries");
        } else {
            snprintf(out, sizeof(out),
                     "{\"ok\":false,\"error\":\"bad_code\",\"left\":0,"
                     "\"message\":\"Five wrong codes. Ask Orion for a new one.\"}");
        }
        reply(req, "403 Forbidden", out);
        memset(token, 0, sizeof(token));
        return ESP_OK;
    }

    drop_code();
    esp_err_t err = api_post_token(token);
    memset(token, 0, sizeof(token));
    if (err != ESP_OK) {
        reply(req, "503 Service Unavailable", "{\"ok\":false,\"error\":\"busy\",\"message\":\"could not save the pairing\"}");
        return ESP_OK;
    }
    snprintf(out, sizeof(out), "{\"device_id\":\"%s\",\"ok\":true}", api_device_id());
    reply(req, "200 OK", out);
    return ESP_OK;
}
