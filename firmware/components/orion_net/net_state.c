// What the rest of the firmware asks orion_net: up or down, the address, the
// signal, and who wants to hear about changes. The driver side lives in
// orion_net.c and reports in through net_priv.h.
#include "orion_net.h"
#include "net_priv.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_log.h"
#include "esp_wifi.h"

static const char *TAG = "orion_net";

#define MAX_CALLBACKS 4

typedef struct {
    orion_net_cb_t fn;
    void *ctx;
} listener_t;

static listener_t s_listeners[MAX_CALLBACKS];
static bool s_up;
static bool s_ever_up;
static char s_ip[16] = "0.0.0.0";
static uint32_t s_disconnects;

static void notify(orion_net_state_t state)
{
    for (int i = 0; i < MAX_CALLBACKS; i++) {
        if (s_listeners[i].fn) {
            s_listeners[i].fn(state, s_listeners[i].ctx);
        }
    }
}

void net_mark_up(const char *ip)
{
    strlcpy(s_ip, ip, sizeof(s_ip));
    s_up = true;
    s_ever_up = true;
    ESP_LOGI(TAG, "up, ip %s, rssi %d", s_ip, orion_net_rssi());
    notify(ORION_NET_UP);
}

void net_mark_down(void)
{
    if (!s_up) {
        return;
    }
    s_up = false;
    strlcpy(s_ip, "0.0.0.0", sizeof(s_ip));
    notify(ORION_NET_DOWN);
}

bool net_ever_up(void)
{
    return s_ever_up;
}

uint32_t net_count_disconnect(void)
{
    return ++s_disconnects;
}

esp_err_t orion_net_wait_up(uint32_t timeout_ms)
{
    const uint32_t step = 100;
    uint32_t waited = 0;
    while (!s_up && waited < timeout_ms) {
        vTaskDelay(pdMS_TO_TICKS(step));
        waited += step;
    }
    return s_up ? ESP_OK : ESP_ERR_TIMEOUT;
}

bool orion_net_is_up(void)
{
    return s_up;
}

// While the speaker plays, Wi-Fi sends at 13 dBm instead of 20: a transmit
// burst at full power is a few hundred mA, and while the voice streams in
// the board answers every packet. On a weak USB port, with no battery, those
// bursts on top of the speaker's peaks pulled the rail down and the amplifier
// dropped out mid word. Only with a strong signal, where 7 dB less still
// reaches the router easily.
#define TX_LOW_QDBM     52      // 13 dBm, in 0.25 dBm steps
#define TX_FULL_QDBM    80      // 20 dBm
#define TX_LOW_MIN_RSSI -67

void orion_net_set_quiet_tx(bool quiet)
{
    static bool s_quiet;
    if (quiet == s_quiet) return;
    if (quiet) {
        const int rssi = orion_net_rssi();
        if (!s_up || rssi == 0 || rssi < TX_LOW_MIN_RSSI) return;
        if (esp_wifi_set_max_tx_power(TX_LOW_QDBM) == ESP_OK) s_quiet = true;
    } else {
        esp_wifi_set_max_tx_power(TX_FULL_QDBM);
        s_quiet = false;
    }
}

int orion_net_rssi(void)
{
    wifi_ap_record_t ap;
    if (!s_up || esp_wifi_sta_get_ap_info(&ap) != ESP_OK) {
        return 0;
    }
    return ap.rssi;
}

uint32_t orion_net_disconnect_count(void)
{
    return s_disconnects;
}

esp_err_t orion_net_ip(char *out, size_t out_len)
{
    if (!out || out_len == 0) {
        return ESP_ERR_INVALID_ARG;
    }
    strlcpy(out, s_ip, out_len);
    return s_up ? ESP_OK : ESP_ERR_INVALID_STATE;
}

esp_err_t orion_net_register_cb(orion_net_cb_t cb, void *ctx)
{
    for (int i = 0; i < MAX_CALLBACKS; i++) {
        if (!s_listeners[i].fn) {
            s_listeners[i].fn = cb;
            s_listeners[i].ctx = ctx;
            return ESP_OK;
        }
    }
    return ESP_ERR_NO_MEM;
}
