// Verified pinmap for the LilyGO T-CameraPlus-S3 V1.2. No pin is hardcoded
// anywhere else in the firmware.
//
// Provenance, in order of authority:
//   [LG-PIN]  LilyGO components/private_library/pin_config.h, T_CameraPlus_S3_V1_2 block
//             github.com/Xinyuan-LilyGO/T-CameraPlus-S3
//   [LG-RM]   LilyGO README.md, "T-CameraPlus-S3_V1.2 版本" pin tables, same repo
//   [LG-EX]   Behaviour copied from LilyGO's own examples in that repo
//   [BOARD]   Confirmed at runtime on the board
//
// The store listing pinmap is V1.0/V1.1 in places and is wrong for V1.2. Two traps
// it sets: GPIO 4 is the camera power-down line, not a reset, and it never mentions
// the audio enable on GPIO 18 that both the mic and the amp sit behind.

#pragma once

#include "driver/gpio.h"

// ---------------------------------------------------------------------------
// PSRAM
// ---------------------------------------------------------------------------
// An ESP32-S3 with in-package octal PSRAM reserves GPIO 33 to 37, which would
// collide with the LCD and the I2C bus below. This board does not do that: it
// carries an external quad SPI PSRAM, so 33 to 37 are ordinary GPIOs.
// Evidence: LilyGO platformio.ini selects memory_type qio_qspi with qio_opi
// commented out, and their sdkconfig.defaults sets CONFIG_SPIRAM_MODE_QUAD=y.
// Our sdkconfig.defaults matches. Do not switch this to octal.

// ---------------------------------------------------------------------------
// Shared SPI bus: LCD and TF card
// ---------------------------------------------------------------------------
#define BOARD_SPI_SCLK        GPIO_NUM_35   // [LG-PIN] SPI_SCLK
#define BOARD_SPI_MOSI        GPIO_NUM_34   // [LG-PIN] SPI_MOSI
#define BOARD_SPI_MISO        GPIO_NUM_48   // [LG-PIN] SPI_MISO, V1.2 moved this from 37

// LCD: ST7789V, 240x240, module FP-133H01D
#define BOARD_LCD_SCLK        BOARD_SPI_SCLK
#define BOARD_LCD_MOSI        BOARD_SPI_MOSI
#define BOARD_LCD_CS          GPIO_NUM_36   // [LG-PIN] LCD_CS, was 34 on V1.0
#define BOARD_LCD_DC          GPIO_NUM_45   // [LG-PIN] LCD_DC
#define BOARD_LCD_BL          GPIO_NUM_46   // [LG-PIN] LCD_BL
#define BOARD_LCD_RST         (-1)          // [LG-PIN] LCD_RST -1, tied to chip reset on V1.2
#define BOARD_LCD_WIDTH       240
#define BOARD_LCD_HEIGHT      240

// TF card, same SPI bus as the LCD. Only one of the two may own the bus at a time.
#define BOARD_SD_CS           GPIO_NUM_21   // [LG-PIN] SD_CS
#define BOARD_SD_SCLK         BOARD_SPI_SCLK
#define BOARD_SD_MOSI         BOARD_SPI_MOSI
#define BOARD_SD_MISO         BOARD_SPI_MISO

// ---------------------------------------------------------------------------
// Shared I2C bus: CST816S touch and SY6970 power chip
// ---------------------------------------------------------------------------
#define BOARD_I2C_SDA         GPIO_NUM_33   // [LG-PIN] IIC_SDA, V1.2 moved this from 1
#define BOARD_I2C_SCL         GPIO_NUM_37   // [LG-PIN] IIC_SCL, V1.2 moved this from 2
#define BOARD_I2C_PORT        I2C_NUM_0
#define BOARD_I2C_FREQ_HZ     400000

#define BOARD_TOUCH_ADDR      0x15          // [LG-PIN] CST816_ADDRESS
#define BOARD_TOUCH_INT       GPIO_NUM_47   // [LG-PIN] TP_INT
#define BOARD_TOUCH_RST       (-1)          // [LG-PIN] TP_RST -1 on V1.2, was 48 on V1.0

#define BOARD_SY6970_ADDR     0x6A          // [LG-PIN] SY6970_ADDRESS
// V1.2 exposes no SY6970 interrupt line. V1.0/V1.1 had it on 47.

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------
// One enable line gates BOTH the PDM microphone and the MAX98357A amplifier,
// and it is ACTIVE LOW. Every LilyGO example writes LOW here before touching
// either peripheral. Leave it high and both look dead with no error.
// [LG-PIN] MP34DT05TR_MAX98357_EN, [LG-EX] DMIC_ReadData, Voice_Speaker, SD_Music
#define BOARD_AUDIO_EN        GPIO_NUM_18
#define BOARD_AUDIO_EN_ACTIVE 0

// Microphone: MP34DT05-A, PDM. On the ESP32-S3 only I2S port 0 can do PDM RX.
// LilyGO drives this with BCLK -1, which is how a PDM master is configured.
#define BOARD_MIC_CLK         GPIO_NUM_40   // [LG-PIN] MP34DT05TR_LRCLK, the PDM clock
#define BOARD_MIC_DATA        GPIO_NUM_38   // [LG-PIN] MP34DT05TR_DATA
#define BOARD_MIC_I2S_PORT    I2S_NUM_0
// BOARD_AUDIO_EN low also selects the left PDM slot, so capture mono from left.

// Speaker: MAX98357A, standard I2S TX. Must be port 1, port 0 is the PDM mic.
#define BOARD_SPK_BCLK        GPIO_NUM_41   // [LG-PIN] MAX98357A_BCLK
#define BOARD_SPK_LRCLK       GPIO_NUM_42   // [LG-PIN] MAX98357A_LRCLK
#define BOARD_SPK_DOUT        GPIO_NUM_39   // [LG-PIN] MAX98357A_DATA, was 38 on V1.0
#define BOARD_SPK_I2S_PORT    I2S_NUM_1

#define BOARD_MIC_SAMPLE_RATE 16000

// ---------------------------------------------------------------------------
// Camera: OV2640, DVP. Its SCCB bus is separate from the touch I2C bus.
// ---------------------------------------------------------------------------
#define BOARD_CAM_XCLK        GPIO_NUM_7    // [LG-PIN] OV2640_XCLK
#define BOARD_CAM_SIOD        GPIO_NUM_1    // [LG-PIN] OV2640_SDA
#define BOARD_CAM_SIOC        GPIO_NUM_2    // [LG-PIN] OV2640_SCL
#define BOARD_CAM_PWDN        GPIO_NUM_4    // [LG-PIN] OV2640_PWDN. NOT a reset line.
#define BOARD_CAM_RESET       (-1)          // [LG-PIN] OV2640_RESET -1 on V1.2
#define BOARD_CAM_VSYNC       GPIO_NUM_3    // [LG-PIN] OV2640_VSYNC, was 4 on V1.0
#define BOARD_CAM_HREF        GPIO_NUM_5    // [LG-PIN] OV2640_HREF
#define BOARD_CAM_PCLK        GPIO_NUM_10   // [LG-PIN] OV2640_PCLK

// Data bus. LilyGO names these D9..D2, which is the esp32-camera Y9..Y2
// convention. Y9 is the camera's D7 and Y2 is its D0.
#define BOARD_CAM_Y9          GPIO_NUM_6    // [LG-PIN] OV2640_D9, camera D7
#define BOARD_CAM_Y8          GPIO_NUM_8    // [LG-PIN] OV2640_D8, camera D6
#define BOARD_CAM_Y7          GPIO_NUM_9    // [LG-PIN] OV2640_D7, camera D5
#define BOARD_CAM_Y6          GPIO_NUM_11   // [LG-PIN] OV2640_D6, camera D4
#define BOARD_CAM_Y5          GPIO_NUM_13   // [LG-PIN] OV2640_D5, camera D3
#define BOARD_CAM_Y4          GPIO_NUM_15   // [LG-PIN] OV2640_D4, camera D2
#define BOARD_CAM_Y3          GPIO_NUM_14   // [LG-PIN] OV2640_D3, camera D1
#define BOARD_CAM_Y2          GPIO_NUM_12   // [LG-PIN] OV2640_D2, camera D0

// AP1511B_FBC drives the IR-cut filter. Off by default, we shoot in daylight.
#define BOARD_IRCUT           GPIO_NUM_16   // [LG-PIN] AP1511B_FBC

// ---------------------------------------------------------------------------
// User button
// ---------------------------------------------------------------------------
// KEY1 pulls to ground when pressed, so enable the internal pull-up.
#define BOARD_BUTTON          GPIO_NUM_17   // [LG-PIN] KEY1
#define BOARD_BUTTON_ACTIVE   0
