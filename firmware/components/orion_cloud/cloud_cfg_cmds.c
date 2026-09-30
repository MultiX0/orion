// Console commands that change the stored settings the way the LAN API will,
// for testing a provider switch without the app: set, then cloud_reload.
//
//   cfg_set stt_prov openai_compatible
//   cfg_copy di_key stt_key        a key is copied on the board, never typed
//   cfg_del stt_prov               back to the version 1 key or the default
//   cloud_reload
//
// cfg_set refuses the key names: a key typed at the console would be echoed
// into every serial log.

#include "cloud_private.h"

#include <stdio.h>
#include <string.h>

#include "esp_console.h"

#include "orion_config.h"

static bool is_secret(const char *key)
{
    const size_t n = strlen(key);
    return (n >= 4 && strcmp(key + n - 4, "_key") == 0) || strcmp(key, "wifi_pass") == 0;
}

static int cmd_set(int argc, char **argv)
{
    if (argc < 3) {
        printf("cfg_set usage: cfg_set <nvs key> <value>\n");
        return 1;
    }
    if (is_secret(argv[1])) {
        printf("cfg_set refuses %s: copy a stored key with cfg_copy instead\n", argv[1]);
        return 1;
    }
    const esp_err_t err = orion_config_set_str(argv[1], argv[2]);
    printf("cfg_set %s %s\n", argv[1], esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_copy(int argc, char **argv)
{
    if (argc < 3) {
        printf("cfg_set usage: cfg_copy <from key> <to key>\n");
        return 1;
    }
    char value[320];
    esp_err_t err = orion_config_get_str(argv[1], value, sizeof(value));
    if (err == ESP_OK) {
        err = orion_config_set_str(argv[2], value);
    }
    const size_t len = strlen(value);
    memset(value, 0, sizeof(value));
    // Length only, never the value, as everywhere else.
    printf("cfg_set %s -> %s, %u chars, %s\n", argv[1], argv[2], (unsigned) len,
           esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_del(int argc, char **argv)
{
    if (argc < 2) {
        printf("cfg_set usage: cfg_del <nvs key>\n");
        return 1;
    }
    const esp_err_t err = orion_config_erase(argv[1]);
    printf("cfg_set %s erased %s\n", argv[1], esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

void cloud_cfg_register_cmds(void)
{
    const esp_console_cmd_t cmds[] = {
        { .command = "cfg_set", .help = "cfg_set <key> <value>: store a setting", .func = cmd_set },
        { .command = "cfg_copy", .help = "cfg_copy <from> <to>: copy a stored key", .func = cmd_copy },
        { .command = "cfg_del", .help = "cfg_del <key>: remove a setting", .func = cmd_del },
    };
    for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) {
        esp_console_cmd_register(&cmds[i]);
    }
}
