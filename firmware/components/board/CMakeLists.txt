idf_component_register(
    SRCS "board.c" "board_sy6970.c" "board_button.c" "board_cmds.c" "orion_state.c"
    INCLUDE_DIRS "include"
    REQUIRES driver esp_driver_i2c esp_driver_gpio
    PRIV_REQUIRES esp_timer console
)
