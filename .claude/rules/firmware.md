---
paths:
  - "firmware/**"
---

# Firmware rules

Full detail in `AGENTS.md` under "The firmware", "Firmware memory", "LVGL and the screen" and "Protocol rules".

- ESP-IDF 5.5.5, C; C++17 only in `orion_wakeword`. Components talk only through `include/` headers. Pins only from `board/include/board_pins.h`, screen colors and timings only from `orion_ui/ui_tokens.h`.
- Internal RAM is almost gone after a turn (27 to 40 KB free). New buffers go to PSRAM with `heap_caps_malloc(n, MALLOC_CAP_SPIRAM)`; DMA buffers (LCD, I2S) stay internal. Measure `heap` before and after and put the numbers in the commit.
- New tasks get PSRAM stacks (`xTaskCreateWithCaps(..., MALLOC_CAP_SPIRAM)`) unless they touch flash. A PSRAM-stack task never calls `orion_config_*`, NVS, SPIFFS or partition APIs; read settings at init, post writes to the event loop. A `...WithCaps` task never deletes itself.
- The console task has a 4 KB stack: deep work in a command runs on a helper task (`cloud_run_big`).
- Any `lv_*` call off the LVGL task holds `lvgl_port_lock(0)`. Screen callbacks run on the LVGL task: no blocking, no NVS writes, no restarts there. Text goes through `ui_set_text`. Keep `LV_USE_BIDI` and `LV_USE_ARABIC_PERSIAN_CHARS` and fonts with the Arabic presentation forms.
- Never start Bluetooth on a running system; setup mode is a reboot (`prov_boot`).
- One kept-alive HTTP client per host. Finish responses by reading them to the end, never `esp_http_client_flush_response`. SSE reads are 128 bytes. HTTPS always verifies with the certificate bundle.
- Fish: `format: "pcm"`, `latency: "balanced"`, no `prosody` block, no language hint on speech to text.
- Never log a key, token, auth header or a body that holds one. Print lengths.
- Configuration changes go in `sdkconfig.defaults`; delete `firmware/sdkconfig` after changing them. Never commit `sdkconfig` or `dependencies.lock`.
- `firmware/assets/` holds only files the chip opens (2 MB budget). Build inputs live in `firmware/assets_src/`; the generated font, image and token C files are rebuilt with the scripts in `firmware/assets_src/ui/tools/`, never edited by hand.
- Read the comments before changing a number: most record the measurement that chose it. Replace a number only with a new measurement, and write it in the comment.
- Board access only through `tools/flash.ps1`, `tools/serial_capture.py`, `tools/board_session.py`, `tools/cloud/console_session.py`. Ask first, flash the app partition only by default, `volume 0` unless sound is the test, never `idf.py monitor` from an agent.
- No em dashes, no emojis, including log strings and screen text.
