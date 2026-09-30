idf_component_register(
    SRCS "orion_settings.c" "settings_store.c" "settings_json.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES esp_event esp_timer json log heap orion_config orion_cloud orion_audio
)
