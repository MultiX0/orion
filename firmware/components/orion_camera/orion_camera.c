// OV2640 through espressif/esp32-camera. The driver keeps its own frame
// buffer in PSRAM and its own DMA task; we only ask it for a frame when
// someone wants one. Mode changes (JPEG 640x480 for the vision path, small
// RGB565 for a screen preview) go through esp_camera_reconfigure, so either
// can be asked for at any time.
#include "orion_camera.h"

#include "board_pins.h"
#include "camera_priv.h"
#include "driver/gpio.h"
#include "esp_camera.h"
#include "esp_check.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static const char *TAG = "camera";

#define XCLK_HZ        20000000
#define JPEG_QUALITY   12          // 0 best, 63 worst. 12 is about 30 KB at VGA.
#define HOLD_TIMEOUT_MS 5000
#define FRESH_WINDOW_US 150000
#define SETTLE_FRAMES   4          // AGC frames to drop after a mode switch

static camera_config_t s_cfg = {
    .pin_pwdn = BOARD_CAM_PWDN,
    .pin_reset = BOARD_CAM_RESET,
    .pin_xclk = BOARD_CAM_XCLK,
    .pin_sccb_sda = BOARD_CAM_SIOD,
    .pin_sccb_scl = BOARD_CAM_SIOC,
    .pin_d7 = BOARD_CAM_Y9,
    .pin_d6 = BOARD_CAM_Y8,
    .pin_d5 = BOARD_CAM_Y7,
    .pin_d4 = BOARD_CAM_Y6,
    .pin_d3 = BOARD_CAM_Y5,
    .pin_d2 = BOARD_CAM_Y4,
    .pin_d1 = BOARD_CAM_Y3,
    .pin_d0 = BOARD_CAM_Y2,
    .pin_vsync = BOARD_CAM_VSYNC,
    .pin_href = BOARD_CAM_HREF,
    .pin_pclk = BOARD_CAM_PCLK,
    .xclk_freq_hz = XCLK_HZ,
    .ledc_timer = LEDC_TIMER_0,
    .ledc_channel = LEDC_CHANNEL_0,
    .pixel_format = PIXFORMAT_JPEG,
    .frame_size = FRAMESIZE_VGA,
    .jpeg_quality = JPEG_QUALITY,
    .fb_count = 1,
    .fb_location = CAMERA_FB_IN_PSRAM,
    .grab_mode = CAMERA_GRAB_WHEN_EMPTY,
    // The camera's SCCB pins are not the touch bus, so the driver opens its
    // own i2c_master bus on port 1.
    .sccb_i2c_port = -1,
};
// JPEG frame buffer: the driver's AUTO rule, width * height / 5, gives 61440
// bytes at VGA. Quality 12 frames come in around half that.

static SemaphoreHandle_t s_lock;
static camera_fb_t *s_fb;
static bool s_ready;
static bool s_ircut;
static uint32_t s_last_ms;
static uint32_t s_switch_ms;
static int64_t s_released_us;

esp_err_t orion_camera_ircut(bool on)
{
    s_ircut = on;
    return gpio_set_level(BOARD_IRCUT, on ? 1 : 0);
}

bool camera_ircut_state(void)
{
    return s_ircut;
}

// In a dim room the first frames average 15 of 255. Let the AGC go higher
// before giving up on a dark room. Reconfigure resets the sensor, so this
// runs after every mode change too.
static void apply_sensor_defaults(void)
{
    sensor_t *s = esp_camera_sensor_get();
    if (s) {
        s->set_gainceiling(s, GAINCEILING_16X);
    }
}

esp_err_t orion_camera_init(void)
{
    if (s_ready) {
        return ESP_OK;
    }
    s_lock = xSemaphoreCreateMutex();
    ESP_RETURN_ON_FALSE(s_lock, ESP_ERR_NO_MEM, TAG, "lock");

    gpio_config_t io = {
        .pin_bit_mask = 1ULL << BOARD_IRCUT,
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&io), TAG, "ircut gpio");
    orion_camera_ircut(false);

    int64_t t0 = esp_timer_get_time();
    ESP_RETURN_ON_ERROR(esp_camera_init(&s_cfg), TAG, "esp_camera_init");
    sensor_t *s = esp_camera_sensor_get();
    ESP_RETURN_ON_FALSE(s, ESP_FAIL, TAG, "no sensor");
    apply_sensor_defaults();
    s_ready = true;
    ESP_LOGI(TAG, "sensor pid 0x%02x ready in %u ms, jpeg 640x480 q%d, pwdn %d ircut %d off, xclk %d MHz",
             s->id.PID, (unsigned) ((esp_timer_get_time() - t0) / 1000), JPEG_QUALITY,
             BOARD_CAM_PWDN, BOARD_IRCUT, XCLK_HZ / 1000000);
    return ESP_OK;
}

// Reconfigures the driver only when the format or size actually changes.
static esp_err_t set_mode(pixformat_t fmt, framesize_t size)
{
    if (s_cfg.pixel_format == fmt && s_cfg.frame_size == size) {
        return ESP_OK;
    }
    camera_config_t c = s_cfg;
    c.pixel_format = fmt;
    c.frame_size = size;
    int64_t t0 = esp_timer_get_time();
    ESP_RETURN_ON_ERROR(esp_camera_reconfigure(&c), TAG, "reconfigure");
    apply_sensor_defaults();
    s_cfg = c;
    // The first frame after a switch averages 12 of 255: the exposure restarts
    // from scratch. Give it time.
    for (int i = 0; i < SETTLE_FRAMES; i++) {
        camera_fb_t *fb = esp_camera_fb_get();
        if (fb) {
            esp_camera_fb_return(fb);
        }
    }
    s_switch_ms = (uint32_t) ((esp_timer_get_time() - t0) / 1000);
    ESP_LOGI(TAG, "mode %s %dx%d in %u ms", fmt == PIXFORMAT_JPEG ? "jpeg" : "rgb565",
             resolution[size].width, resolution[size].height, (unsigned) s_switch_ms);
    return ESP_OK;
}

// The driver has been filling its single buffer since the last release, so
// the first frame is as old as that gap. Drop it and take the next one,
// unless the last release was moments ago, as in a preview loop, where the
// waiting frame is fresh and the flush would halve the frame rate.
static esp_err_t grab(pixformat_t fmt, framesize_t size)
{
    ESP_RETURN_ON_FALSE(s_ready, ESP_ERR_INVALID_STATE, TAG, "not initialised");
    ESP_RETURN_ON_FALSE(xSemaphoreTake(s_lock, pdMS_TO_TICKS(HOLD_TIMEOUT_MS)) == pdTRUE,
                        ESP_ERR_TIMEOUT, TAG, "previous frame never released");
    esp_err_t err = set_mode(fmt, size);
    if (err != ESP_OK) {
        xSemaphoreGive(s_lock);
        return err;
    }
    int64_t t0 = esp_timer_get_time();
    if (t0 - s_released_us > FRESH_WINDOW_US) {
        camera_fb_t *stale = esp_camera_fb_get();
        if (stale) {
            esp_camera_fb_return(stale);
        }
    }
    s_fb = esp_camera_fb_get();
    s_last_ms = (uint32_t) ((esp_timer_get_time() - t0) / 1000);
    if (!s_fb) {
        ESP_LOGE(TAG, "no frame after %u ms", (unsigned) s_last_ms);
        xSemaphoreGive(s_lock);
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t orion_camera_capture_jpeg(uint8_t **jpeg, size_t *len)
{
    *jpeg = NULL;
    *len = 0;
    ESP_RETURN_ON_ERROR(grab(PIXFORMAT_JPEG, FRAMESIZE_VGA), TAG, "grab");
    // A JPEG starts FF D8 and ends FF D9. Anything else is a torn frame.
    bool ok = s_fb->len > 4 && s_fb->buf[0] == 0xFF && s_fb->buf[1] == 0xD8 &&
              s_fb->buf[s_fb->len - 2] == 0xFF && s_fb->buf[s_fb->len - 1] == 0xD9;
    if (!ok) {
        ESP_LOGW(TAG, "frame of %u bytes is not a whole jpeg", (unsigned) s_fb->len);
        orion_camera_release();
        return ESP_ERR_INVALID_RESPONSE;
    }
    *jpeg = s_fb->buf;
    *len = s_fb->len;
    ESP_LOGI(TAG, "jpeg %ux%u, %u bytes, %u ms", (unsigned) s_fb->width, (unsigned) s_fb->height,
             (unsigned) s_fb->len, (unsigned) s_last_ms);
    return ESP_OK;
}

static framesize_t preview_size(uint16_t w, uint16_t h)
{
    static const framesize_t sizes[] = { FRAMESIZE_QQVGA, FRAMESIZE_HQVGA, FRAMESIZE_240X240, FRAMESIZE_QVGA };
    for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++) {
        if (resolution[sizes[i]].width >= w && resolution[sizes[i]].height >= h) {
            return sizes[i];
        }
    }
    return FRAMESIZE_QVGA;
}

esp_err_t orion_camera_capture_preview(uint16_t w, uint16_t h, uint8_t **rgb565, size_t *len,
                                       uint16_t *out_w, uint16_t *out_h)
{
    *rgb565 = NULL;
    *len = 0;
    ESP_RETURN_ON_ERROR(grab(PIXFORMAT_RGB565, preview_size(w, h)), TAG, "grab");
    *rgb565 = s_fb->buf;
    *len = s_fb->len;
    if (out_w) {
        *out_w = (uint16_t) s_fb->width;
    }
    if (out_h) {
        *out_h = (uint16_t) s_fb->height;
    }
    return ESP_OK;
}

void orion_camera_release(void)
{
    if (s_fb) {
        esp_camera_fb_return(s_fb);
        s_fb = NULL;
        s_released_us = esp_timer_get_time();
        xSemaphoreGive(s_lock);
    }
}

uint32_t orion_camera_last_capture_ms(void)
{
    return s_last_ms;
}

uint32_t camera_last_switch_ms(void)
{
    return s_switch_ms;
}
