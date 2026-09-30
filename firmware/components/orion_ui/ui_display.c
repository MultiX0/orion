// ST7789V over SPI and CST816S over the shared I2C bus, both handed to LVGL
// through esp_lvgl_port. Panel settings match what LilyGO ships for V1.2:
// 80 MHz, IPS inversion on, rotation 0, no offsets.
#include "ui_internal.h"

#include <stdio.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include "board.h"
#include "board_pins.h"
#include "driver/spi_master.h"
#include "esp_check.h"
#include "esp_lcd_io_i2c.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_touch_cst816s.h"
#include "esp_log.h"
#include "esp_lvgl_port.h"
#include "esp_timer.h"

static const char *TAG = "orion_ui";

#define UI_SPI_HOST  SPI2_HOST
#define UI_PCLK_HZ   (80 * 1000 * 1000)
// Two 30 line strips in internal DMA RAM, 28.8 KB. 60 lines would take
// another 28.8 KB of internal RAM the full firmware does not have, and 30
// still holds 30 fps or more in every state.
#define UI_BUF_LINES 30

static esp_lcd_panel_handle_t s_panel;
static esp_lcd_touch_handle_t s_touch;

static struct {
    int16_t x, y;
    bool pressed;
} s_fake;

static bool s_touch_log;
static uint32_t s_frames;
static uint32_t s_fps;
static int64_t s_fps_t0;

static esp_err_t lcd_init(esp_lcd_panel_io_handle_t *io)
{
    spi_bus_config_t bus = {
        .sclk_io_num = BOARD_LCD_SCLK,
        .mosi_io_num = BOARD_LCD_MOSI,
        .miso_io_num = BOARD_SPI_MISO, // the TF card shares this bus
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = UI_W * UI_H * 2,
    };
    ESP_RETURN_ON_ERROR(spi_bus_initialize(UI_SPI_HOST, &bus, SPI_DMA_CH_AUTO), TAG, "spi bus");

    esp_lcd_panel_io_spi_config_t io_cfg = {
        .cs_gpio_num = BOARD_LCD_CS,
        .dc_gpio_num = BOARD_LCD_DC,
        .spi_mode = 0,
        .pclk_hz = UI_PCLK_HZ,
        .trans_queue_depth = 10,
        .lcd_cmd_bits = 8,
        .lcd_param_bits = 8,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t) UI_SPI_HOST, &io_cfg, io),
                        TAG, "panel io");

    esp_lcd_panel_dev_config_t panel_cfg = {
        // -1 on V1.2: the driver sends a software reset instead of pulsing a pin.
        .reset_gpio_num = BOARD_LCD_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = 16,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7789(*io, &panel_cfg, &s_panel), TAG, "st7789");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_reset(s_panel), TAG, "reset");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_init(s_panel), TAG, "init");
    // IPS module: without inversion black comes out white.
    ESP_RETURN_ON_ERROR(esp_lcd_panel_invert_color(s_panel, true), TAG, "invert");
    return ESP_OK;
}

static esp_err_t touch_init(void)
{
    i2c_master_bus_handle_t bus = board_i2c_bus();
    if (bus == NULL) {
        ESP_LOGW(TAG, "board has no i2c bus yet, touch disabled");
        return ESP_ERR_INVALID_STATE;
    }

    esp_lcd_panel_io_i2c_config_t io_cfg = ESP_LCD_TOUCH_IO_I2C_CST816S_CONFIG();
    io_cfg.dev_addr = BOARD_TOUCH_ADDR;
    io_cfg.scl_speed_hz = BOARD_I2C_FREQ_HZ;
    esp_lcd_panel_io_handle_t io;
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_i2c(bus, &io_cfg, &io), TAG, "touch io");

    esp_lcd_touch_config_t cfg = {
        .x_max = UI_W,
        .y_max = UI_H,
        .rst_gpio_num = BOARD_TOUCH_RST,
        .int_gpio_num = BOARD_TOUCH_INT,
        .levels = { .reset = 0, .interrupt = 0 },
    };
    // The CST816 dozes until it is touched and can miss the first probe.
    esp_err_t err = ESP_FAIL;
    for (int i = 0; i < 3 && err != ESP_OK; i++) {
        err = esp_lcd_touch_new_i2c_cst816s(io, &cfg, &s_touch);
        if (err != ESP_OK) {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
    }
    return err;
}

static void on_render_ready(lv_event_t *e)
{
    (void) e;
    s_frames++;
    int64_t now = esp_timer_get_time();
    if (now - s_fps_t0 >= 1000000) {
        s_fps = s_frames;
        s_frames = 0;
        s_fps_t0 = now;
    }
}

// A second pointer the serial console can press, so tap and long press are
// testable without a finger on the glass.
static void fake_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    (void) indev;
    data->point.x = s_fake.x;
    data->point.y = s_fake.y;
    data->state = s_fake.pressed ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}

// Prints where each real press starts and ends, to check the glass against
// the drawing. The menu corner is 0..71 on both axes.
static void log_touch(lv_event_t *e)
{
    if (!s_touch_log) {
        return;
    }
    lv_point_t p;
    lv_indev_get_point(lv_event_get_user_data(e), &p);
    bool down = lv_event_get_code(e) == LV_EVENT_PRESSED;
    printf("touch %s x %d y %d%s\n", down ? "down" : "up", (int) p.x, (int) p.y,
           ui_in_btn_corner(&p) ? " menu corner" : "");
}

esp_err_t ui_display_init(lv_display_t **disp_out, lv_indev_t **indev_out)
{
    esp_lcd_panel_io_handle_t io;
    ESP_RETURN_ON_ERROR(lcd_init(&io), TAG, "lcd");

    lvgl_port_cfg_t port = ESP_LVGL_PORT_INIT_CONFIG();
    port.task_stack = 10240;
    // The stack lives in PSRAM. Internal RAM is the scarce thing once every
    // component runs, and the LVGL task never touches flash with the cache off.
    port.task_stack_caps = MALLOC_CAP_SPIRAM;
    port.task_affinity = 1; // Wi-Fi lives on core 0, rendering never waits for it
    ESP_RETURN_ON_ERROR(lvgl_port_init(&port), TAG, "lvgl port");

    lvgl_port_display_cfg_t dcfg = {
        .io_handle = io,
        .panel_handle = s_panel,
        .buffer_size = UI_W * UI_BUF_LINES,
        .double_buffer = true,
        .hres = UI_W,
        .vres = UI_H,
        .color_format = LV_COLOR_FORMAT_RGB565,
        .flags = { .buff_dma = 1, .swap_bytes = 1 },
    };
    lv_display_t *disp = lvgl_port_add_disp(&dcfg);
    ESP_RETURN_ON_FALSE(disp != NULL, ESP_FAIL, TAG, "add display");
    lv_display_add_event_cb(disp, on_render_ready, LV_EVENT_RENDER_READY, NULL);
    s_fps_t0 = esp_timer_get_time();

    *disp_out = disp;
    *indev_out = NULL;
    if (touch_init() == ESP_OK) {
        lvgl_port_touch_cfg_t tcfg = { .disp = disp, .handle = s_touch };
        *indev_out = lvgl_port_add_touch(&tcfg);
    }
    if (*indev_out) {
        lvgl_port_lock(0);
        lv_indev_add_event_cb(*indev_out, log_touch, LV_EVENT_PRESSED, *indev_out);
        lv_indev_add_event_cb(*indev_out, log_touch, LV_EVENT_RELEASED, *indev_out);
        lvgl_port_unlock();
    }

    lvgl_port_lock(0);
    lv_indev_t *fake = lv_indev_create();
    lv_indev_set_type(fake, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(fake, fake_read);
    lv_indev_set_display(fake, disp);
    lvgl_port_unlock();

    ESP_LOGI(TAG, "lcd %dx%d spi %d MHz, draw buffers 2 x %d lines internal, touch %s",
             UI_W, UI_H, UI_PCLK_HZ / 1000000, UI_BUF_LINES, s_touch ? "ok" : "off");
    return ESP_OK;
}

void ui_display_on(void)
{
    esp_lcd_panel_disp_on_off(s_panel, true);
    board_backlight(true);
}

uint32_t ui_display_fps(void)
{
    return s_fps;
}

void ui_display_fake_touch(int16_t x, int16_t y, bool pressed)
{
    s_fake.x = x;
    s_fake.y = y;
    s_fake.pressed = pressed;
}

void ui_display_touch_log(bool on)
{
    s_touch_log = on;
}
