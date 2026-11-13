// Internal to the board component.
#pragma once

#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

esp_err_t board_button_init(void);

esp_err_t board_sy6970_init(i2c_master_bus_handle_t bus);

typedef struct {
    float vbus_v;
    float vbat_v;
    float vsys_v;
    int charge_ma;
    int vbus_stat;   // REG0B bits 7:5
    int chrg_stat;   // REG0B bits 4:3, 0 idle, 1 pre, 2 fast, 3 done
    bool power_good;
} board_sy6970_status_t;

esp_err_t board_sy6970_read(board_sy6970_status_t *out);
esp_err_t board_sy6970_reg(uint8_t reg, uint8_t *val);
esp_err_t board_sy6970_set_input_limit(int ma);
int board_sy6970_input_limit_ma(void);
// power ilim <mA>: a limit set by hand, which board_power_keep leaves alone,
// to stand in for a weak USB port.
esp_err_t board_power_set_limit_by_hand(int ma);
// power ilim auto: the board's own limit again, kept by board_power_keep.
esp_err_t board_power_limit_auto(void);
