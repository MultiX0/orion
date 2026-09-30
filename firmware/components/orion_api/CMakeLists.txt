idf_component_register(
    SRCS "orion_api.c" "api_http.c" "api_ws.c" "api_cam.c" "api_config.c" "api_pair.c" "api_talk.c"
    INCLUDE_DIRS "include"
    REQUIRES board
    PRIV_REQUIRES esp_http_server esp_netif esp_wifi esp_event esp_timer esp_app_format json lwip
                  orion_config orion_net orion_prov orion_camera orion_settings
)
