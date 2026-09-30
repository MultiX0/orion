idf_component_register(
    SRCS "orion_camera.c" "camera_cmds.c"
    INCLUDE_DIRS "include"
    REQUIRES board
    PRIV_REQUIRES esp_psram esp_timer console mbedtls esp_driver_gpio
)
