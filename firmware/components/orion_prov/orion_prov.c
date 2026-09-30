// Glue around ESP-IDF's wifi_provisioning manager. See the header for why
// setup mode is a boot mode.
#include "orion_prov.h"
#include "prov_priv.h"

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/event_groups.h"
#include "freertos/task.h"
#include "esp_bt.h"
#include "esp_event.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "protocomm_ble.h"
#include "protocomm_security.h"

#include "orion_settings.h"
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"

#include "orion_config.h"
#include "orion_net.h"

static const char *TAG = "orion_prov";

#define BIT_END      BIT0   // the manager emitted WIFI_PROV_END
#define BIT_SUCCESS  BIT1
#define BIT_STOP     BIT2   // console asked to leave setup mode

#define PAIR_ENDPOINT "orion-pair"
#define CONFIG_ENDPOINT "orion-config"

static EventGroupHandle_t s_ev;
static orion_prov_cb_t s_cb;
static void *s_cb_ctx;
static char s_code[8];
static bool s_running;
static bool s_bt_released;
static wifi_sta_config_t s_creds;   // from CRED_RECV, written to NVS on success
static int64_t s_t_creds;

void prov_log_heap(const char *when)
{
    ESP_LOGI(TAG, "heap %-18s int %6u, largest int %6u, largest dma %6u, psram %u",
             when,
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
             (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_DMA),
             (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
}

static void report(orion_prov_state_t st, const char *detail)
{
    static const char *NAMES[] = { "waiting", "connecting", "failed", "done", "timeout" };
    ESP_LOGI(TAG, "%s %s", NAMES[st], detail ? detail : "");
    if (s_cb) {
        s_cb(st, detail, s_cb_ctx);
    }
}

// Only a password that actually joined is written. A wrong one stays in RAM
// until the next attempt overwrites it.
static void save_credentials(void)
{
    orion_config_set_str(ORION_CFG_WIFI_SSID, (const char *) s_creds.ssid);
    orion_config_set_str(ORION_CFG_WIFI_PASS, (const char *) s_creds.password);
    memset(&s_creds, 0, sizeof(s_creds));
}

static void on_prov(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;
    switch (id) {
    case WIFI_PROV_START:
        prov_log_heap("advertising");
        report(ORION_PROV_WAITING, orion_prov_device_name());
        break;
    case WIFI_PROV_CRED_RECV: {
        const wifi_sta_config_t *c = data;
        memcpy(&s_creds, c, sizeof(s_creds));
        s_t_creds = esp_timer_get_time();
        report(ORION_PROV_CONNECTING, (const char *) c->ssid);
        break;
    }
    case WIFI_PROV_CRED_FAIL: {
        const wifi_prov_sta_fail_reason_t *r = data;
        const char *why = *r == WIFI_PROV_STA_AUTH_ERROR ? "wrong password"
                                                          : "network not found";
        ESP_LOGW(TAG, "join failed %lld ms after the credentials: %s",
                 (esp_timer_get_time() - s_t_creds) / 1000, why);
        // Back to waiting, BLE link kept, so the phone can send another
        // password without starting over.
        wifi_prov_mgr_reset_sm_state_on_failure();
        report(ORION_PROV_FAILED, why);
        break;
    }
    case WIFI_PROV_CRED_SUCCESS: {
        char ip[16] = "";
        orion_net_ip(ip, sizeof(ip));
        ESP_LOGI(TAG, "connected %lld ms after the credentials, ip %s",
                 (esp_timer_get_time() - s_t_creds) / 1000, ip);
        save_credentials();
        xEventGroupSetBits(s_ev, BIT_SUCCESS);
        report(ORION_PROV_DONE, ip);
        break;
    }
    case WIFI_PROV_END:
        xEventGroupSetBits(s_ev, BIT_END);
        break;
    default:
        break;
    }
}

static void on_ble(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) data;
    if (base == PROTOCOMM_TRANSPORT_BLE_EVENT) {
        ESP_LOGI(TAG, "phone %s", id == PROTOCOMM_TRANSPORT_BLE_CONNECTED ? "connected"
                                                                           : "disconnected");
    } else if (id == PROTOCOMM_SECURITY_SESSION_CREDENTIALS_MISMATCH) {
        ESP_LOGW(TAG, "wrong code entered");
    } else if (id == PROTOCOMM_SECURITY_SESSION_SETUP_OK) {
        ESP_LOGI(TAG, "secure session up");
    }
}

static void handlers(bool on)
{
    if (on) {
        esp_event_handler_register(WIFI_PROV_EVENT, ESP_EVENT_ANY_ID, on_prov, NULL);
        esp_event_handler_register(PROTOCOMM_TRANSPORT_BLE_EVENT, ESP_EVENT_ANY_ID, on_ble, NULL);
        esp_event_handler_register(PROTOCOMM_SECURITY_SESSION_EVENT, ESP_EVENT_ANY_ID, on_ble, NULL);
    } else {
        esp_event_handler_unregister(WIFI_PROV_EVENT, ESP_EVENT_ANY_ID, on_prov);
        esp_event_handler_unregister(PROTOCOMM_TRANSPORT_BLE_EVENT, ESP_EVENT_ANY_ID, on_ble);
        esp_event_handler_unregister(PROTOCOMM_SECURITY_SESSION_EVENT, ESP_EVENT_ANY_ID, on_ble);
    }
}

esp_err_t orion_prov_start(orion_prov_cb_t cb, void *ctx)
{
    if (s_running) {
        return ESP_ERR_INVALID_STATE;
    }
    if (s_bt_released) {
        ESP_LOGE(TAG, "bt memory was released this boot; use prov start to reboot into setup");
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = orion_net_init_driver();
    if (err != ESP_OK) {
        return err;
    }
    orion_settings_init();    // orion-config renders from it; NVS read here, on main
    s_cb = cb;
    s_cb_ctx = ctx;
    if (!s_ev) {
        s_ev = xEventGroupCreate();
    }
    xEventGroupClearBits(s_ev, BIT_END | BIT_SUCCESS | BIT_STOP);
    orion_net_set_paused(true);
    // Pausing stops new attempts, not the one in flight. A station that is
    // still connecting refuses new config ("sta is connecting, cannot set
    // config"), and with the all-channel scan an attempt lasts seconds, long
    // enough to stop setup mode from starting. Abort it before the manager
    // takes the radio.
    if (esp_wifi_disconnect() == ESP_OK) {
        vTaskDelay(pdMS_TO_TICKS(300));
    }
    handlers(true);

    prov_log_heap("before ble");
    wifi_prov_mgr_config_t cfg = {
        .scheme = wifi_prov_scheme_ble,
        // Releases the controller's static memory to the heap at deinit.
        .scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
        .app_event_handler = WIFI_PROV_EVENT_HANDLER_NONE,
    };
    err = wifi_prov_mgr_init(cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "manager init: %s", esp_err_to_name(err));
        goto fail;
    }
    snprintf(s_code, sizeof(s_code), "%06u", (unsigned) (esp_random() % 1000000u));
    wifi_prov_mgr_endpoint_create(PAIR_ENDPOINT);
    wifi_prov_mgr_endpoint_create(CONFIG_ENDPOINT);
    err = wifi_prov_mgr_start_provisioning(WIFI_PROV_SECURITY_1, s_code,
                                           orion_prov_device_name(), NULL);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "start: %s", esp_err_to_name(err));
        wifi_prov_mgr_deinit();
        goto fail;
    }
    wifi_prov_mgr_endpoint_register(PAIR_ENDPOINT, prov_pair_handler, NULL);
    wifi_prov_mgr_endpoint_register(CONFIG_ENDPOINT, prov_config_handler, NULL);
    s_running = true;
    ESP_LOGI(TAG, "setup mode: ble name %s, code %s", orion_prov_device_name(), s_code);
    prov_log_heap("ble up");
    return ESP_OK;

fail:
    handlers(false);
    orion_net_set_paused(false);
    return err;
}

esp_err_t orion_prov_wait(uint32_t timeout_ms)
{
    if (!s_running) {
        return ESP_ERR_INVALID_STATE;
    }
    EventBits_t bits = xEventGroupWaitBits(s_ev, BIT_SUCCESS | BIT_STOP, pdFALSE, pdFALSE,
                                           pdMS_TO_TICKS(timeout_ms));
    if (bits & BIT_SUCCESS) {
        // The manager keeps BLE up for CONFIG_WIFI_PROV_AUTOSTOP_TIMEOUT more
        // seconds so the phone can read "connected" before the link drops.
        xEventGroupWaitBits(s_ev, BIT_END, pdFALSE, pdFALSE,
                            pdMS_TO_TICKS((CONFIG_WIFI_PROV_AUTOSTOP_TIMEOUT + 5) * 1000));
        return ESP_OK;
    }
    if (bits & BIT_STOP) {
        return ESP_ERR_INVALID_STATE;
    }
    report(ORION_PROV_TIMEOUT, NULL);
    return ESP_ERR_TIMEOUT;
}

void prov_request_stop(void)
{
    if (s_ev) {
        xEventGroupSetBits(s_ev, BIT_STOP);
    }
}

void orion_prov_stop(void)
{
    if (!s_running) {
        return;
    }
    if (!(xEventGroupGetBits(s_ev) & BIT_END)) {
        wifi_prov_mgr_stop_provisioning();
        xEventGroupWaitBits(s_ev, BIT_END, pdFALSE, pdFALSE, pdMS_TO_TICKS(5000));
    }
    prov_log_heap("ble stopped");
    wifi_prov_mgr_deinit();
    s_bt_released = true;
    handlers(false);
    s_running = false;
    memset(&s_creds, 0, sizeof(s_creds));
    orion_net_set_paused(false);
    prov_log_heap("ble released");
}

bool orion_prov_is_running(void)
{
    return s_running;
}

const char *orion_prov_code(void)
{
    return s_code;
}

void orion_prov_release_bt(void)
{
    if (s_bt_released) {
        return;
    }
    prov_log_heap("before bt release");
    esp_err_t err = esp_bt_mem_release(ESP_BT_MODE_BTDM);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "bt mem release: %s", esp_err_to_name(err));
    }
    s_bt_released = true;
    prov_log_heap("after bt release");
}
