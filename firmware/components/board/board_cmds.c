// Console commands for poking the board from tools/serial_capture.py --send.
#include "board.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
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
    if (argc > 2 && !strcmp(argv[1], "ilim")) {
        if (!strcmp(argv[2], "auto")) {
            err = board_power_limit_auto();
        } else {
            // Under 500 mA a board with no battery browns out.
            char *end = NULL;
            const long ma = strtol(argv[2], &end, 10);
            if (end == argv[2] || *end || ma < 500 || ma > 3250) {
                printf("usage: power ilim <500..3250|auto>\n");
                return 1;
            }
            err = board_power_set_limit_by_hand((int) ma);
        }
        printf("power input limit %d mA: %s\n", board_sy6970_input_limit_ma(), esp_err_to_name(err));
        return err == ESP_OK ? 0 : 1;
    }
    if (argc > 1 && !strcmp(argv[1], "watch")) {
        // How often the charger holds the input back while something runs:
        // IDPM, at its current limit; VDPM, the source's voltage sagging.
        const int secs = argc > 2 ? atoi(argv[2]) : 20;
        int n = 0, idpm = 0, vdpm = 0;
        const TickType_t end = xTaskGetTickCount() + pdMS_TO_TICKS(secs * 1000);
        while ((int32_t) (end - xTaskGetTickCount()) > 0) {
            uint8_t v;
            if (board_sy6970_reg(0x13, &v) == ESP_OK) {
                n++;
                idpm += (v & 0x40) != 0;
                vdpm += (v & 0x80) != 0;
            }
            vTaskDelay(pdMS_TO_TICKS(10));
        }
        printf("power watch %d s: %d samples, at the current limit %d (%.1f%%), source sagging %d (%.1f%%), limit %d mA\n",
               secs, n, idpm, n ? 100.0f * idpm / n : 0.0f, vdpm, n ? 100.0f * vdpm / n : 0.0f,
               board_sy6970_input_limit_ma());
        return 0;
    }
    static const char *chrg[] = { "idle", "pre", "fast", "done" };
    printf("power vbus %.2f V (stat %d, pg %d) vbat %.2f V vsys %.2f V ichg %d mA charge %s, input limit %d mA\n",
           s.vbus_v, s.vbus_stat, s.power_good, s.vbat_v, s.vsys_v, s.charge_ma, chrg[s.chrg_stat],
           board_sy6970_input_limit_ma());
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
        { .command = "power", .help = "power [watch <s> | ilim <mA>|auto]: SY6970 voltages, charge state, input limit", .func = cmd_power },
        { .command = "audio_en", .help = "audio_en <0|1>: mic and amp enable line", .func = cmd_audio_en },
        { .command = "bl", .help = "bl <0|1>: LCD backlight", .func = cmd_bl },
    };
    for (size_t i = 0; i < sizeof(cmds) / sizeof(cmds[0]); i++) {
        ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmds[i]), TAG, "register %s", cmds[i].command);
    }
    return ESP_OK;
}
