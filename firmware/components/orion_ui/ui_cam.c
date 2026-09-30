// The camera card: a live preview in a 176 x 132 well. Frames are captured
// on their own task, never on the LVGL task, so a slow sensor can never stall
// the screen. Two PSRAM slots: the capture task writes the one not on screen,
// the LVGL side swaps them. Only runs while the menu is open.
//
// Preferred source is the sensor's own RGB565 at 160 x 120, which LVGL blits
// with no decode at all. The JPEG path stays as the fallback and for the
// built-in test frame; TJpgDec costs about 120 ms a 320 x 240 frame here.
#include "ui_internal.h"

#include <stdio.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/idf_additions.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include "esp_heap_caps.h"
#include "esp_lvgl_port.h"
#include "esp_timer.h"

#define VIEW_W     176
#define VIEW_H     132
#define HEAD_H     34
#define PREVIEW_W  160
#define PREVIEW_H  120
#define SLOT_BYTES (320 * 240 * 2)
#define SWAP_MS    30

typedef enum { SRC_NONE, SRC_PREVIEW, SRC_JPEG } src_kind_t;

static lv_obj_t *s_frame, *s_note;
static lv_timer_t *s_swap_timer;
static TaskHandle_t s_task;
static SemaphoreHandle_t s_lock;
static volatile bool s_run;

static src_kind_t s_kind;
static ui_rgb565_get_t s_preview;
static ui_jpeg_get_t s_jpeg;
static ui_jpeg_release_t s_release;

static uint8_t *s_slot[2];
static lv_image_dsc_t s_dsc[2];
static int s_front = -1, s_ready = -1;
static const char *s_err;
static uint32_t s_frames;
static int64_t s_t0;

int32_t ui_cam_height(void)
{
    return HEAD_H + VIEW_H + 2 * UI_SPACE_3;
}

void ui_cam_create(lv_obj_t *parent, int32_t w, int32_t pad)
{
    lv_obj_t *card = ui_card_new(parent, w, ui_cam_height());
    lv_obj_t *tag = ui_mono_label(card, UI_TEXT_FAINT, "// CAM");
    lv_obj_align(tag, LV_ALIGN_TOP_LEFT, 0, 0);
    lv_obj_t *title = ui_ar_label(card, UI_TEXT_WHITE, &ui_font_text_16, "الكاميرا");
    lv_obj_align(title, LV_ALIGN_TOP_RIGHT, 0, -6);

    lv_obj_t *well = lv_obj_create(card);
    ui_no_touch(well);
    lv_obj_set_size(well, VIEW_W, VIEW_H);
    lv_obj_align(well, LV_ALIGN_TOP_MID, 0, HEAD_H - pad / 2);
    lv_obj_set_style_bg_color(well, lv_color_hex(UI_BG_PRIMARY), 0);
    lv_obj_set_style_bg_opa(well, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(well, 1, 0);
    lv_obj_set_style_border_color(well, lv_color_hex(UI_TEXT_WHITE), 0);
    lv_obj_set_style_border_opa(well, UI_OPA_BORDER_SUBTLE, 0);
    lv_obj_set_style_radius(well, UI_RADIUS_SM, 0);
    lv_obj_set_style_pad_all(well, 0, 0);
    lv_obj_remove_flag(well, LV_OBJ_FLAG_OVERFLOW_VISIBLE);

    s_frame = lv_image_create(well);
    ui_no_touch(s_frame);
    lv_obj_add_flag(s_frame, LV_OBJ_FLAG_HIDDEN);
    s_note = ui_mono_label(well, UI_TEXT_FAINT, "// NO CAMERA");
    lv_obj_center(s_note);
}

// TJpgDec takes an in-memory JPEG's size from the descriptor, it does not
// read the SOF itself. Leave w and h at zero and it decodes nothing, silently.
static bool jpeg_size(const uint8_t *d, size_t len, uint32_t *w, uint32_t *h)
{
    for (size_t i = 2; i + 9 < len;) {
        if (d[i] != 0xFF) {
            i++;
            continue;
        }
        uint8_t m = d[i + 1];
        if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
            *h = ((uint32_t) d[i + 5] << 8) | d[i + 6];
            *w = ((uint32_t) d[i + 7] << 8) | d[i + 8];
            return *w > 0 && *h > 0;
        }
        if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
            i += 2;
            continue;
        }
        i += 2 + (((uint32_t) d[i + 2] << 8) | d[i + 3]);
    }
    return false;
}

// Copies one frame into the slot that is not on screen. The camera's own
// buffer is released straight after, so the sensor never waits on the UI.
static void publish(const uint8_t *px, size_t len, uint32_t w, uint32_t h, bool jpeg)
{
    xSemaphoreTake(s_lock, portMAX_DELAY);
    int b = (s_front == 0) ? 1 : 0;
    if (s_slot[b] == NULL) {
        s_slot[b] = heap_caps_malloc(SLOT_BYTES, MALLOC_CAP_SPIRAM);
    }
    if (s_slot[b] && len <= SLOT_BYTES) {
        if (jpeg) {
            memcpy(s_slot[b], px, len);
        } else {
            // The OV2640 sends RGB565 high byte first, LVGL wants it low byte
            // first. LV_COLOR_FORMAT_RGB565_SWAPPED would say so, but this
            // LVGL build cannot blend it (no Kconfig switch for it) and draws
            // nothing, so the swap happens here, in the copy we make anyway.
            const uint16_t *src = (const uint16_t *) px;
            uint16_t *dst = (uint16_t *) s_slot[b];
            for (size_t i = 0; i < len / 2; i++) {
                dst[i] = __builtin_bswap16(src[i]);
            }
        }
        lv_image_dsc_t *d = &s_dsc[b];
        memset(d, 0, sizeof(*d));
        d->header.magic = LV_IMAGE_HEADER_MAGIC;
        d->header.cf = jpeg ? LV_COLOR_FORMAT_RAW : LV_COLOR_FORMAT_RGB565;
        d->header.w = w;
        d->header.h = h;
        d->header.stride = jpeg ? w * 3 : w * 2;
        d->data = s_slot[b];
        d->data_size = len;
        s_ready = b;
        s_err = NULL;
    } else {
        s_err = "// FRAME TOO BIG";
    }
    xSemaphoreGive(s_lock);
}

static void capture_once(void)
{
    uint8_t *px = NULL;
    size_t len = 0;
    uint16_t w = 0, h = 0;
    if (s_kind == SRC_PREVIEW) {
        if (s_preview(PREVIEW_W, PREVIEW_H, &px, &len, &w, &h) == ESP_OK && px) {
            publish(px, len, w, h, false);
        } else {
            s_err = "// NO SIGNAL";
        }
    } else if (s_kind == SRC_JPEG) {
        uint32_t jw = 0, jh = 0;
        if (s_jpeg(&px, &len) == ESP_OK && px && jpeg_size(px, len, &jw, &jh)) {
            publish(px, len, jw, jh, true);
        } else {
            s_err = "// NO SIGNAL";
        }
    }
    if (px && s_release) {
        s_release();
    }
}

static void capture_task(void *arg)
{
    (void) arg;
    while (true) {
        if (!s_run || s_kind == SRC_NONE) {
            ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
            continue;
        }
        capture_once();
        // Let a frame already waiting be shown before the next one lands.
        vTaskDelay(pdMS_TO_TICKS(s_kind == SRC_JPEG ? 60 : 5));
    }
}

static void swap(lv_timer_t *t)
{
    (void) t;
    if (s_kind == SRC_NONE) {
        lv_label_set_text(s_note, "// NO CAMERA");
        return;
    }
    if (xSemaphoreTake(s_lock, 0) != pdTRUE) {
        return;
    }
    if (s_ready >= 0) {
        s_front = s_ready;
        s_ready = -1;
        lv_image_set_src(s_frame, &s_dsc[s_front]);
        // 1:1, centred. The 160 x 120 preview sits in the well with a quiet
        // matte round it; a bigger frame is cropped to its middle.
        lv_obj_set_size(s_frame, s_dsc[s_front].header.w, s_dsc[s_front].header.h);
        lv_obj_center(s_frame);
        lv_obj_remove_flag(s_frame, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(s_note, LV_OBJ_FLAG_HIDDEN);
        s_frames++;
    } else if (s_err && s_front < 0) {
        lv_label_set_text(s_note, s_err);
    }
    xSemaphoreGive(s_lock);
}

void ui_cam_set_source(ui_jpeg_get_t get, ui_jpeg_release_t release)
{
    if (s_kind == SRC_PREVIEW) {
        return; // the RGB565 preview wins whenever both are wired
    }
    s_jpeg = get;
    s_release = release;
    s_kind = get ? SRC_JPEG : SRC_NONE;
}

void ui_cam_set_preview(ui_rgb565_get_t get, ui_jpeg_release_t release)
{
    s_preview = get;
    s_release = release;
    s_kind = get ? SRC_PREVIEW : (s_jpeg ? SRC_JPEG : SRC_NONE);
}

// The built-in 320 x 240 test JPEG through the same path as a camera frame,
// for a board with no camera. Stays until a real source is set.
static esp_err_t test_get(uint8_t **jpeg, size_t *len)
{
    *jpeg = (uint8_t *) ui_img_test_frame;
    *len = ui_img_test_frame_len;
    return ESP_OK;
}

void ui_cam_self_test(void)
{
    s_preview = NULL;
    s_jpeg = test_get;
    s_release = NULL;
    s_kind = SRC_JPEG;
}

void ui_cam_run(bool on)
{
    if (s_lock == NULL) {
        s_lock = xSemaphoreCreateMutex();
        xTaskCreateWithCaps(capture_task, "ui_cam", 4096, NULL, 3, &s_task, MALLOC_CAP_SPIRAM);
        s_swap_timer = lv_timer_create(swap, SWAP_MS, NULL);
    }
    s_run = on;
    if (on) {
        s_frames = 0;
        s_t0 = esp_timer_get_time();
        lv_timer_resume(s_swap_timer);
        xTaskNotifyGive(s_task);
        return;
    }
    lv_timer_pause(s_swap_timer);
    uint32_t ms = (uint32_t) ((esp_timer_get_time() - s_t0) / 1000);
    if (s_frames && ms) {
        printf("cam: %u frames in %u ms, %u.%u fps, %s\n", (unsigned) s_frames, (unsigned) ms,
               (unsigned) (s_frames * 1000 / ms), (unsigned) (s_frames * 10000 / ms % 10),
               s_kind == SRC_PREVIEW ? "rgb565 preview" : "jpeg");
    }
}
