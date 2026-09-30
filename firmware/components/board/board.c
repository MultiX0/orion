#include "board.h"

#include "board_pins.h"
#include "board_priv.h"
#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_log.h"

static const char *TAG = "board";

static i2c_master_bus_handle_t s_bus;
static bool s_audio_on;

static esp_err_t gpio_out(gpio_num_t pin, int level)
{
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << pin,
        .mode = GPIO_MODE_OUTPUT,
    };
    esp_err_t err = gpio_config(&cfg);
    if (err == ESP_OK) {
        err = gpio_set_level(pin, level);
    }
    return err;
}

esp_err_t board_audio_enable(bool on)
{
    s_audio_on = on;
    return gpio_set_level(BOARD_AUDIO_EN, on ? BOARD_AUDIO_EN_ACTIVE : !BOARD_AUDIO_EN_ACTIVE);
}

bool board_audio_enabled(void)
{
    return s_audio_on;
}

esp_err_t board_backlight(bool on)
{
    return gpio_set_level(BOARD_LCD_BL, on ? 1 : 0);
}

i2c_master_bus_handle_t board_i2c_bus(void)
{
    return s_bus;
}

static esp_err_t i2c_init(void)
{
    i2c_master_bus_config_t cfg = {
        .i2c_port = BOARD_I2C_PORT,
        .sda_io_num = BOARD_I2C_SDA,
        .scl_io_num = BOARD_I2C_SCL,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_RETURN_ON_ERROR(i2c_new_master_bus(&cfg, &s_bus), TAG, "i2c bus");

    esp_err_t touch = i2c_master_probe(s_bus, BOARD_TOUCH_ADDR, 50);
    ESP_LOGI(TAG, "i2c sda %d scl %d: touch 0x%02x %s", BOARD_I2C_SDA, BOARD_I2C_SCL,
             BOARD_TOUCH_ADDR, touch == ESP_OK ? "found" : "no answer");
    return ESP_OK;
}

esp_err_t board_init(void)
{
    ESP_RETURN_ON_ERROR(gpio_out(BOARD_AUDIO_EN, !BOARD_AUDIO_EN_ACTIVE), TAG, "audio en");
    ESP_RETURN_ON_ERROR(gpio_out(BOARD_LCD_BL, 0), TAG, "backlight");
    ESP_RETURN_ON_ERROR(i2c_init(), TAG, "i2c");

    esp_err_t pmu = board_sy6970_init(s_bus);
    if (pmu != ESP_OK) {
        ESP_LOGW(TAG, "sy6970: %s, continuing on whatever power we have", esp_err_to_name(pmu));
    }

    ESP_RETURN_ON_ERROR(board_button_init(), TAG, "button");
    ESP_LOGI(TAG, "init done, audio path off until orion_audio turns it on");
    return ESP_OK;
}
