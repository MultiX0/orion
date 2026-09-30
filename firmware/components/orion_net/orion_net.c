// Wi-Fi station. Credentials come from NVS, never from the binary.
//
// The board lives on a desk and the router reboots, so the interesting part is
// not connecting, it is reconnecting forever without hammering the AP. Backoff
// doubles from 1 s to 30 s and resets the moment an IP arrives.

#include "orion_net.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/timers.h"

#include "esp_event.h"
#include "esp_log.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include <stdlib.h>
#include <time.h>
#include "esp_wifi.h"

#include "orion_config.h"
#include "net_diagnose.h"
#include "net_priv.h"

static const char *TAG = "orion_net";

#define BACKOFF_MIN_MS  1000
#define BACKOFF_MAX_MS  30000

static esp_netif_t *s_netif;
static TimerHandle_t s_retry;
static uint32_t s_backoff_ms = BACKOFF_MIN_MS;
static bool s_started;
static bool s_driver_ready;
static bool s_wifi_started;
static bool s_paused;

static void retry_now(TimerHandle_t t)
{
    (void) t;
    ESP_LOGI(TAG, "reconnecting");
    esp_wifi_connect();
}

static void schedule_retry(void)
{
    if (!s_retry) {
        return;
    }
    ESP_LOGW(TAG, "retry in %u ms", (unsigned) s_backoff_ms);
    xTimerChangePeriod(s_retry, pdMS_TO_TICKS(s_backoff_ms), 0);
    xTimerStart(s_retry, 0);

    s_backoff_ms *= 2;
    if (s_backoff_ms > BACKOFF_MAX_MS) {
        s_backoff_ms = BACKOFF_MAX_MS;
    }
}

static void on_wifi(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;

    if (id == WIFI_EVENT_STA_START) {
        s_wifi_started = true;
        if (!s_paused) {
            esp_wifi_connect();
        }
        return;
    }
    if (id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *e = data;
        uint32_t disconnects = net_count_disconnect();
        net_mark_down();
        const uint8_t reason = e ? e->reason : 0;
        ESP_LOGW(TAG, "disconnected, reason %d (%s)", reason, reason_name(reason));
        // In setup mode the provisioning manager owns the station and reports
        // the failure to the phone. A retry from here would fight it.
        if (s_paused) {
            return;
        }
        // Never associating at all looks exactly like a wrong password, so say
        // what it usually is instead. The ESP32-S3 has no 5 GHz radio.
        if (!net_ever_up() && disconnects == 3) {
            diagnose();
        }
        schedule_retry();
    }
}

// The board's own clock, so the date and time reach the model without a PC.
// Jordan is UTC+3 all year since 2022. Once, on the first address.
static void start_clock(void)
{
    static bool started;
    if (started) {
        return;
    }
    started = true;
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    cfg.wait_for_sync = false;
    if (esp_netif_sntp_init(&cfg) != ESP_OK) {
        ESP_LOGW(TAG, "sntp did not start");
    }
}

static void on_ip(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    (void) arg;
    (void) base;

    if (id != IP_EVENT_STA_GOT_IP) {
        return;
    }
    ip_event_got_ip_t *e = data;
    char ip[16];
    snprintf(ip, sizeof(ip), IPSTR, IP2STR(&e->ip_info.ip));
    s_backoff_ms = BACKOFF_MIN_MS;
    start_clock();
    net_mark_up(ip);
}

esp_err_t orion_net_init_driver(void)
{
    if (s_driver_ready) {
        return ESP_OK;
    }
    ESP_ERROR_CHECK(esp_netif_init());
    esp_err_t err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    s_netif = esp_netif_create_default_wifi_sta();

    wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&init));

    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        WIFI_EVENT, ESP_EVENT_ANY_ID, on_wifi, NULL, NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(
        IP_EVENT, IP_EVENT_STA_GOT_IP, on_ip, NULL, NULL));

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    // The radio sleeping between beacons adds tens of milliseconds to the first
    // packet of every turn. The board is on USB power, so it stays awake.
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
    // 20 MHz, even when the router offers 40. At -77 to -79 dBm from the
    // router, a common signal on a desk, a 40 MHz channel spreads the same power
    // over twice the band: slower rates, more retries, a 3.8 s TLS handshake
    // and an 11 s stall mid sentence. Half the width is about 3 dB more margin.
    ESP_ERROR_CHECK(esp_wifi_set_bandwidth(WIFI_IF_STA, WIFI_BW_HT20));

    s_retry = xTimerCreate("net_retry", pdMS_TO_TICKS(BACKOFF_MIN_MS), pdFALSE,
                           NULL, retry_now);
    s_driver_ready = true;
    return ESP_OK;
}

void orion_net_set_paused(bool paused)
{
    s_paused = paused;
    if (paused && s_retry) {
        xTimerStop(s_retry, 0);
    }
}

// Reads the saved network into the driver. Zeroes the password copies after.
static esp_err_t apply_saved_config(char *ssid, size_t ssid_len)
{
    char pass[65] = {0};
    if (orion_config_get_str(ORION_CFG_WIFI_SSID, ssid, ssid_len) != ESP_OK ||
        ssid[0] == '\0') {
        ESP_LOGE(TAG, "no wifi_ssid in nvs. Fill WIFI_SSID in .env and run "
                      "tools/cloud/provision.py, or pair over Bluetooth.");
        return ESP_ERR_NOT_FOUND;
    }
    orion_config_get_str(ORION_CFG_WIFI_PASS, pass, sizeof(pass));

    wifi_config_t cfg = {0};
    strlcpy((char *) cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid));
    strlcpy((char *) cfg.sta.password, pass, sizeof(cfg.sta.password));
    cfg.sta.threshold.authmode = pass[0] ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    cfg.sta.pmf_cfg.capable = true;
    // A home network is often several access points under one name. The default
    // fast scan joins the first one it hears: the same spot can get -55 dBm on
    // one boot and -81 on the next, and at -81 a spoken answer stalls for 18 s.
    // Scan every channel and take the strongest.
    cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    cfg.sta.sort_method = WIFI_CONNECT_AP_BY_SIGNAL;
    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &cfg);

    memset(pass, 0, sizeof(pass));
    memset(&cfg, 0, sizeof(cfg));
    return err;
}

// True when the station already holds an address, which happens when the
// provisioning manager connected it before orion_net_start was called.
static bool adopt_existing_ip(void)
{
    esp_netif_ip_info_t info;
    if (!s_netif || esp_netif_get_ip_info(s_netif, &info) != ESP_OK ||
        info.ip.addr == 0) {
        return false;
    }
    char ip[16];
    snprintf(ip, sizeof(ip), IPSTR, IP2STR(&info.ip));
    s_backoff_ms = BACKOFF_MIN_MS;
    net_mark_up(ip);
    return true;
}

esp_err_t orion_net_start(void)
{
    if (s_started) {
        return ESP_OK;
    }
    // The driver comes up even without credentials: its DMA buffers must be
    // taken before the screen and camera use that memory, and Bluetooth setup
    // needs a station to scan with.
    esp_err_t err = orion_net_init_driver();
    if (err != ESP_OK) {
        return err;
    }
    s_paused = false;

    char ssid[33] = {0};
    if (orion_net_is_up() || adopt_existing_ip()) {
        s_started = true;
        return ESP_OK;
    }
    err = apply_saved_config(ssid, sizeof(ssid));
    if (err != ESP_OK) {
        return err;
    }
    if (s_wifi_started) {
        esp_wifi_connect();
    } else {
        ESP_ERROR_CHECK(esp_wifi_start());
    }
    s_started = true;
    ESP_LOGI(TAG, "connecting to '%s'", ssid);
    return ESP_OK;
}

esp_err_t orion_net_reconnect(void)
{
    char ssid[33] = {0};
    esp_err_t err = apply_saved_config(ssid, sizeof(ssid));
    if (err != ESP_OK) {
        return err;
    }
    s_backoff_ms = BACKOFF_MIN_MS;
    ESP_LOGI(TAG, "switching to '%s'", ssid);
    esp_wifi_disconnect();
    return esp_wifi_connect();
}

esp_err_t orion_net_stop(void)
{
    if (!s_started) {
        return ESP_OK;
    }
    if (s_retry) {
        xTimerStop(s_retry, 0);
    }
    esp_err_t err = esp_wifi_stop();
    s_started = false;
    net_mark_down();
    return err;
}
