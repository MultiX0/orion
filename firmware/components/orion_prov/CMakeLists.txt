idf_component_register(
    SRCS "orion_prov.c" "prov_pair.c" "prov_cmds.c" "prov_config.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_event
    PRIV_REQUIRES wifi_provisioning protocomm bt esp_wifi esp_netif esp_timer json console
                  orion_config orion_net orion_settings
)
