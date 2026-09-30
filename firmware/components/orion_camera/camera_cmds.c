// Console command: cam [jpeg|bench [n]|dump|preview [w h]|ircut <0|1>|info]
// "dump" prints the JPEG as base64 between ORION_JPEG_BEGIN and
// ORION_JPEG_END so a capture log can be turned back into a picture on the PC.
#include "orion_camera.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "camera_priv.h"
#include "esp_check.h"
#include "esp_console.h"
#include "esp_heap_caps.h"
#include "esp_timer.h"
#include "mbedtls/base64.h"

static const char *TAG = "camera";

static int capture_once(bool quiet)
{
    uint8_t *jpeg;
    size_t len;
    esp_err_t err = orion_camera_capture_jpeg(&jpeg, &len);
    if (err != ESP_OK) {
        printf("cam: %s\n", esp_err_to_name(err));
        return 1;
    }
    if (!quiet) {
        printf("cam: jpeg %u bytes in %u ms, psram free %u\n", (unsigned) len,
               (unsigned) orion_camera_last_capture_ms(),
               (unsigned) heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
    }
    orion_camera_release();
    return 0;
}

static int bench(int n)
{
    uint32_t total_ms = 0, min_ms = UINT32_MAX, max_ms = 0;
    size_t total_len = 0;
    int ok = 0;
    for (int i = 0; i < n; i++) {
        uint8_t *jpeg;
        size_t len;
        if (orion_camera_capture_jpeg(&jpeg, &len) != ESP_OK) {
            continue;
        }
        uint32_t ms = orion_camera_last_capture_ms();
        total_ms += ms;
        total_len += len;
        min_ms = ms < min_ms ? ms : min_ms;
        max_ms = ms > max_ms ? ms : max_ms;
        ok++;
        orion_camera_release();
    }
    if (ok == 0) {
        printf("cam bench: 0 of %d captures\n", n);
        return 1;
    }
    printf("cam bench: %d of %d ok, capture ms avg %u min %u max %u, jpeg avg %u bytes\n", ok, n,
           (unsigned) (total_ms / ok), (unsigned) min_ms, (unsigned) max_ms, (unsigned) (total_len / ok));
    return 0;
}

static int dump(void)
{
    uint8_t *jpeg;
    size_t len;
    esp_err_t err = orion_camera_capture_jpeg(&jpeg, &len);
    if (err != ESP_OK) {
        printf("cam dump: %s\n", esp_err_to_name(err));
        return 1;
    }
    size_t b64_len = 0;
    mbedtls_base64_encode(NULL, 0, &b64_len, jpeg, len);
    unsigned char *b64 = heap_caps_malloc(b64_len, MALLOC_CAP_SPIRAM);
    if (!b64 || mbedtls_base64_encode(b64, b64_len, &b64_len, jpeg, len) != 0) {
        printf("cam dump: no memory\n");
        free(b64);
        orion_camera_release();
        return 1;
    }
    orion_camera_release();
    printf("ORION_JPEG_BEGIN cam_%us %u\n", (unsigned) (esp_timer_get_time() / 1000000), (unsigned) len);
    fflush(stdout);
    write(fileno(stdout), b64, b64_len);
    printf("\nORION_JPEG_END\n");
    fflush(stdout);
    free(b64);
    return 0;
}

static int preview(int argc, char **argv)
{
    uint16_t w = argc > 2 ? atoi(argv[2]) : 160;
    uint16_t h = argc > 3 ? atoi(argv[3]) : 120;
    uint8_t *px;
    size_t len;
    uint16_t ow, oh;
    int64_t t0 = esp_timer_get_time();
    esp_err_t err = orion_camera_capture_preview(w, h, &px, &len, &ow, &oh);
    if (err != ESP_OK) {
        printf("cam preview: %s\n", esp_err_to_name(err));
        return 1;
    }
    // Ten frames in a row is what a screen preview would do.
    uint32_t first_ms = (uint32_t) ((esp_timer_get_time() - t0) / 1000);
    orion_camera_release();
    t0 = esp_timer_get_time();
    int frames = 0;
    for (int i = 0; i < 10; i++) {
        if (orion_camera_capture_preview(w, h, &px, &len, &ow, &oh) == ESP_OK) {
            frames++;
            orion_camera_release();
        }
    }
    uint32_t ten_ms = (uint32_t) ((esp_timer_get_time() - t0) / 1000);
    printf("cam preview: %ux%u rgb565 %u bytes, first frame %u ms (mode switch %u ms), then %d frames in %u ms = %u.%u fps\n",
           ow, oh, (unsigned) len, (unsigned) first_ms, (unsigned) camera_last_switch_ms(), frames,
           (unsigned) ten_ms, (unsigned) (frames * 1000 / ten_ms), (unsigned) (frames * 10000 / ten_ms % 10));
    return 0;
}

static int cmd_cam(int argc, char **argv)
{
    const char *sub = argc > 1 ? argv[1] : "jpeg";
    if (!strcmp(sub, "jpeg")) {
        return capture_once(false);
    }
    if (!strcmp(sub, "bench")) {
        return bench(argc > 2 ? atoi(argv[2]) : 10);
    }
    if (!strcmp(sub, "dump")) {
        return dump();
    }
    if (!strcmp(sub, "preview")) {
        return preview(argc, argv);
    }
    if (!strcmp(sub, "ircut")) {
        if (argc > 2) {
            orion_camera_ircut(atoi(argv[2]) != 0);
        }
        printf("cam ircut %s\n", camera_ircut_state() ? "on" : "off");
        return 0;
    }
    if (!strcmp(sub, "info")) {
        printf("cam last capture %u ms, last mode switch %u ms, ircut %s\n",
               (unsigned) orion_camera_last_capture_ms(), (unsigned) camera_last_switch_ms(),
               camera_ircut_state() ? "on" : "off");
        return 0;
    }
    printf("usage: cam [jpeg|bench [n]|dump|preview [w h]|ircut <0|1>|info]\n");
    return 1;
}

esp_err_t orion_camera_register_cmds(void)
{
    const esp_console_cmd_t cmd = {
        .command = "cam",
        .help = "cam [jpeg|bench [n]|dump|preview [w h]|ircut <0|1>|info]: OV2640",
        .func = cmd_cam,
    };
    ESP_RETURN_ON_ERROR(esp_console_cmd_register(&cmd), TAG, "register cam");
    return ESP_OK;
}
