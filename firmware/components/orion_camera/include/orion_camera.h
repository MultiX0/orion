// OV2640 over DVP. Capture on demand only, nothing runs in the background.
// Every capture hands out the driver's own frame buffer, which lives in PSRAM.
// One frame is held at a time: release it before asking for the next.
#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include "esp_err.h"

esp_err_t orion_camera_init(void);

// 640x480 JPEG for the vision path. Returns a JPEG in PSRAM.
// Call orion_camera_release when done with it.
esp_err_t orion_camera_capture_jpeg(uint8_t **jpeg, size_t *len);

// Small RGB565 frame for a screen preview. w and h pick the nearest sensor
// size at or above them (160x120, 240x176, 240x240, 320x240); *out_w and
// *out_h say what came back. Switching between this and the JPEG capture
// reconfigures the sensor, which costs a few hundred ms the first time.
esp_err_t orion_camera_capture_preview(uint16_t w, uint16_t h, uint8_t **rgb565, size_t *len,
                                       uint16_t *out_w, uint16_t *out_h);

void orion_camera_release(void);

// AP1511B_FBC on GPIO 16. Off by default, we shoot in daylight.
esp_err_t orion_camera_ircut(bool on);

uint32_t orion_camera_last_capture_ms(void);

// Console command: cam [jpeg|preview [w h]|ircut <0|1>|info]
esp_err_t orion_camera_register_cmds(void);
