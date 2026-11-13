idf_component_register(
    SRCS "orion_hub.c"
    INCLUDE_DIRS "include"
    PRIV_REQUIRES esp_http_client esp_netif esp_timer lwip console json orion_cloud orion_config orion_net orion_prov orion_settings
)
