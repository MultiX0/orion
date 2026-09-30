// Typed reads of the NVS keys that tools/cloud/provision.py writes from .env.
//
// Nothing in here is compiled into the binary. If the nvs partition was never
// provisioned every getter returns ESP_ERR_NVS_NOT_FOUND and the caller says so
// out loud, which is a much better failure than a key baked into flash.

#include "orion_config.h"

#include <string.h>

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "orion_config";

static nvs_handle_t s_nvs;
static bool s_open;

esp_err_t orion_config_init(void)
{
    if (s_open) {
        return ESP_OK;
    }

    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "nvs partition needs erasing, doing it now");
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "nvs_flash_init: %s", esp_err_to_name(err));
        return err;
    }

    err = nvs_open(ORION_CFG_NAMESPACE, NVS_READWRITE, &s_nvs);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "no namespace '%s': %s. Run tools/cloud/provision.py.",
                 ORION_CFG_NAMESPACE, esp_err_to_name(err));
        return err;
    }

    s_open = true;
    return ESP_OK;
}

esp_err_t orion_config_get_str(const char *key, char *out, size_t out_len)
{
    if (!s_open || !out || out_len == 0) {
        return ESP_ERR_INVALID_STATE;
    }
    out[0] = '\0';
    size_t len = out_len;
    esp_err_t err = nvs_get_str(s_nvs, key, out, &len);
    if (err != ESP_OK) {
        out[0] = '\0';
    }
    return err;
}

esp_err_t orion_config_get_i32(const char *key, int32_t *out)
{
    if (!s_open || !out) {
        return ESP_ERR_INVALID_STATE;
    }
    return nvs_get_i32(s_nvs, key, out);
}

bool orion_config_get_bool(const char *key, bool fallback)
{
    int32_t v = 0;
    if (orion_config_get_i32(key, &v) != ESP_OK) {
        return fallback;
    }
    return v != 0;
}

esp_err_t orion_config_set_str(const char *key, const char *value)
{
    if (!s_open) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_set_str(s_nvs, key, value);
    if (err == ESP_OK) {
        err = nvs_commit(s_nvs);
    }
    return err;
}

esp_err_t orion_config_set_i32(const char *key, int32_t value)
{
    if (!s_open) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_set_i32(s_nvs, key, value);
    if (err == ESP_OK) {
        err = nvs_commit(s_nvs);
    }
    return err;
}

esp_err_t orion_config_erase(const char *key)
{
    if (!s_open) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_erase_key(s_nvs, key);
    if (err == ESP_OK) {
        err = nvs_commit(s_nvs);
    }
    return err == ESP_ERR_NVS_NOT_FOUND ? ESP_OK : err;
}

esp_err_t orion_config_erase_all(void)
{
    if (!s_open) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = nvs_erase_all(s_nvs);
    if (err == ESP_OK) {
        err = nvs_commit(s_nvs);
    }
    ESP_LOGW(TAG, "factory reset: every key erased: %s", esp_err_to_name(err));
    return err;
}

size_t orion_config_copy_str(const char *key, char *out, size_t out_len,
                             const char *fallback)
{
    if (orion_config_get_str(key, out, out_len) != ESP_OK || out[0] == '\0') {
        if (!fallback) {
            out[0] = '\0';
            return 0;
        }
        strlcpy(out, fallback, out_len);
    }
    return strlen(out);
}

bool orion_config_has(const char *key)
{
    size_t len = 0;
    return s_open && nvs_get_str(s_nvs, key, NULL, &len) == ESP_OK && len > 1;
}

// Wi-Fi and something to talk to. Per stage keys are not required here: a
// language model on the LAN needs none, and a stage that is missing its key
// fails its own orion_cloud_test with http_401, which says more than this could.
bool orion_config_is_provisioned(void)
{
    if (!orion_config_has(ORION_CFG_WIFI_SSID)) {
        ESP_LOGW(TAG, "missing key '%s', run tools/cloud/provision.py", ORION_CFG_WIFI_SSID);
        return false;
    }
    if (!orion_config_has(ORION_CFG_LLM_KEY) && !orion_config_has(ORION_CFG_DEEPINFRA_KEY) &&
        !orion_config_has(ORION_CFG_LLM_URL)) {
        ESP_LOGW(TAG, "no language model configured, run tools/cloud/provision.py");
        return false;
    }
    return true;
}

void orion_config_report(void)
{
    // Prints what is present, never what it contains. A key is reported by its
    // length only, since a serial log can end up on screen or in a recording.
    char buf[320];      // OpenAI project keys run past 160 characters
    static const char *shown[] = {
        ORION_CFG_WIFI_SSID, ORION_CFG_WAKE_PHRASE,
        ORION_CFG_LLM_URL, ORION_CFG_LLM_MODEL,
        ORION_CFG_STT_PROV, ORION_CFG_STT_URL, ORION_CFG_STT_MODEL,
        ORION_CFG_TTS_PROV, ORION_CFG_TTS_URL, ORION_CFG_TTS_MODEL, ORION_CFG_TTS_VOICE,
        ORION_CFG_ASR_PROVIDER, ORION_CFG_FISH_VOICE, ORION_CFG_DEVICE_NAME,
    };
    static const char *secret[] = {
        ORION_CFG_WIFI_PASS, ORION_CFG_LLM_KEY, ORION_CFG_STT_KEY, ORION_CFG_TTS_KEY,
        ORION_CFG_FISH_KEY, ORION_CFG_DEEPINFRA_KEY, ORION_CFG_APP_TOKEN, ORION_CFG_APP_TOKENS,
    };

    for (size_t i = 0; i < sizeof(shown) / sizeof(shown[0]); i++) {
        if (orion_config_get_str(shown[i], buf, sizeof(buf)) == ESP_OK) {
            ESP_LOGI(TAG, "%-13s %s", shown[i], buf);
        } else {
            ESP_LOGW(TAG, "%-13s not set", shown[i]);
        }
    }
    for (size_t i = 0; i < sizeof(secret) / sizeof(secret[0]); i++) {
        if (orion_config_get_str(secret[i], buf, sizeof(buf)) == ESP_OK) {
            ESP_LOGI(TAG, "%-13s present, %d chars", secret[i], (int) strlen(buf));
            memset(buf, 0, sizeof(buf));
        } else {
            ESP_LOGW(TAG, "%-13s not set", secret[i]);
        }
    }
}
