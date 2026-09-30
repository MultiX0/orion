idf_component_register(
    SRCS "orion_wakeword.c" "ww_model.cpp" "ww_frontend.c" "ww_manifest.c" "ww_clip.c" "ww_cmds.c"
    INCLUDE_DIRS "include"
    REQUIRES orion_audio
    PRIV_REQUIRES esp_partition json esp_timer console nvs_flash
)

# The model image for the raw "model" partition. Built from a .tflite and its
# JSON manifest, flashed by a plain `idf.py flash` like the app. Point
# ORION_WAKE_MODEL at another pair (path without extension) to switch models:
#   idf.py -D ORION_WAKE_MODEL=../wakeword/models/orion build
if(NOT ORION_WAKE_MODEL)
    set(ORION_WAKE_MODEL "${CMAKE_CURRENT_SOURCE_DIR}/models/orion")
endif()
get_filename_component(ORION_WAKE_MODEL "${ORION_WAKE_MODEL}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")

idf_build_get_property(python PYTHON)
set(ww_bin "${CMAKE_BINARY_DIR}/wakeword_model.bin")
add_custom_command(
    OUTPUT "${ww_bin}"
    COMMAND ${python} "${CMAKE_CURRENT_SOURCE_DIR}/tools/pack_model.py"
            "${ORION_WAKE_MODEL}.tflite" "${ORION_WAKE_MODEL}.json" "${ww_bin}"
    DEPENDS "${ORION_WAKE_MODEL}.tflite" "${ORION_WAKE_MODEL}.json"
            "${CMAKE_CURRENT_SOURCE_DIR}/tools/pack_model.py"
    COMMENT "Packing wake word model ${ORION_WAKE_MODEL}"
    VERBATIM
)
add_custom_target(wakeword_model ALL DEPENDS "${ww_bin}")
esptool_py_flash_to_partition(flash "model" "${ww_bin}")
add_dependencies(flash wakeword_model)
