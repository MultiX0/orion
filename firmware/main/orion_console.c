// esp_console over the USB port. Every component registers its own test
// commands here, so tools/serial_capture.py --send "<cmd>" can drive the whole
// board with nobody at the keyboard.
#include "orion_console.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "esp_console.h"
#include "esp_log.h"
#include "esp_heap_caps.h"

#include "board.h"
#include "orion_audio.h"
#include "orion_wakeword.h"
#include "orion_cloud.h"
#include "orion_camera.h"
#include "orion_config.h"
#include "orion_prov.h"
#include "orion_sm.h"
#include "orion_turn.h"

static const char *TAG = "console";

static int cmd_state(int argc, char **argv)
{
    turn_timing_t t;
    turn_last_timing(&t);
    printf("state %s turns %u\n", orion_state_name(sm_state()), (unsigned) sm_turn_count());
    printf("last asr_ms=%u llm_ms=%u tts_first_ms=%u tts_total_ms=%u total_ms=%u\n",
           (unsigned) t.asr_ms, (unsigned) t.llm_ms, (unsigned) t.tts_first_ms,
           (unsigned) t.tts_total_ms, (unsigned) t.total_ms);
    printf("heard: %s\nreply: %s\n", turn_last_transcript(), turn_last_reply());
    return 0;
}

static int cmd_wake(int argc, char **argv)
{
    sm_post(EV_WAKE, 0);
    return 0;
}

static int cmd_cancel(int argc, char **argv)
{
    sm_post(EV_CANCEL, 0);
    return 0;
}

static int hex_digit(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// ask <text>: a full turn through the state machine and the screen, minus the
// microphone. talk (from orion_cloud) is the same request without the UI.
static int cmd_ask(int argc, char **argv)
{
    if (argc < 2) {
        printf("usage: ask <text> | ask hex:<utf8 hex>\n");
        return 1;
    }
    char text[512] = "";
    if (strncmp(argv[1], "hex:", 4) == 0) {
        // Arabic, which the console's line reader does not pass whole.
        size_t w = 0;
        for (const char *h = argv[1] + 4; h[0] && h[1] && w + 1 < sizeof(text); h += 2) {
            const int hi = hex_digit(h[0]), lo = hex_digit(h[1]);
            if (hi < 0 || lo < 0) {
                printf("ask: bad hex\n");
                return 1;
            }
            text[w++] = (char) (hi * 16 + lo);
        }
        text[w] = '\0';
    } else {
        for (int i = 1; i < argc; i++) {
            if (i > 1) {
                strlcat(text, " ", sizeof(text));
            }
            strlcat(text, argv[i], sizeof(text));
        }
    }
    turn_set_pending_text(text);
    sm_post(EV_ASK, 0);
    return 0;
}

static int cmd_heap(int argc, char **argv)
{
    printf("heap_int=%u largest_int=%u psram_free=%u\n",
           (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
           (unsigned) heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL),
           (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    return 0;
}

// `vol` from orion_audio changes the level until the next reset. This one
// also stores it, so a muted board stays muted through flashes and reboots.
static int cmd_volume(int argc, char **argv)
{
    if (argc > 1) {
        int v = atoi(argv[1]);
        v = v < 0 ? 0 : (v > 100 ? 100 : v);
        orion_audio_set_volume((uint8_t) v);
        orion_config_set_i32(ORION_CFG_VOLUME, v);
    }
    printf("volume %u (saved)\n", (unsigned) orion_audio_get_volume());
    return 0;
}

static void reg(const char *name, const char *help, esp_console_cmd_func_t fn)
{
    const esp_console_cmd_t c = { .command = name, .help = help, .func = fn };
    ESP_ERROR_CHECK(esp_console_cmd_register(&c));
}

esp_err_t console_start(void)
{
    esp_console_repl_t *repl = NULL;
    esp_console_repl_config_t rc = ESP_CONSOLE_REPL_CONFIG_DEFAULT();
    rc.prompt = "orion>";
    rc.max_cmdline_length = 512;
    esp_console_dev_usb_serial_jtag_config_t hw = ESP_CONSOLE_DEV_USB_SERIAL_JTAG_CONFIG_DEFAULT();

    esp_err_t err = esp_console_new_repl_usb_serial_jtag(&hw, &rc, &repl);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "repl: %s", esp_err_to_name(err));
        return err;
    }

    esp_console_register_help_command();
    reg("state", "assistant state and the last turn's timings", cmd_state);
    reg("wake", "act as if the wake word fired", cmd_wake);
    reg("cancel", "abandon the current turn", cmd_cancel);
    reg("ask", "ask <text> | ask hex:<utf8 hex>: run a turn on typed text", cmd_ask);
    reg("heap", "free internal heap and psram", cmd_heap);
    reg("volume", "volume <0..100>: set and remember the volume", cmd_volume);

    board_register_cmds();
    orion_audio_register_cmds();
    orion_wakeword_register_cmds();
    orion_camera_register_cmds();
    orion_cloud_register_console();
    orion_prov_register_cmds();

    return esp_console_start_repl(repl);
}
