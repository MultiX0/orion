idf_component_register(
    SRCS "orion_audio.c" "audio_spk.c" "audio_dsp.c" "audio_spk_cmds.c" "audio_wav.c"
         "audio_mic.c" "audio_ring.c" "audio_vad.c" "audio_cmds.c"
    INCLUDE_DIRS "include"
    REQUIRES esp_driver_i2s board
    PRIV_REQUIRES spiffs esp_psram console esp_timer vfs nvs_flash
)
