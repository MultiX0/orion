// The orion-config endpoint: a POST /api/config body over the encrypted
// setup session. A body too long for one write comes in parts,
// {"part":i,"parts":n,"data":"<slice>"}, gathered here in PSRAM.
#include "prov_priv.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "cJSON.h"
#include "esp_heap_caps.h"
#include "esp_log.h"

#include "orion_settings.h"

static const char *TAG = "orion_prov";

#define BODY_MAX 4096
#define OUT_MAX  2048

static char *s_body;
static size_t s_len;
static int s_next = 1;

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

static esp_err_t answer(const char *json, uint8_t **outbuf, ssize_t *outlen)
{
    *outbuf = reply(json, outlen);
    return *outbuf ? ESP_OK : ESP_ERR_NO_MEM;
}

static void reset(void)
{
    if (s_body) {
        memset(s_body, 0, BODY_MAX);
    }
    s_len = 0;
    s_next = 1;
}

// Adds one part. Returns 0 when more are due, 1 when the body is whole, -1 on error.
static int gather(const cJSON *root, const char **why)
{
    const cJSON *part = cJSON_GetObjectItem(root, "part");
    const cJSON *parts = cJSON_GetObjectItem(root, "parts");
    const cJSON *data = cJSON_GetObjectItem(root, "data");
    if (!cJSON_IsNumber(part) || !cJSON_IsNumber(parts) || !cJSON_IsString(data) ||
        parts->valueint < 1 || part->valueint < 1 || part->valueint > parts->valueint) {
        *why = "part, parts and data expected";
        return -1;
    }
    if (part->valueint == 1) {
        reset();
    } else if (part->valueint != s_next) {
        reset();
        *why = "parts out of order, start again from part 1";
        return -1;
    }
    size_t n = strlen(data->valuestring);
    if (s_len + n >= BODY_MAX) {
        reset();
        *why = "config longer than 4095 bytes";
        return -1;
    }
    memcpy(s_body + s_len, data->valuestring, n);
    s_len += n;
    s_body[s_len] = '\0';
    s_next = part->valueint + 1;
    return part->valueint == parts->valueint ? 1 : 0;
}

esp_err_t prov_config_handler(uint32_t session_id, const uint8_t *inbuf, ssize_t inlen,
                              uint8_t **outbuf, ssize_t *outlen, void *priv)
{
    (void) session_id;
    (void) priv;
    if (!s_body) {
        s_body = heap_caps_calloc(1, BODY_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    }
    if (!s_body || orion_settings_init() != ESP_OK || !inbuf || inlen <= 0) {
        return answer("{\"error\":\"invalid_config\",\"message\":\"empty request\"}", outbuf, outlen);
    }

    cJSON *root = cJSON_ParseWithLength((const char *) inbuf, (size_t) inlen);
    char small[96];
    if (cJSON_GetObjectItem(root, "parts")) {
        const char *why = "";
        int r = gather(root, &why);
        int part = cJSON_GetObjectItem(root, "part")->valueint;
        cJSON_Delete(root);
        if (r < 0) {
            snprintf(small, sizeof(small), "{\"error\":\"invalid_config\",\"message\":\"%s\"}", why);
            return answer(small, outbuf, outlen);
        }
        if (r == 0) {
            snprintf(small, sizeof(small), "{\"ok\":true,\"part\":%d}", part);
            return answer(small, outbuf, outlen);
        }
    } else {
        cJSON_Delete(root);
        if ((size_t) inlen >= BODY_MAX) {
            return answer("{\"error\":\"invalid_config\",\"message\":\"too long\"}", outbuf, outlen);
        }
        reset();
        memcpy(s_body, inbuf, (size_t) inlen);
        s_len = (size_t) inlen;
        s_body[s_len] = '\0';
    }

    char *out = heap_caps_malloc(OUT_MAX, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    if (!out) {
        reset();
        return ESP_ERR_NO_MEM;
    }
    esp_err_t err = orion_settings_apply(s_body, s_len, out, OUT_MAX);
    ESP_LOGI(TAG, "orion-config: %u bytes, %s", (unsigned) s_len, esp_err_to_name(err));
    reset();
    if (err != ESP_OK && err != ESP_ERR_INVALID_ARG) {
        strlcpy(out, "{\"error\":\"store_failed\",\"message\":\"could not store the config\"}", OUT_MAX);
    }
    err = answer(out, outbuf, outlen);
    memset(out, 0, OUT_MAX);
    heap_caps_free(out);
    return err;
}
