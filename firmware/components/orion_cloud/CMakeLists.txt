idf_component_register(
    SRCS "orion_cloud.c" "cloud_cfg.c" "cloud_net.c" "cloud_util.c" "cloud_pc.c"
         "cloud_asr.c" "cloud_tts.c" "cloud_reply.c" "cloud_stream.c"
         "cloud_sse.c" "cloud_chunk.c" "cloud_chunk_test.c" "cloud_json.c"
         "cloud_console.c" "cloud_admin.c" "cloud_cfg_cmds.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_http_client
    PRIV_REQUIRES orion_config orion_camera orion_audio orion_net
                  esp-tls json mbedtls spiffs console esp_timer
)
