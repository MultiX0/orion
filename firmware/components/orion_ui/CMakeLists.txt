set(assets "../../assets_src/ui")

idf_component_register(
    SRCS "orion_ui.c" "ui_display.c" "ui_anim.c" "ui_orb.c" "ui_idle.c" "ui_text.c"
         "ui_menu.c" "ui_style.c" "ui_star.c" "ui_setup.c" "ui_pair.c" "ui_cam.c" "ui_boot.c" "ui_cmds.c" "ui_mem.c"
         "${assets}/fonts/ui_font_text_22.c"
         "${assets}/fonts/ui_font_text_16.c"
         "${assets}/fonts/ui_font_mono_12.c"
         "${assets}/fonts/ui_font_code_40.c"
         "${assets}/fonts/ui_font_wordmark_36.c"
         "${assets}/images/ui_img_mark_96.c"
         "${assets}/images/ui_img_glow_128.c"
         "${assets}/images/ui_img_star_56.c"
         "${assets}/images/ui_img_test_frame.c"
    INCLUDE_DIRS "include"
    PRIV_INCLUDE_DIRS "."
    REQUIRES board
    PRIV_REQUIRES heap esp_driver_spi esp_lcd esp_driver_gpio esp_driver_i2c esp_timer
                  esp_app_format console mbedtls
                  lvgl__lvgl espressif__esp_lvgl_port espressif__esp_lcd_touch
                  espressif__esp_lcd_touch_cst816s
)

# ui_mem.c provides LVGL's allocator, but nothing in orion_ui calls it, so the
# linker would never pull it out of the archive. -u makes it.
target_link_libraries(${COMPONENT_LIB} INTERFACE "-u lv_mem_init")
