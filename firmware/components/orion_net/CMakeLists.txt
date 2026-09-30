idf_component_register(
    SRCS "orion_net.c" "net_state.c" "net_diagnose.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_wifi esp_netif esp_event
    PRIV_REQUIRES orion_config nvs_flash
)
