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

#define REG_INPUT     0x00    // EN_HIZ, EN_ILIM, IINLIM (100 mA + 50 mA steps)
#define REG_ADC_CTRL  0x02
#define REG_CHG_CTRL  0x03
#define REG_TIMER     0x07
#define REG_STATUS    0x0B
#define REG_BATV      0x0E
#define REG_SYSV      0x0F
#define REG_VBUSV     0x11
#define REG_ICHG      0x12
#define REG_DPM       0x13    // VDPM_STAT, IDPM_STAT, IDPM_LIM: is the input being held back now
#define REG_ID        0x14

#define I2C_TIMEOUT_MS 50
// 500 mA, what the chip picks for most adapters, was hit 26 times in a 33 s
// answer at full volume; 1500 mA, none. A source that cannot give it is
// still protected by the chip's input voltage regulation.
#define BOARD_INPUT_LIMIT_MA 1500

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

esp_err_t board_sy6970_reg(uint8_t reg, uint8_t *val)
{
    if (!s_dev) {
        return ESP_ERR_NOT_FOUND;
    }
    return rd(reg, val);
}

// The most the board may draw from USB. Input detection sets it on its own,
// and sets 500 mA for an adapter it does not recognize, which is most of them
// (VBUS_STAT 5). With no battery to cover the peaks, a loud syllable on the
// speaker plus a Wi-Fi burst asks for more than that, the system rail sags,
// and the amplifier cuts out mid word. The ILIM pin's limit is ignored, and
// the chip's own input voltage regulation still protects a weak source.
esp_err_t board_sy6970_set_input_limit(int ma)
{
    if (!s_dev) {
        return ESP_ERR_NOT_FOUND;
    }
    if (ma < 100) ma = 100;
    if (ma > 3250) ma = 3250;
    const uint8_t code = (uint8_t) ((ma - 100) / 50);
    return update(REG_INPUT, 0xFF, code);       // EN_HIZ 0, EN_ILIM 0, IINLIM
}

// The charger is holding its input back this moment: at its current limit
// (IDPM), or keeping a weak source's voltage up (VDPM). With no battery to
// make up the difference the system rail sags, and the speaker's amplifier,
// on that rail, drops out mid word.
bool board_power_held_back(void)
{
    uint8_t v = 0;
    if (!s_dev || rd(REG_DPM, &v) != ESP_OK) {
        return false;
    }
    return (v & 0xC0) != 0;
}

int board_sy6970_input_limit_ma(void)
{
    uint8_t v = 0;
    if (!s_dev || rd(REG_INPUT, &v) != ESP_OK) {
        return -1;
    }
    return 100 + (v & 0x3F) * 50;
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
    // Room for the speaker's peaks: see board_sy6970_set_input_limit.
    ESP_RETURN_ON_ERROR(board_sy6970_set_input_limit(BOARD_INPUT_LIMIT_MA), TAG, "input limit");

    vTaskDelay(pdMS_TO_TICKS(60));

    board_sy6970_status_t s;
    ESP_RETURN_ON_ERROR(board_sy6970_read(&s), TAG, "first read");
    ESP_LOGI(TAG, "found, id reg 0x%02x, vbus %.2f V (stat %d) vbat %.2f V vsys %.2f V ichg %d mA chrg %d pg %d",
             id, s.vbus_v, s.vbus_stat, s.vbat_v, s.vsys_v, s.charge_ma, s.chrg_stat, s.power_good);
    return ESP_OK;
}

// Input detection runs again when the cable is plugged back in and sets its
// own limit: put ours back. Cheap, call it every minute.
static bool s_manual_limit;   // set from the console (power ilim): left alone

esp_err_t board_power_set_limit_by_hand(int ma)
{
    const esp_err_t err = board_sy6970_set_input_limit(ma);
    if (err == ESP_OK) {
        s_manual_limit = true;
    }
    return err;
}

esp_err_t board_power_limit_auto(void)
{
    s_manual_limit = false;
    return board_sy6970_set_input_limit(BOARD_INPUT_LIMIT_MA);
}

void board_power_keep(void)
{
    if (s_manual_limit) {
        return;
    }
    const int now = board_sy6970_input_limit_ma();
    if (now > 0 && now != BOARD_INPUT_LIMIT_MA) {
        ESP_LOGI(TAG, "input limit was %d mA, back to %d", now, BOARD_INPUT_LIMIT_MA);
        board_sy6970_set_input_limit(BOARD_INPUT_LIMIT_MA);
    }
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
