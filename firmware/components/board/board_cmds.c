// Console commands for poking the board from tools/serial_capture.py --send.
#include "board.h"

#include <stdio.h>
#include <stdlib.h>
#include "board_priv.h"
#include "esp_check.h"
#include "esp_console.h"

static const char *TAG = "board";

static int cmd_power(int argc, char **argv)
{
    board_sy6970_status_t s;
    esp_err_t err = board_sy6970_read(&s);
    if (err != ESP_OK) {
        printf("sy6970: %s\n", esp_err_to_name(err));
        return 1;
    }
    static const char *chrg[] = { "idle", "pre", "fast", "done" };
    printf("power vbus %.2f V (stat %d, pg %d) vbat %.2f V vsys %.2f V ichg %d mA charge %s\n",
           s.vbus_v, s.vbus_stat, s.power_good, s.vbat_v, s.vsys_v, s.charge_ma, chrg[s.chrg_stat]);
    return 0;
}

static int on_off(int argc, char **argv, esp_err_t (*fn)(bool), const char *what)
{
    if (argc < 2) {
        printf("usage: %s <0|1>\n", what);
        return 1;
    }
    bool on = atoi(argv[1]) != 0;
    esp_err_t err = fn(on);
    printf("%s %s: %s\n", what, on ? "on" : "off", esp_err_to_name(err));
    return err == ESP_OK ? 0 : 1;
}

static int cmd_audio_en(int argc, char **argv)
{
    return on_off(argc, argv, board_audio_enable, "audio_en");
}

static int cmd_bl(int argc, char **argv)
{
    return on_off(argc, argv, board_backlight, "bl");
}

esp_err_t board_register_cmds(void)
{
    const esp_console_cmd_t cmds[] = {
        { .command = "power", .help = "SY6970 voltages and charge state", .func = cmd_power },
        { .command = "audio_en", .help = "audio_en <0|1>: mic and amp enable line", .func = cmd_audio_en },
        { .command = "bl", .help = "bl <0|1>: LCD backlight", .func = cmd_bl },
    };
    for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) {
        ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmds[i]), TAG, "register %s", cmds[i].command);
    }
    return ESP_OK;
}
