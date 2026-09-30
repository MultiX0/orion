// SY6970 charger and power path. Register map is the BQ25896 layout.
// Nothing on this board is powered through it that we have to switch on, so
// this only makes sure it stays configured and gives us live readings.
#include "board.h"

#include "board_pins.h"
#include "board_priv.h"
#include "esp_check.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "sy6970";

#define REG_ADC_CTRL  0x02
#define REG_CHG_CTRL  0x03
#define REG_TIMER     0x07
#define REG_STATUS    0x0B
#define REG_BATV      0x0E
#define REG_SYSV      0x0F
#define REG_VBUSV     0x11
#define REG_ICHG      0x12
#define REG_ID        0x14

#define I2C_TIMEOUT_MS 50

static i2c_master_dev_handle_t s_dev;

static esp_err_t rd(uint8_t reg, uint8_t *val)
{
    return i2c_master_transmit_receive(s_dev, &reg, 1, val, 1, I2C_TIMEOUT_MS);
}

static esp_err_t wr(uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = { reg, val };
    return i2c_master_transmit(s_dev, buf, sizeof(buf), I2C_TIMEOUT_MS);
}

static esp_err_t update(uint8_t reg, uint8_t clear, uint8_t set)
{
    uint8_t v;
    ESP_RETURN_ON_ERROR(rd(reg, &v), TAG, "read 0x%02x", reg);
    v = (v & ~clear) | set;
    return wr(reg, v);
}

esp_err_t board_sy6970_read(board_sy6970_status_t *out)
{
    if (!s_dev) {
        return ESP_ERR_NOT_FOUND;
    }
    uint8_t st, bat, sys, bus, ichg;
    ESP_RETURN_ON_ERROR(rd(REG_STATUS, &st), TAG, "status");
    ESP_RETURN_ON_ERROR(rd(REG_BATV, &bat), TAG, "batv");
    ESP_RETURN_ON_ERROR(rd(REG_SYSV, &sys), TAG, "sysv");
    ESP_RETURN_ON_ERROR(rd(REG_VBUSV, &bus), TAG, "vbusv");
    ESP_RETURN_ON_ERROR(rd(REG_ICHG, &ichg), TAG, "ichg");

    out->vbat_v = 2.304f + (bat & 0x7F) * 0.020f;
    out->vsys_v = 2.304f + (sys & 0x7F) * 0.020f;
    out->vbus_v = 2.6f + (bus & 0x7F) * 0.1f;
    out->charge_ma = (ichg & 0x7F) * 50;
    out->vbus_stat = (st >> 5) & 0x7;
    out->chrg_stat = (st >> 3) & 0x3;
    out->power_good = (st & 0x04) != 0;
    return ESP_OK;
}

esp_err_t board_sy6970_init(i2c_master_bus_handle_t bus)
{
    ESP_RETURN_ON_ERROR(i2c_master_probe(bus, BOARD_SY6970_ADDR, I2C_TIMEOUT_MS), TAG,
                        "no answer at 0x%02x", BOARD_SY6970_ADDR);

    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = BOARD_SY6970_ADDR,
        .scl_speed_hz = BOARD_I2C_FREQ_HZ,
    };
    ESP_RETURN_ON_ERROR(i2c_master_bus_add_device(bus, &cfg, &s_dev), TAG, "add device");

    uint8_t id = 0;
    ESP_RETURN_ON_ERROR(rd(REG_ID, &id), TAG, "id");

    // The I2C watchdog resets every register to default 40 s after the last
    // write. Off, so the settings below stick.
    ESP_RETURN_ON_ERROR(update(REG_TIMER, 0x30, 0x00), TAG, "watchdog");
    // ADC on and continuous, so power_info reads live values.
    ESP_RETURN_ON_ERROR(update(REG_ADC_CTRL, 0x00, 0xC0), TAG, "adc");
    // No OTG boost, charging enabled. Same as LilyGO's examples.
    ESP_RETURN_ON_ERROR(update(REG_CHG_CTRL, 0x20, 0x10), TAG, "charge");

    vTaskDelay(pdMS_TO_TICKS(60));

    board_sy6970_status_t s;
    ESP_RETURN_ON_ERROR(board_sy6970_read(&s), TAG, "first read");
    ESP_LOGI(TAG, "found, id reg 0x%02x, vbus %.2f V (stat %d) vbat %.2f V vsys %.2f V ichg %d mA chrg %d pg %d",
             id, s.vbus_v, s.vbus_stat, s.vbat_v, s.vsys_v, s.charge_ma, s.chrg_stat, s.power_good);
    return ESP_OK;
}

esp_err_t board_power_info(float *vbus_v, float *vbat_v, bool *charging)
{
    board_sy6970_status_t s;
    ESP_RETURN_ON_ERROR(board_sy6970_read(&s), TAG, "read");
    if (vbus_v) {
        *vbus_v = s.vbus_v;
    }
    if (vbat_v) {
        *vbat_v = s.vbat_v;
    }
    if (charging) {
        *charging = s.chrg_stat == 1 || s.chrg_stat == 2;
    }
    return ESP_OK;
}
