# Firmware

The board's firmware: an ESP-IDF v5.5.5 project in `firmware/` for the LilyGO T-CameraPlus-S3 V1.2 (ESP32-S3, 16 MB flash, 8 MB quad PSRAM). C everywhere, C++17 only where TensorFlow Lite Micro needs it. The version comes from `firmware/version.txt` (currently `1.0.0`).

By MultiX0 (https://github.com/MultiX0), under the PolyForm Noncommercial License 1.0.0. The boot log, `GET /api/info` and the wake word manifest all carry the author and the source.

This page is the map: building, flashing, partitions, boot, tasks, memory and every component. The deeper pages:

- [FIRMWARE_CLOUD.md](FIRMWARE_CLOUD.md): the voice pipeline on the board, speech to text, model, text to speech, brains, latency.
- [FIRMWARE_AUDIO.md](FIRMWARE_AUDIO.md): microphone, end of speech detection, speaker, loudness, earcons.
- [FIRMWARE_SCREEN.md](FIRMWARE_SCREEN.md): the 240x240 interface, Arabic text, the menu, the camera preview.
- [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md): every serial console command.
- [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md): the LAN API and Bluetooth setup.
- [WAKEWORD.md](WAKEWORD.md): the wake word model and its runtime.

## Building and flashing

### Anywhere ESP-IDF runs

Install ESP-IDF v5.5.5 for the `esp32s3` target, then from `firmware/`:

```
idf.py build
idf.py -p <port> flash
```

`idf.py flash` writes everything: bootloader, partition table, application, the assets image and the wake word model image. The build takes its configuration from `sdkconfig.defaults` only; `sdkconfig` is generated and gitignored.

`idf.py -p <port> app-flash` writes only the application and is much faster during development. It leaves the assets and the model alone.

The board's USB-C port is the ESP32-S3's own USB-Serial-JTAG; there is no USB-UART bridge. If flashing cannot connect: hold BOOT, tap RST, release BOOT, run again.

### The Windows wrappers

On Windows the repo has two PowerShell scripts that work from PowerShell 5.1 and from Git Bash:

```
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 -B C:\ob build      # a short build dir
tools\flash.ps1                    # full flash, as idf.py flash
tools\flash.ps1 -App               # the application only
tools\flash.ps1 -Bin <image> -Address 0x9000    # one partition image, through esptool
tools\flash.ps1 -Erase             # erase the whole flash
```

- `idf.ps1` finds ESP-IDF (`ORION_IDF_PATH`, `IDF_PATH`, then `C:\Espressif\frameworks`, `%USERPROFILE%\esp`, `C:\esp`), activates it and runs `idf.py` inside `firmware/`. `tools\idf.ps1 --esptool <args>` runs esptool inside the same environment. It clears the MSYS variables Git Bash leaks, because ESP-IDF refuses to start with "MSys/Mingw is not supported", and it keeps going past `export.ps1` writing its banner to stderr, which Windows PowerShell 5.1 would otherwise treat as a fatal error.
- `flash.ps1` reads the port from `tools\port.txt` (or `-Port COMx`) and takes an exclusive lock on `%USERPROFILE%\.orion\flash.lock` first, so a flash never collides with a serial capture. A lock older than 10 minutes, or whose holder process is gone, is taken over.
- Read the serial port with `python tools/serial_capture.py`, which shares the same lock. `idf.py monitor` never returns and is not used. See [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md).

### Things that bite

- **Long paths on Windows.** esp-tflite-micro's object paths are long, and from a checkout path over about 100 characters they pass Windows' 260 character limit: "fatal error: opening dependency file ... No such file or directory". Build into a short directory with `idf.py -B C:\ob build` and flash from there.
- **A stale `sdkconfig`.** An existing `firmware/sdkconfig` wins over `sdkconfig.defaults`. After pulling a change to the defaults, delete `firmware/sdkconfig` (and `sdkconfig.old`) so it is regenerated; otherwise old memory settings come back and the board runs out of internal RAM in ways that look like new bugs.
- **`dependencies.lock`** is gitignored. The pinned versions live in each component's `idf_component.yml`.
- **Full flash from an old branch** rewrites the assets and model partitions too. After testing an older build, flash the current `assets.bin` and model again, or the board speaks with an old prompt.

### Another wake word model

The model image is built from a `.tflite` and its JSON manifest, `firmware/components/orion_wakeword/models/orion.*` by default. Point the build at another pair (path without the extension):

```
idf.py -D ORION_WAKE_MODEL=../wakeword/models/orion_full2 build
```

The previous models are kept next to the current one for a one-command rollback: `orion_full2`, `orion_ft4`, `orion_ft`, `orion_v0`, and the stock `okay_nabu`.

## Partitions

`firmware/partitions.csv`, 16 MB flash:

| Name | Type | Offset | Size | Holds |
|---|---|---|---|---|
| `nvs` | data, nvs | `0x9000` | 24 KB | every setting, key and token |
| `phy_init` | data, phy | `0xf000` | 4 KB | RF calibration |
| `factory` | app | `0x10000` | 5 MB | the application |
| `assets` | data, spiffs | `0x510000` | 2 MB | earcons and the system prompt, mounted at `/assets` |
| `model` | data, raw | `0x710000` | 512 KB | the wake word model image, memory mapped |

`firmware/assets/` is packed into the `assets` image by `spiffs_create_partition_image` in `firmware/main/CMakeLists.txt`. It is a runtime filesystem: only what the chip opens belongs there. Build-time sources (fonts, the star SVG and the scripts that convert them to C arrays) live in `firmware/assets_src/` and never reach the board.

| File in `/assets` | What |
|---|---|
| `system_prompt.txt` | the board's system prompt, loaded once at boot (see [VOICE.md](VOICE.md)) |
| `earcons/wake.wav` | the wake chime, generated, not spoken |
| `earcons/thinking.wav` | "لحظة من فضلك." |
| `earcons/repeat.wav` | "عذراً، هل يمكنك الإعادة؟", when nothing was heard |
| `earcons/offline.wav` | "لا يوجد اتصال بالإنترنت حالياً." |
| `earcons/error.wav` | "عذراً، حدث خطأ ما. حاول مرة أخرى." |
| `speaker_check.wav` | a 4.9 s speech clip for `wav speaker_check.wav` |

The model image is a 32 byte header (`ORWW`, format version, JSON length, model length, model offset), the JSON manifest, then the `.tflite` aligned to 16 bytes. `tools/pack_model.py` in the component builds it; a plain `idf.py flash` writes it.

## Configuration

The important choices in `sdkconfig.defaults`, and why:

| Setting | Why |
|---|---|
| `CONFIG_SPIRAM_MODE_QUAD` | The board has an external quad SPI PSRAM, not in-package octal. Octal would take GPIO 33 to 37, which the screen and the I2C bus use. Do not change it. |
| `CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL=4096` | Anything over 4 KB goes to PSRAM unless the caller asks for internal. |
| `CONFIG_ESP_CONSOLE_USB_SERIAL_JTAG` | The console is on the native USB port. |
| `CONFIG_MBEDTLS_CERTIFICATE_BUNDLE`, `CONFIG_ESP_TLS_INSECURE=n` | Every HTTPS request verifies the server. Never turn this off. |
| `CONFIG_MBEDTLS_EXTERNAL_MEM_ALLOC` | TLS buffers (about 40 KB per kept-alive connection) in PSRAM. |
| `CONFIG_MBEDTLS_HARDWARE_AES=n` | Hardware AES needs internal DMA bounce buffers for PSRAM records, and mid turn there were none. |
| `CONFIG_ESP_WIFI_DYNAMIC_RX_BUFFER_NUM=64`, `CONFIG_LWIP_TCP_WND_DEFAULT=32768` | A 64 KB TCP window against 32 receive buffers let 24 kHz TTS bursts overflow the radio, and retransmission backoff left 11 to 18 s of silence mid answer. Now the window fits the buffers. |
| `CONFIG_LWIP_MAX_SOCKETS=16` | Two linked apps, the camera stream, the HTTP server and up to five cloud connections. |
| `CONFIG_LV_USE_BIDI`, `CONFIG_LV_USE_ARABIC_PERSIAN_CHARS` | Without them Arabic renders as isolated letters in the wrong order. |
| `CONFIG_LV_USE_CUSTOM_MALLOC` | LVGL allocates from PSRAM through `orion_ui/ui_mem.c`. |
| `CONFIG_BT_CTRL_RUN_IN_FLASH_ONLY` | The Bluetooth controller's 14.7 KB of IRAM code would otherwise cost internal RAM on every boot, for a radio used only in setup mode. |
| `CONFIG_ESP_PROTOCOMM_SUPPORT_SECURITY_VERSION_0=n` | Plain text provisioning sessions are never offered; the phone must know the code. |
| `CONFIG_HTTPD_WS_POST_HANDSHAKE_CB_SUPPORT` | ESP-IDF 5.5 calls only this callback after a WebSocket handshake, not the URI handler. Without it no token was ever checked and every link closed at its first ping. |
| `CONFIG_MDNS_TASK_CREATE_FROM_SPIRAM`, `CONFIG_MDNS_MEMORY_ALLOC_SPIRAM` | mDNS cost 29 KB of internal RAM before; about 0.5 KB after. |
| `CONFIG_ESP_TASK_WDT_TIMEOUT_S=30`, `CONFIG_FREERTOS_HZ=1000` | |

## Boot

`firmware/main/main.c`, in order. A subsystem that fails to start is logged and skipped, so the screen can say what is wrong instead of staying dark.

1. Report the chip, the version, the author and **the reason for the last reset** (`power on`, `brownout`, `panic`, `task watchdog` and so on). A brownout or power-on reset in the middle of speech is the supply giving way under the speaker.
2. `board_init`: I2C bus, SY6970, button. The audio enable stays off.
3. `orion_config_init`: NVS.
4. **Wi-Fi first**, before anything else takes internal RAM. Its receive buffers need DMA capable memory.
5. The screen, showing the boot animation.
6. The serial console (before setup mode, so `prov stop` works there).
7. **Setup mode** if there is no Wi-Fi saved or the `prov_boot` flag is set: Bluetooth, the setup screen, wait up to 10 minutes. Otherwise release the Bluetooth controller's memory. If a saved network is not up yet, arm the 30 s watch that restarts into setup mode.
8. Audio, wake word, camera, cloud. Apply the stored volume.
9. The state machine, which drives everything from here, then the LAN API.

The main task then logs the state, the turn count and free memory once a minute.

## Tasks

| Task | Stack | Where | Prio | Core | Job |
|---|---|---|---|---|---|
| `orion_sm` | 6 KB | internal | 5 | any | the state machine; every UI call; the mic level at 33 Hz while listening or speaking |
| `orion_turn` | 12 KB | internal | 4 | any | one turn: record, transcribe, reply; TLS handshakes run on it |
| `cloud_llm` | 12 KB | PSRAM | 4 | any | streams the model's reply and feeds the chunker |
| `cloud_tts` | 10 KB | PSRAM | 4 | any | turns each piece into PCM into the ring |
| `cloud_cmd` | 12 KB | PSRAM | | | helper for console commands that open TLS |
| `mic` | 4 KB | internal | 10 | 1 | PDM capture into the 4 s ring |
| `wakeword` | 8 KB | internal | 5 | 1 | features every 10 ms, the model every 30 ms |
| LVGL (`esp_lvgl_port`) | 10 KB | PSRAM | | 1 | rendering; Wi-Fi lives on core 0 |
| `ui_cam` | 4 KB | PSRAM | 3 | any | the menu's camera preview, only while the menu is open |
| HTTP server | 8 KB | PSRAM | | | the LAN API |
| `mjpeg` | 6 KB | PSRAM | 4 | any | the `/stream` loop, parked between viewers |
| console REPL | default | internal | | | serial commands |

A task whose stack is in PSRAM must never run while the flash cache is off, which means it must never read or write NVS or SPIFFS. That rule decides a lot: settings are read once into RAM, the prompt is loaded at init, and NVS writes from the HTTP server are posted to the default event loop, which has an internal stack. The first LAN API build broke it (the first authorised request read the device name from NVS on the HTTP task and reset the socket), and the rule has held since.

## Memory

Internal RAM is the scarce resource; see [ARCHITECTURE.md](ARCHITECTURE.md#internal-ram-is-the-constraint) for the decisions it forced. Typical numbers from the boot log (`after <step> heap int`, bytes free in internal RAM):

| After | Free internal |
|---|---|
| start | about 270 KB |
| Wi-Fi | about 198 KB |
| screen | about 164 KB |
| audio | about 144 KB |
| wake word | about 87 KB (its tensor arena is internal when it fits) |
| camera | about 65 KB |
| cloud | about 62 KB |
| LAN API serving | about 37 KB |
| after a voice turn, everything running | 27 to 41 KB |

PSRAM: about 8.2 MB free at idle. The large users are the 1.5 MB text to speech ring, the 4 s microphone ring, the camera frame buffer (60 KB), the LVGL heap, the 40 turn history and every TLS session's buffers.

`heap` on the console prints the current numbers.

## Components

Every component has a public header in `include/` and nothing else is shared. The console commands of each are in [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md).

### main

`main.c` (boot), `orion_sm.c` (the state machine), `orion_turn.c` (the turn worker), `orion_console.c` (the REPL and the commands `state`, `wake`, `cancel`, `ask`, `heap`, `volume`).

The state machine is one task and one queue of 16 events. Its inputs:

| Event | From |
|---|---|
| `EV_WAKE` | wake word |
| `EV_BUTTON` | short press on IO17, or `POST /api/talk` without text |
| `EV_TAP` | a tap on the screen |
| `EV_ASK` | typed text: `ask`, `POST /api/talk` with text, `/api/talk/snapshot` |
| `EV_SAY` | `POST /api/say` |
| `EV_CANCEL` | long press on IO17, `POST /api/stop`, `cancel` on the console |
| `EV_SPEECH_END`, `EV_ASR_DONE`, `EV_LLM_DONE`, `EV_TTS_CHUNK`, `EV_TTS_DONE`, `EV_ERROR` | the turn worker |
| `EV_PROGRESS` | the reply stream is alive: restart the 30 s deadline |
| `EV_TIMEOUT` | the 30 s deadline, counted from the last sign of progress |
| `EV_NET_UP`, `EV_NET_DOWN` | Wi-Fi |
| `EV_PC_INFO` | refresh the PC card after a health check |

Timers: the turn deadline (30 s without progress), the boot network wait (20 s, then offline), and the 40 s heartbeat that keeps the cloud connections warm and checks the PC brain while idle.

After each turn it logs one line:

```
turn=12 asr_ms=402 llm_ms=950 tts_first_ms=498 tts_total_ms=2210 total_ms=3950 heap_int=38112 psram_free=6723040
```

and the turn worker adds a detailed one:

```
turn_perf speech_end_to_audio_ms=2480 asr_ms=402 asr_connect_ms=0 llm_first_ms=431 llm_ms=950 tts_first_ms=498 first_audio_ms=1043 gap_ms=0 pieces=2 connect_llm=0 connect_tts=0 total_ms=3950
```

`speech_end_to_audio_ms` is the number that decides how fast Orion feels: the user stops talking, and this long later the first word comes out. `connect_*` are TLS setup times, 0 when the connection was warm. `gap_ms` is how long the speaker ran dry between pieces.

### board

The board support: I2C master on SDA 33, SCL 37 at 400 kHz (CST816S touch at 0x15, SY6970 at 0x6A), the SY6970 set up with its I2C watchdog off (it resets itself otherwise), continuous ADC, OTG off, charging on. The side button KEY1 on GPIO 17 is polled every 10 ms with a 3 sample debounce; held 700 ms it fires a long press. The backlight is on GPIO 46.

`board_audio_enable` drives GPIO 18, the single **active low** line that gates both the PDM microphone and the MAX98357A amplifier. It stays off at boot and `orion_audio` turns it on after the speaker's I2S clock is running, which keeps the amplifier from popping.

`include/board_pins.h` is the one place any pin is defined, with the source of each. Two traps in the store listing for this board: GPIO 4 is the camera's power-down line, not a reset (V1.2 has no camera reset), and the listing never mentions GPIO 18; leave it high and both the microphone and the speaker look dead with no error.

`orion_state.h` holds the one state enum the whole firmware shares: `boot`, `idle`, `wake`, `listening`, `thinking`, `speaking`, `error`, `offline`.

### orion_config

Typed reads and writes of the NVS namespace `orion`. Secrets are reported by length, never by value (`orion_config_report` at boot). Every key:

| Key | Type | Meaning | Written by |
|---|---|---|---|
| `wifi_ssid`, `wifi_pass` | string | the network | Bluetooth setup, `/api/provision`, `provision.py` |
| `app_token` | string | the newest paired app's token | Bluetooth pairing, `/api/pair`, `provision.py` |
| `app_tokens` | string | up to four tokens, newest first, comma separated | the LAN API |
| `device_name` | string | display name, default `Orion` | the app |
| `prov_boot` | i32 | 1: the next boot goes into setup mode | `prov start`, the menu, the 30 s watch |
| `volume` | i32 | 0 to 100, default 70 | the app, `volume`, `provision.py` |
| `ww_enabled` | i32 | `wake_word_enabled`: 0 stops the wake word listener, and the idle screen asks for a tap instead | the app |
| `tz` | string | the time zone as a POSIX TZ string, default `UTC0` | the app, sent from the phone's or the PC's own zone |
| `debug_clips` | i32 | 1: dump 2 s of audio around each wake | `ww debug 1` |
| `llm_prov`, `llm_url`, `llm_key`, `llm_model` | string | language model | the app, `provision.py` |
| `stt_prov`, `stt_url`, `stt_key`, `stt_model` | string | speech to text | the app, `provision.py` |
| `tts_prov`, `tts_url`, `tts_key`, `tts_model`, `tts_voice` | string | text to speech | the app, `provision.py` |
| `pc_enabled` | i32 | PC control on | the desktop app |
| `pc_url`, `pc_token` | string | the PC brain's address and the token the board sends it | the desktop app |
| `pc_approval` | string | `ask` or `auto` | any app |
| `vision_mode` | string | how the model gets the camera: `tool` (default: a question plainly about what is in front takes the picture first, anything else offers the `look` tool), `keyword` (only the picture-first phrases), `off` | `provision.py`, `cfg_set` |
| `wake_phrase` | string | written by `provision.py`; the phrase shown comes from the model manifest | `provision.py` |

Older keys still read when their newer key is missing, so a board set up by an older build keeps working: `di_key` (the DeepInfra key, for the model and any DeepInfra stage), `fish_key`, `fish_voice`, `asr_provider` (`fish` or `deepinfra`), `asr_model`. When the app changes a stage, the matching older key is kept in step, so a cleared key never comes back through the fallback.

`orion_config_erase_all` is the factory reset: every key in the namespace.

### orion_settings

The configuration as the API sees it: the `llm`, `stt`, `tts` and `pc` blocks of [the protocol](DEVICE_PROTOCOL.md#post-apiconfig). It keeps a RAM copy in PSRAM, merges a partial update onto a copy, validates every value, stores only the keys that changed, and tells the cloud to reload. It also applies the time zone (`setenv("TZ")` and `tzset()`) at boot and whenever it changes, and calls the hook set with `orion_settings_on_change`, which `main.c` turns into an `EV_SETTINGS` event so the state machine starts or stops the wake word. A write coming from the HTTP task (PSRAM stack) is posted to the event loop and waited for up to 5 s; a write from the Bluetooth endpoint (internal stack) happens directly. If a turn is running, the reload retries every second until it is over. Shared by the LAN API and Bluetooth setup mode.

### orion_net

The Wi-Fi station. It scans every channel and joins the strongest access point with the saved name (`WIFI_ALL_CHANNEL_SCAN`, `WIFI_CONNECT_AP_BY_SIGNAL`), uses 20 MHz channels, and never enables power save. It reconnects with backoff from 1 s to 30 s.

Why the scan: a home network is often several access points under one name, and the default fast scan joined whichever answered first, -55 dBm on one boot and -81 on another. At -80 dBm a spoken answer stalled for 11 to 18 s and a TLS handshake took 3.8 s. With the full scan it joins at -55 to -59.

After three failed attempts with no success, it scans and logs every 2.4 GHz network it can see, then says whether the saved name is in the scan (so the password is wrong) or not (so it is probably a 5 GHz only network, which this chip can never join). Disconnect reasons are logged by name.

It also starts SNTP (`pool.ntp.org`). The time zone comes from the settings (`tz`, set from the app), and the board's own model gets the local date and time from this clock.

`orion_net_set_paused` hands the station to the provisioning manager during setup mode, and `orion_net_start` adopts the connection the manager already made.

### orion_prov

Bluetooth setup mode: ESP Unified Provisioning over NimBLE, security 1 with the six digit code, and the `orion-pair` and `orion-config` endpoints. Names come from the station MAC (`Orion-a1b2`, `orion-a1b2`). Credentials are kept in RAM until the station actually connects, then written. On failure the manager is reset and Bluetooth stays up for another try. See [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md#bluetooth-setup-mode).

Setup mode is a boot mode, because the controller's memory can be released only once per boot. Entering it from a running system writes `prov_boot` and restarts. The rest of the system is not started until it ends, so NimBLE has the whole heap. Measured: 34 KB of internal RAM while Bluetooth is up, all of it back after release.

### orion_api

The LAN API: HTTP on port 80 (task stack in PSRAM, 8 sockets), `/ws` with links, `/capture` and `/stream`, mDNS, the UDP beacon, SNTP, the paired token list, the 40 turn history in PSRAM and the pairing code. It starts whenever Wi-Fi is up and stops when it goes down. It never touches NVS from the HTTP task: the device name, volume and tokens are cached, and writes go through the event loop. See [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md).

### orion_audio

Microphone on I2S0 in PDM RX (only port 0 can do PDM on the S3), speaker on I2S1 in standard TX. A 4 s capture ring in PSRAM with independent readers, a DC blocker and noise floor, the end of speech detector, the playback stream with fades, the loudness pipeline, WAV playback from `/assets`. See [FIRMWARE_AUDIO.md](FIRMWARE_AUDIO.md).

### orion_wakeword

ESPHome's micro_wake_word pipeline ported to this firmware: the micro speech features frontend (40 mel channels per 30 ms window, 10 ms step), the streaming model on TFLite Micro (`esp-tflite-micro` 1.3.x with `esp-nn`, the versions ESPHome validated), and the sliding window average against the manifest's cutoff, with a cooldown after each detection. The model partition is memory mapped. The tensor arena goes to internal RAM when it fits (PSRAM doubles the inference time) and falls back to PSRAM.

Cost, measured: 471 us of features per 10 ms step, 2.2 ms per inference every third step (3.9 ms worst), so about 12 percent of one core.

A detection must also pass an **energy gate**: the loudest 100 ms of the last 1.5 s must reach twice the noise floor and at least RMS 30. Silence reads 4 to 13, speech 40 to 180. The gate ends wakes on silence and on the microphone's own hum, whatever the model thinks; a rejection is logged as `gated`. See [WAKEWORD.md](WAKEWORD.md#on-the-board).

### orion_camera

The OV2640 through `esp32-camera`: XCLK 20 MHz on LEDC timer 0 channel 0, its own SCCB bus (GPIO 1 and 2), one frame buffer in PSRAM. Capture on demand only.

- `orion_camera_capture_jpeg`: 640x480 JPEG at quality 12, 9 to 31 KB depending on light, 54 to 79 ms per capture once running.
- `orion_camera_capture_preview`: RGB565 at the nearest of 160x120, 240x176, 240x240, 320x240, for the screen. Switching between JPEG and RGB565 costs about 180 ms plus 4 dropped frames while the exposure settles.
- A capture holds a lock until `orion_camera_release`; a second caller waits up to 5 s. A capture within 150 ms of the last release skips flushing the stale frame, which doubled the preview frame rate.
- The gain ceiling is 16x, for dim rooms. The IR cut filter (GPIO 16) is off by default.

### orion_cloud

The voice loop's network side: speech to text (Fish streaming or OpenAI compatible), the streaming chat completion with the look tool, the chunker, text to speech into a PSRAM ring, kept-alive connections with prewarm, the PC and phone brains, and the settings reload and stage tests. See [FIRMWARE_CLOUD.md](FIRMWARE_CLOUD.md).

### orion_ui

The screen: LVGL 9.4 through `esp_lvgl_port`, the ST7789 at 80 MHz SPI with two 30 line draw buffers in internal DMA memory, the CST816S touch. The idle face, the orb and the star, the text box, the menu, the setup and pairing screens, the camera preview, and the console tools to drive and screenshot it. See [FIRMWARE_SCREEN.md](FIRMWARE_SCREEN.md).

## Making a release

See [RELEASING.md](RELEASING.md).
