// Bluetooth LE setup mode: Espressif Unified Provisioning (wifi_provisioning
// over NimBLE, security 1 with a six digit proof of possession), plus the
// orion-pair endpoint from docs/DEVICE_PROTOCOL.md.
//
// Setup mode is a boot mode. The BLE controller's static memory can only be
// given back to the heap with esp_bt_mem_release, which is one way until the
// next reset, so entering setup mode from a running system sets an NVS flag
// and restarts. On that boot the camera, wake word and cloud never start, so
// NimBLE has the whole heap; on success the boot simply continues with the
// station already connected, no second reboot.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"

typedef enum {
    ORION_PROV_WAITING,     // advertising, waiting for the phone
    ORION_PROV_CONNECTING,  // credentials received, station joining
    ORION_PROV_FAILED,      // wrong password or network not found, still in setup mode
    ORION_PROV_DONE,        // connected, setup mode ending
    ORION_PROV_TIMEOUT,     // nobody paired in time
} orion_prov_state_t;

// detail: the SSID while connecting, the reason when failed, the IP when done.
typedef void (*orion_prov_cb_t)(orion_prov_state_t state, const char *detail, void *ctx);

// "Orion-1a2b": the BLE name, from the station MAC. Valid from boot.
const char *orion_prov_device_name(void);
// "orion-1a2b": what the LAN API and the phone call this board.
const char *orion_prov_device_id(void);
// Six digits, drawn fresh by orion_prov_start. Empty before that.
const char *orion_prov_code(void);

// True when this boot should run setup mode: no Wi-Fi credentials, or the
// prov_boot flag left by orion_prov_request. Clears the flag.
bool orion_prov_should_run(void);
// From a running system: sets the flag and restarts into setup mode.
void orion_prov_request(const char *why);
// Same, half a second later on the esp_timer task. For callers on a task
// whose stack may not be internal RAM, such as the LVGL menu callback.
void orion_prov_request_async(const char *why);
// Restarts into setup mode if the network is still down after ms.
void orion_prov_watch(uint32_t ms);

esp_err_t orion_prov_start(orion_prov_cb_t cb, void *ctx);
// Blocks until the phone succeeded (ESP_OK), `prov stop` (ESP_ERR_INVALID_STATE)
// or timeout_ms passed (ESP_ERR_TIMEOUT).
esp_err_t orion_prov_wait(uint32_t timeout_ms);
// Ends setup mode: BLE off, manager freed, controller memory back in the heap.
void orion_prov_stop(void);
bool orion_prov_is_running(void);

// A boot that never uses Bluetooth calls this once so the heap is exactly
// what it was before BLE was compiled in.
void orion_prov_release_bt(void);

// Console: prov start|stop|status
esp_err_t orion_prov_register_cmds(void);
