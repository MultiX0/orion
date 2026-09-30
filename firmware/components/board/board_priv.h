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
