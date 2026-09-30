// The board's names, the reboot-into-setup flag, and the orion-pair endpoint.
#include "orion_prov.h"
#include "prov_priv.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_system.h"
#include "esp_timer.h"

#include "orion_config.h"
#include "orion_net.h"

static const char *TAG = "orion_prov";

static char s_name[16];
static char s_id[16];

// Lower case hex of the last two MAC bytes, so "orion-a1b2" reads like the
// contract's example and the BLE name matches it apart from the capital.
static void ids(void)
{
    if (s_name[0]) {
        return;
    }
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_name, sizeof(s_name), "Orion-%02x%02x", mac[4], mac[5]);
    snprintf(s_id, sizeof(s_id), "orion-%02x%02x", mac[4], mac[5]);
}

const char *orion_prov_device_name(void)
{
    ids();
    return s_name;
}

const char *orion_prov_device_id(void)
{
    ids();
    return s_id;
}

bool orion_prov_should_run(void)
{
    int32_t flag = 0;
    bool flagged = orion_config_get_i32(ORION_CFG_PROV_BOOT, &flag) == ESP_OK && flag == 1;
    if (flagged) {
        orion_config_set_i32(ORION_CFG_PROV_BOOT, 0);
    }
    bool no_creds = !orion_config_has(ORION_CFG_WIFI_SSID);
    if (flagged || no_creds) {
        ESP_LOGI(TAG, "setup mode this boot: %s", flagged ? "requested" : "no wifi credentials");
    }
    return flagged || no_creds;
}

void orion_prov_request(const char *why)
{
    ESP_LOGW(TAG, "restarting into setup mode: %s", why);
    // nvs_commit is synchronous, so the flag is on flash before the reset.
    orion_config_set_i32(ORION_CFG_PROV_BOOT, 1);
    esp_restart();
}

static void request_cb(void *arg)
{
    orion_prov_request((const char *) arg);
}

void orion_prov_request_async(const char *why)
{
    static esp_timer_handle_t s_req;
    if (!s_req) {
        const esp_timer_create_args_t a = { .callback = request_cb, .arg = (void *) why,
                                            .name = "prov_request" };
        ESP_ERROR_CHECK(esp_timer_create(&a, &s_req));
    }
    esp_timer_start_once(s_req, 500000);
}

static void watch_cb(void *arg)
{
    (void) arg;
    if (!orion_net_is_up()) {
        orion_prov_request("no network in time");
    }
}

void orion_prov_watch(uint32_t ms)
{
    static esp_timer_handle_t s_watch;
    if (!s_watch) {
        const esp_timer_create_args_t a = { .callback = watch_cb, .name = "prov_watch" };
        ESP_ERROR_CHECK(esp_timer_create(&a, &s_watch));
    }
    esp_timer_stop(s_watch);
    esp_timer_start_once(s_watch, (uint64_t) ms * 1000);
}

// protocomm frees the response buffer once it has been sent.
static uint8_t *reply(const char *json, ssize_t *outlen)
{
    size_t n = strlen(json);
    uint8_t *out = malloc(n);
    if (out) {
        memcpy(out, json, n);
        *outlen = (ssize_t) n;
    }
    return out;
}

esp_err_t prov_pair_handler(uint32_t session_id, const uint8_t *inbuf, ssize_t inlen,
                            uint8_t **outbuf, ssize_t *outlen, void *priv)
{
    (void) session_id;
    (void) priv;
    char body[257] = "";
    if (inbuf && inlen > 0) {
        size_t n = inlen < (ssize_t) sizeof(body) - 1 ? (size_t) inlen : sizeof(body) - 1;
        memcpy(body, inbuf, n);
        body[n] = '\0';
    }

    cJSON *root = cJSON_Parse(body);
    const cJSON *tok = cJSON_GetObjectItem(root, "app_token");
    const cJSON *name = cJSON_GetObjectItem(root, "device_name");
    size_t tok_len = cJSON_IsString(tok) ? strlen(tok->valuestring) : 0;
    bool ok = tok_len >= 8 && tok_len <= 64;
    if (ok) {
        char dn[33] = "Orion";
        if (cJSON_IsString(name) && name->valuestring[0]) {
            strlcpy(dn, name->valuestring, sizeof(dn));
        }
        orion_config_set_str(ORION_CFG_APP_TOKEN, tok->valuestring);
        orion_config_set_str(ORION_CFG_DEVICE_NAME, dn);
        ESP_LOGI(TAG, "paired: device_name '%s', token %u chars", dn, (unsigned) tok_len);
    } else {
        ESP_LOGW(TAG, "orion-pair: bad request, %d bytes", (int) inlen);
    }
    cJSON_Delete(root);

    char json[80];
    snprintf(json, sizeof(json), "{\"device_id\":\"%s\",\"ok\":%s}",
             orion_prov_device_id(), ok ? "true" : "false");
    *outbuf = reply(json, outlen);
    return *outbuf ? ESP_OK : ESP_ERR_NO_MEM;
}
