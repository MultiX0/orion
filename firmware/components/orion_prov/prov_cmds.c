// Console: prov start | stop | status. start from a running system reboots
// into setup mode; stop ends a running setup mode early.
#include "orion_prov.h"
#include "prov_priv.h"

#include <stdio.h>
#include <string.h>

#include "esp_console.h"
#include "esp_log.h"

#include "orion_config.h"
#include "orion_net.h"

static const char *TAG = "orion_prov";

static int cmd_prov(int argc, char **argv)
{
    const char *sub = argc > 1 ? argv[1] : "status";
    if (strcmp(sub, "start") == 0) {
        if (orion_prov_is_running()) {
            printf("already in setup mode: name %s code %s\n",
                   orion_prov_device_name(), orion_prov_code());
            return 0;
        }
        printf("rebooting into setup mode\n");
        orion_prov_request("console");
        return 0;
    }
    if (strcmp(sub, "stop") == 0) {
        if (!orion_prov_is_running()) {
            printf("not in setup mode\n");
            return 0;
        }
        prov_request_stop();
        return 0;
    }
    // For LAN API tests without a phone. provision.py rewrites the whole NVS
    // partition, so a token stored by pairing does not survive a provisioning
    // run. Never echoed.
    if (strcmp(sub, "token") == 0 && argc > 2) {
        size_t n = strlen(argv[2]);
        if (n < 8 || n > 64) {
            printf("token must be 8 to 64 chars\n");
            return 1;
        }
        esp_err_t err = orion_config_set_str(ORION_CFG_APP_TOKEN, argv[2]);
        printf("app_token stored, %u chars: %s\n", (unsigned) n, esp_err_to_name(err));
        return 0;
    }
    char ip[16] = "";
    orion_net_ip(ip, sizeof(ip));
    printf("name %s id %s setup %s code %s net %s %s\n",
           orion_prov_device_name(), orion_prov_device_id(),
           orion_prov_is_running() ? "running" : "off",
           orion_prov_is_running() ? orion_prov_code() : "-",
           orion_net_is_up() ? "up" : "down", ip);
    prov_log_heap("now");
    return 0;
}

esp_err_t orion_prov_register_cmds(void)
{
    const esp_console_cmd_t c = {
        .command = "prov",
        .help = "prov [start|stop|status|token <t>]: Bluetooth Wi-Fi setup mode",
        .func = cmd_prov,
    };
    esp_err_t err = esp_console_cmd_register(&c);
    ESP_LOGI(TAG, "register prov: %s", esp_err_to_name(err));
    return err;
}
