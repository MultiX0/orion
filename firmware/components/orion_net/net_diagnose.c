// Why the board is not on the network, in a sentence rather than a reason code.
//
// The ESP32-S3 has no 5 GHz radio. An SSID that exists only on 5 GHz fails in a
// way that is indistinguishable from a wrong password unless somebody scans and
// says so, which is what this does.

#include "net_diagnose.h"

#include <stdlib.h>
#include <string.h>

#include "esp_log.h"
#include "esp_wifi.h"

#include "orion_config.h"

static const char *TAG = "orion_net";

const char *reason_name(uint8_t reason)
{
    switch (reason) {
    case WIFI_REASON_NO_AP_FOUND:      return "no AP with that SSID on 2.4 GHz";
    case WIFI_REASON_AUTH_FAIL:        return "auth failed";
    case WIFI_REASON_AUTH_EXPIRE:      return "auth expired";
    case WIFI_REASON_HANDSHAKE_TIMEOUT: return "handshake timeout, usually a wrong password";
    case WIFI_REASON_ASSOC_EXPIRE:     return "association expired";
    case WIFI_REASON_BEACON_TIMEOUT:   return "beacon timeout, out of range or AP rebooted";
    case WIFI_REASON_CONNECTION_FAIL:  return "connection failed";
    default:                           return "see esp_wifi_types.h";
    }
}

// Runs once, after a few failures, when we have never been connected. The most
// common cause on this chip is an SSID that only exists on 5 GHz, and that is
// indistinguishable from a bad password unless somebody scans and says so.
void diagnose(void)
{
    char ssid[33] = {0};
    orion_config_get_str(ORION_CFG_WIFI_SSID, ssid, sizeof(ssid));

    wifi_scan_config_t scan = { .show_hidden = true };
    if (esp_wifi_scan_start(&scan, true) != ESP_OK) {
        ESP_LOGW(TAG, "could not scan to diagnose");
        return;
    }

    uint16_t found = 0;
    esp_wifi_scan_get_ap_num(&found);
    if (found == 0) {
        ESP_LOGE(TAG, "scan saw no 2.4 GHz networks at all. Check the antenna.");
        return;
    }
    if (found > 20) {
        found = 20;
    }

    wifi_ap_record_t *aps = calloc(found, sizeof(wifi_ap_record_t));
    if (!aps) {
        return;
    }
    esp_wifi_scan_get_ap_records(&found, aps);

    bool seen = false;
    ESP_LOGW(TAG, "scan found %u networks on 2.4 GHz:", (unsigned) found);
    for (uint16_t i = 0; i < found; i++) {
        const bool match = strcmp((char *) aps[i].ssid, ssid) == 0;
        seen = seen || match;
        ESP_LOGW(TAG, "  %-32s ch %2d  rssi %d%s", (char *) aps[i].ssid,
                 aps[i].primary, aps[i].rssi, match ? "   <- this is ours" : "");
    }

    if (seen) {
        ESP_LOGE(TAG, "'%s' is on the air and we still cannot join it. "
                      "That points at WIFI_PASSWORD in .env.", ssid);
    } else {
        ESP_LOGE(TAG, "'%s' is not in the 2.4 GHz scan. The ESP32-S3 has no "
                      "5 GHz radio, so a 5 GHz only SSID can never be joined. "
                      "Enable 2.4 GHz on the router or use the 2.4 GHz SSID.",
                 ssid);
    }
    free(aps);
}
