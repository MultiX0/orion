// Console commands for the screen, so every state and every string can be
// driven from tools/serial_capture.py --send without a finger or a voice.
#include "ui_internal.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "freertos/idf_additions.h"

#include "esp_check.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_lvgl_port.h"
#include "mbedtls/base64.h"
#include "orion_ui.h"

static const char *TAG = "orion_ui";

// Weak, so orion_ui keeps no build dependency on orion_camera. In the full
// firmware main links orion_camera and these resolve; `ui cam live` then
// shows the real sensor before main wires ui_set_camera_preview itself.
esp_err_t orion_camera_capture_preview(uint16_t w, uint16_t h, uint8_t **rgb565, size_t *len,
                                       uint16_t *out_w, uint16_t *out_h) __attribute__((weak));
void orion_camera_release(void) __attribute__((weak));

// Two fixed Arabic lines, one of them mixed with English. Compiled in so a
// console encoding problem can never be mistaken for a shaping problem.
static const char *AR_HELLO = "أهلين! أنا أوريون، شو بتحب أساعدك فيه اليوم؟";
static const char *AR_MIXED = "فتحتلك الـ Spotify على الـ PC.";

static void join(int argc, char **argv, int from, char *out, size_t n)
{
    size_t len = 0;
    for (int i = from; i < argc && len + 1 < n; i++) {
        if (i > from) {
            out[len++] = ' ';
        }
        len += lv_strlcpy(out + len, argv[i], n - len);
        if (len >= n) {
            len = n - 1;
            break;
        }
    }
    out[len] = 0;
}

// The screen as base64 RGB565, so what is actually on the glass can be turned
// back into a PNG on the PC. This is the only honest evidence for Arabic
// shaping: a log line proves nothing about joined letters.
// Runs on its own task: LVGL's render path needs far more stack than the
// console REPL task has, and it overflows it loudly if you call it inline.
static SemaphoreHandle_t s_shot_done;

static void shot_task(void *arg)
{
    (void) arg;
    // Entrances last 700 ms and a text swap fades first. Let them land, or
    // every screenshot is a picture of a transition.
    vTaskDelay(pdMS_TO_TICKS(900));
    const size_t bytes = UI_W * UI_H * 2;
    uint8_t *raw = heap_caps_malloc(bytes, MALLOC_CAP_SPIRAM);
    if (raw == NULL) {
        printf("shot: no psram\n");
        xSemaphoreGive(s_shot_done);
        vTaskDeleteWithCaps(NULL);
        return;
    }
    lv_draw_buf_t buf;
    lv_draw_buf_init(&buf, UI_W, UI_H, LV_COLOR_FORMAT_RGB565, UI_W * 2, raw, bytes);
    lvgl_port_lock(0);
    lv_result_t r = lv_snapshot_take_to_draw_buf(lv_screen_active(), LV_COLOR_FORMAT_RGB565, &buf);
    lvgl_port_unlock();
    if (r != LV_RESULT_OK) {
        free(raw);
        printf("shot: snapshot failed\n");
        xSemaphoreGive(s_shot_done);
        vTaskDeleteWithCaps(NULL);
        return;
    }

    static char line[4200];
    printf("SHOT BEGIN %d %d rgb565\n", UI_W, UI_H);
    for (size_t off = 0; off < bytes; off += 3072) {
        size_t n = (bytes - off) < 3072 ? (bytes - off) : 3072;
        size_t out = 0;
        mbedtls_base64_encode((unsigned char *) line, sizeof(line), &out, raw + off, n);
        line[out] = 0;
        printf("%s\n", line);
    }
    printf("SHOT END\n");
    free(raw);
    xSemaphoreGive(s_shot_done);
    vTaskDeleteWithCaps(NULL);
}

// Blocks, so a queued list of console commands stays in order.
static int shoot(void)
{
    if (s_shot_done == NULL) {
        s_shot_done = xSemaphoreCreateBinary();
    }
    if (xTaskCreateWithCaps(shot_task, "ui_shot", 10240, NULL, 4, NULL, MALLOC_CAP_SPIRAM) != pdPASS) {
        printf("shot: no task\n");
        return 1;
    }
    xSemaphoreTake(s_shot_done, pdMS_TO_TICKS(20000));
    return 0;
}

static const struct { const char *name; orion_state_t st; } STATES[] = {
    { "boot", OS_BOOT }, { "idle", OS_IDLE }, { "wake", OS_WAKE },
    { "listening", OS_LISTENING }, { "thinking", OS_THINKING },
    { "speaking", OS_SPEAKING }, { "error", OS_ERROR }, { "offline", OS_OFFLINE },
};

// fps per state, measured the same way every time.
static void perf_task(void *arg)
{
    (void) arg;
    static const orion_state_t ST[] = { OS_IDLE, OS_LISTENING, OS_THINKING, OS_SPEAKING, OS_WAKE };
    for (size_t i = 0; i < sizeof(ST) / sizeof(ST[0]); i++) {
        ui_set_state(ST[i]);
        uint32_t sum = 0, lo = 999;
        vTaskDelay(pdMS_TO_TICKS(1500));
        for (int k = 0; k < 4; k++) {
            ui_set_level(0.35f + 0.3f * (k & 1)); // a voice that moves
            vTaskDelay(pdMS_TO_TICKS(1000));
            uint32_t f = ui_fps();
            sum += f;
            lo = f < lo ? f : lo;
        }
        printf("perf %-10s fps avg %u min %u\n", orion_state_name(ST[i]), (unsigned) (sum / 4), (unsigned) lo);
    }
    printf("perf int %u free, psram %u free\n", (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
           (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    ui_set_state(OS_IDLE);
    vTaskDeleteWithCaps(NULL);
}

static const char *USAGE = "ui state|text|strip|tags|level|tap|touch|menu|scroll|boot|cam|setup|perf|fps|ar|shot|mem\n";

static int cmd_ui(int argc, char **argv)
{
    static char buf[512];
    if (argc < 2) {
        printf("%s", USAGE);
        return 1;
    }
    const char *sub = argv[1];

    if (strcmp(sub, "state") == 0 && argc >= 3) {
        for (size_t i = 0; i < sizeof(STATES) / sizeof(STATES[0]); i++) {
            if (strcmp(STATES[i].name, argv[2]) == 0) {
                ui_set_state(STATES[i].st);
                printf("state %s\n", STATES[i].name);
                return 0;
            }
        }
        printf("unknown state %s\n", argv[2]);
        return 1;
    }
    if (strcmp(sub, "text") == 0) {
        join(argc, argv, 2, buf, sizeof(buf));
        ui_set_text(buf);
        printf("text %d bytes\n", (int) strlen(buf));
        return 0;
    }
    if (strcmp(sub, "strip") == 0) {
        static char out[512];
        join(argc, argv, 2, buf, sizeof(buf));
        ui_strip_tags(buf, out, sizeof(out));
        printf("strip in  [%s]\nstrip out [%s]\n", buf, out);
        return 0;
    }
    if (strcmp(sub, "tags") == 0) {
        // Compiled in: the console drops every byte above 0x7F, so Arabic
        // typed over the wire never arrives.
        static const char *T[] = {
            "لا، هذا غلط. [laughing nervously] معك حق، أعتذر. عاصمة أستراليا كانبرا.",
            "سأل رجلٌ صديقه: لماذا وضعتَ ساعتك في البنك؟ [pause] قال: كي أوفّر الوقت [laugh]!",
        };
        static char out[512];
        int which = argc >= 3 ? atoi(argv[2]) : 1;
        const char *in = T[which == 2 ? 1 : 0];
        ui_strip_tags(in, out, sizeof(out));
        printf("tags in  [%s]\ntags out [%s]\n", in, out);
        ui_set_text(in);
        return 0;
    }
    if (strcmp(sub, "level") == 0 && argc >= 3) {
        ui_set_level((float) atof(argv[2]));
        return 0;
    }
    if (strcmp(sub, "tap") == 0) {
        ui_fire_tap();
        return 0;
    }
    if (strcmp(sub, "touch") == 0 && argc >= 3) {
        // ui touch on|off logs real presses; ui touch <x> <y> [ms] fakes one.
        if (argc == 3) {
            ui_display_touch_log(strcmp(argv[2], "on") == 0);
            return 0;
        }
        ui_display_fake_touch(atoi(argv[2]), atoi(argv[3]), true);
        vTaskDelay(pdMS_TO_TICKS(argc >= 5 ? atoi(argv[4]) : 100));
        ui_display_fake_touch(atoi(argv[2]), atoi(argv[3]), false);
        return 0;
    }
    if (strcmp(sub, "menu") == 0) {
        ui_set_net_info(argc >= 3, "OrionNet", argc >= 3 ? argv[2] : NULL, argc >= 4 ? atoi(argv[3]) : -55);
        ui_set_pc_info(argc >= 5, argc >= 6, "DESKTOP-ORION", "192.168.1.20");
        ui_menu_toggle();
        return 0;
    }
    if (strcmp(sub, "cam") == 0) {
        bool live = argc >= 3 && strcmp(argv[2], "live") == 0;
        if (live && orion_camera_capture_preview == NULL) {
            printf("cam: orion_camera is not linked into this image\n");
            return 1;
        }
        if (live) {
            ui_set_camera_preview(orion_camera_capture_preview, orion_camera_release);
        } else {
            ui_cam_self_test();
        }
        return 0;
    }
    if (strcmp(sub, "boot") == 0) {
        ui_boot_replay();
        return 0;
    }
    if (strcmp(sub, "scroll") == 0 && argc >= 3) {
        lvgl_port_lock(0);
        ui_menu_scroll(atoi(argv[2]));
        lvgl_port_unlock();
        return 0;
    }
    if (strcmp(sub, "fps") == 0) {
        printf("fps %u\n", (unsigned) ui_fps());
        return 0;
    }
    if (strcmp(sub, "perf") == 0) {
        xTaskCreateWithCaps(perf_task, "ui_perf", 4096, NULL, 4, NULL, MALLOC_CAP_SPIRAM);
        return 0;
    }
    if (strcmp(sub, "setup") == 0) {
        // ui setup <name> <code> | ui setup <0..3> [detail] | ui setup off
        if (argc >= 3 && strcmp(argv[2], "off") == 0) {
            ui_hide_setup();
        } else if (argc >= 4 && strlen(argv[3]) == 6) {
            ui_show_setup(argv[2], argv[3]);
        } else if (argc >= 3) {
            join(argc, argv, 3, buf, sizeof(buf));
            ui_set_setup_status(atoi(argv[2]), buf);
        }
        return 0;
    }
    if (strcmp(sub, "ar") == 0) {
        int which = argc >= 3 ? atoi(argv[2]) : 1;
        ui_set_text(which == 2 ? AR_MIXED : AR_HELLO);
        printf("ar %d\n", which);
        return 0;
    }
    if (strcmp(sub, "shot") == 0) {
        return shoot();
    }
    if (strcmp(sub, "mem") == 0) {
        printf("ui mem int %u free (min %u), psram %u free, fps %u\n",
               (unsigned) heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
               (unsigned) heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL),
               (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM),
               (unsigned) ui_fps());
        return 0;
    }
    printf("%s", USAGE);
    return 1;
}

esp_err_t ui_register_cmds(void)
{
    const esp_console_cmd_t cmd = {
        .command = "ui",
        .help = "ui state <name> | text <utf8> | level <0..1> | tap | touch on|off|<x> <y> [ms] | menu [ip] [rssi] [pc] [conn] | fps "
                "| setup | perf | ar <1|2> | tags <1|2> | shot | mem",
        .func = cmd_ui,
    };
    ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmd), TAG, "register ui");
    return ESP_OK;
}
