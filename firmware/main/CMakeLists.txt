idf_component_register(
    SRCS "main.c" "orion_sm.c" "orion_turn.c" "orion_console.c"
    INCLUDE_DIRS "."
    REQUIRES board orion_config orion_net orion_audio orion_wakeword orion_cloud orion_settings
             orion_camera orion_ui orion_prov orion_api console esp_timer spiffs esp_psram
             spi_flash nvs_flash esp_wifi esp_app_format
)

# Packs firmware/assets into the 2 MB "assets" partition and flashes it with the
# app. Without this the partition is never written, esp_vfs_spiffs_register
# fails on the board, and the earcons and system prompt silently never arrive.
spiffs_create_partition_image(assets ../assets FLASH_IN_PROJECT)
