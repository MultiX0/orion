// Power, buses and the user button. Call board_init once, before anything else.
#pragma once

#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c_master.h"

esp_err_t board_init(void);

// Shared 400 kHz bus: CST816S touch at 0x15 and SY6970 power chip at 0x6A.
i2c_master_bus_handle_t board_i2c_bus(void);

// Gates the PDM mic and the MAX98357A amp together. The pin is active low in
// hardware, this call takes the logical sense: true means the audio path is on.
// board_init leaves it off. orion_audio turns it on once the I2S clocks run,
// which is what keeps the amp from popping at boot.
esp_err_t board_audio_enable(bool on);
bool board_audio_enabled(void);

esp_err_t board_backlight(bool on);

typedef enum {
    BOARD_BTN_SHORT,
    BOARD_BTN_LONG,
} board_btn_event_t;

// Called from the esp_timer task. Keep it short, post to a queue if in doubt.
typedef void (*board_btn_cb_t)(board_btn_event_t event, void *ctx);

esp_err_t board_button_register(board_btn_cb_t cb, void *ctx);

// Reads the SY6970. Returns ESP_ERR_NOT_FOUND if the chip does not answer.
esp_err_t board_power_info(float *vbus_v, float *vbat_v, bool *charging);

// Console commands: power, audio_en, bl. Needs an esp_console REPL running.
esp_err_t board_register_cmds(void);
