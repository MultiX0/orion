# AGENTS.md

Guidance for anyone changing Orion with a coding assistant (Claude Code, Codex, Cursor and the like), and honestly for people too. This is the single source of truth for how the repo is built, tested and changed. Tool-specific files (`CLAUDE.md`, `.claude/`) only point back here and add what that tool needs.

## What Orion is

Orion is a home voice assistant you build yourself. The hardware is a LilyGO T-CameraPlus-S3 V1.2 (ESP32-S3, 16 MB flash, 8 MB quad PSRAM, 240x240 touch screen, PDM mic, I2S speaker, OV2640 camera). The board runs the whole voice loop on its own over Wi-Fi: it hears its wake word, streams your speech to a speech to text service, streams the reply from any OpenAI-compatible model, speaks it through Fish Audio (or another OpenAI-compatible voice), and shows it on screen. No PC is needed.

The Flutter app (Android, iOS, Windows, Linux) sets the board up over Bluetooth, chooses its models and keys, shows the conversation and the camera, and on a desktop turns the PC into an extended "brain" with tools: it answers the board's turns with the date, the web and memory, and can act on the PC. A phone can serve a smaller brain the same way.

Languages that matter: Arabic and English, often mixed in one sentence. Arabic is a first-class case everywhere (the screen, the prompt, the wake word, the tests), never an afterthought.

License: PolyForm Noncommercial 1.0.0 (`LICENSE`), by MultiX0. Keep the author line and the license notice where they already are (boot log, `/api/info` `source`, `lib/core/project.dart`, the About card).

## Repo map

```
firmware/              ESP-IDF 5.5.5 project for the board
  main/                boot order, state machine (orion_sm), turn worker (orion_turn), console
  components/          one component per concern, public API in include/
    board/             pins (board_pins.h is the only place a pin is written), I2C, SY6970, button
    orion_audio/       PDM mic on I2S0, speaker on I2S1, DSP, VAD, WAV playback
    orion_wakeword/    microWakeWord on TFLite Micro; models/ holds the packed model pairs
    orion_camera/      OV2640, JPEG and RGB565 preview
    orion_net/         Wi-Fi station, scan, diagnosis
    orion_config/      typed NVS reads and writes, the only home of secrets on the board
    orion_settings/    config v2 in RAM, merge, validate, masked render, store
    orion_cloud/       STT, LLM (SSE), TTS pipeline, PC and phone brains, keep-alive sockets
    orion_prov/        Bluetooth setup mode (Espressif Unified Provisioning)
    orion_api/         LAN HTTP API, WebSocket, MJPEG stream, mDNS, UDP beacon, LAN pairing
    orion_ui/          LVGL screen: orb, star, text box, menu, setup and pairing screens
  assets/              runtime files packed into the 2 MB SPIFFS "assets" partition
  assets_src/          build-time sources and generators (fonts, images, tokens); never flashed
  partitions.csv       nvs 0x9000, app 0x10000 (5 MB), assets 0x510000 (2 MB), model 0x710000
  sdkconfig.defaults   the only build configuration; firmware/sdkconfig is generated and ignored
  version.txt          firmware version
lib/                   Flutter app, feature first
  app/                 MaterialApp, go_router table, shell (bottom nav on mobile, rail on desktop)
  core/                theme and tokens, widgets, motion, network, storage, platform, Result
  features/<name>/     domain/ (pure Dart), data/ (implementations, providers), presentation/
  features/harness/    desktop tool server, native tools, PC and phone brain, dsh runtime
test/                  mirrors lib/, fixtures in test/fixtures/
tool/                  Dart and Python dev tools for the app: mock board, token and icon
                       generators, PC brain probe and eval, headless PC harness
tools/                 board tooling (Windows): idf.ps1, flash.ps1, serial_capture.py,
                       board_session.py, replay_clips.ps1, ui_shot.py
tools/cloud/           Python scripts against the real services and the board: provisioning,
                       prompt tests, latency probes, console drivers, earcons
wakeword/              microWakeWord training scripts, the shipped model, test clips
voice/                 how Orion's voice was chosen, auditions
brand/                 the design source of truth: tokens, colors, type, motion, voice, logo
case/                  3D printed enclosure: build123d CAD, Blender scenes, STL, 3MF, renders
harness/dsh/           notes for the optional DeepSeek Harness agent runtime
docs/                  architecture, protocol, harness, providers, firmware, UI, code style
```

Read before changing an area:

| Area | Read |
|---|---|
| Anything the app and board both touch | `docs/DEVICE_PROTOCOL.md` |
| PC and phone brain, tools, approvals | `docs/HARNESS.md` |
| Models, keys, Fish Audio | `docs/PROVIDERS.md` |
| App structure, state, dependencies | `docs/ARCHITECTURE.md`, `docs/CODE_STYLE.md` |
| Screens and motion | `docs/UI.md`, `brand/` |
| Flashing, releases, reset | `docs/FIRMWARE.md` |
| Wake word | `wakeword/README.md` |
| Case | `case/SPEC.md` |

## Setup

- Flutter stable with Dart `^3.12.1` (see `pubspec.yaml`), plus the desktop toolchain for your OS (`flutter doctor`).
- ESP-IDF v5.5.5 for the firmware. On Windows `tools/idf.ps1` finds it in `ORION_IDF_PATH`, `IDF_PATH`, `C:\Espressif\frameworks`, `%USERPROFILE%\esp` or `C:\esp`.
- Python 3.10 to 3.13 for `tools/` and `tools/cloud/` (`pip install pyserial requests pillow`). Wake word training needs its own Python 3.11 or 3.12 inside WSL2 or Linux, see `wakeword/README.md`.
- A `.env` at the repo root for the dev scripts only (gitignored; copy `.env.example`). The scripts read `FISH_API_KEY`, `DEEPINFRA_API_KEY`, `WIFI_SSID`, `WIFI_PASSWORD` and optional overrides (`LLM_MODEL`, `FISH_VOICE_ID`, `FISH_TTS_MODEL`, the `LLM_*`, `STT_*`, `TTS_*` names in `tools/cloud/provision.py`). The app and the board never read it.

On Windows, Python scripts that print Arabic need `PYTHONIOENCODING=utf-8` (the console defaults to cp1252 and raises `UnicodeEncodeError`).

## The app

From the repo root. Generated Dart (`*.g.dart`, `*.freezed.dart`) is gitignored, so generate it after every checkout and after changing any `@riverpod`, `@freezed` or `@JsonSerializable` class.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

No board? Run the mock in a second terminal. It implements all of `docs/DEVICE_PROTOCOL.md` in memory on port 8080 and beacons on UDP 7332.

```
dart run tool/mock_device/main.dart                  # config version 2
dart run tool/mock_device/main.dart --config-v1      # an older board
dart run tool/mock_device/main.dart --flaky          # drops the WebSocket every 20 s
```

Run the app. In onboarding, pick the mock, or enter `localhost:8080` (`10.0.2.2:8080` from the Android emulator). The mock's LAN pairing code is `123456`.

```
flutter run -d windows
flutter run -d linux                                  # builds, but has had little real use
flutter run -d <android device id>                    # flutter devices lists ids
flutter run -d windows --dart-define=ORION_FAKE_BLE=true   # scripted Bluetooth setup, code 123456
```

Mock keys that script failures: an API key `bad` fails its test with 401, a Fish speech to text key `nocredit` answers 402, `busy` answers 409.

Before every commit:

```
flutter analyze            # zero issues
dart format .              # must change nothing
flutter test
dart run custom_lint       # the Riverpod lints, when you touched providers
```

Builds:

```
flutter build windows                      # build/windows/x64/runner/Release/
flutter build apk --debug                  # build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
flutter build linux
```

A Windows build from a very deep path (a nested worktree, for example) fails with MSB3491 in a plugin tlog. Build from a short checkout path. The Android emulator has no Bluetooth and cannot receive the board's UDP beacon; use a real phone for setup over Bluetooth. iOS is configured but has not been built.

## The firmware

### Windows

`tools/idf.ps1` loads the ESP-IDF environment and runs `idf.py` in `firmware/`. It works from PowerShell and from Git Bash (it clears the MSYS variables ESP-IDF refuses to run with).

```
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 -B C:\ob build     # deep checkout paths, see below
```

If your checkout path is long, esp-tflite-micro's object paths pass Windows' 260 character limit and the build fails with "opening dependency file ... No such file or directory". Build into a short directory with `-B` and flash from there.

Every flash goes through `tools/flash.ps1`, which takes the board lock first. Put your port in `tools/port.txt` or pass `-Port COMx`.

```
tools\flash.ps1                                                  # bootloader, table, app, assets, model
tools\flash.ps1 -Bin firmware\build\orion.bin -Address 0x10000   # the app only, keeps assets, model, NVS
tools\flash.ps1 -Bin firmware\build\assets.bin -Address 0x510000 # assets only (prompt, earcons)
tools\flash.ps1 -Bin firmware\build\wakeword_model.bin -Address 0x710000
tools\flash.ps1 -App                                             # idf.py app-flash
tools\flash.ps1 -Erase                                           # erase everything, settings included
```

Run each as `powershell -ExecutionPolicy Bypass -File tools\flash.ps1 ...` if your execution policy blocks scripts. The `-Bin` forms pass the port to esptool explicitly. The plain, `-App` and `-Erase` forms hand `-p <port>` to `idf.ps1`, where Windows PowerShell binds `-p` to its own `-PipelineVariable` parameter, so idf.py ends up finding the port by itself; with more than one serial device attached, prefer the `-Bin` forms. `tools/cloud/build_flash_app.ps1` builds into `C:\ocl_build` and writes the app partition only if the build succeeded.

Serial is read non-interactively, through the same lock:

```
python tools/serial_capture.py --seconds 20 --out logs/boot.txt
python tools/serial_capture.py --seconds 15 --no-reset --send "volume 0" --send "ask What is the capital of Jordan?" --out logs/ask.txt
python tools/cloud/console_session.py --out logs/session.txt "vol 0" "talk What time is it?" "heap"
python tools/board_session.py --app firmware/build/orion.bin --out logs/run.txt --seconds 60
```

`logs/` is gitignored. `console_session.py` sends one command, waits for that command's result line, then sends the next. `board_session.py` holds the lock across flash, reset and capture (and can play WAVs through the PC with `--play`), so nothing else can flash in between.

### Linux

The PowerShell wrappers, `serial_capture.py`, `board_session.py` and the lock are Windows only today (they use `%USERPROFILE%` and Win32 process checks). On Linux use ESP-IDF directly:

```
. ~/esp/esp-idf/export.sh          # wherever ESP-IDF v5.5.5 is installed
cd firmware
idf.py build
idf.py -p /dev/ttyACM0 flash
idf.py -p /dev/ttyACM0 app-flash
python -m esptool --chip esp32s3 -p /dev/ttyACM0 write_flash 0x510000 build/assets.bin
idf.py -p /dev/ttyACM0 monitor     # interactive, Ctrl+] to leave; people only, never an automated agent
```

The board enumerates as a USB-Serial-JTAG device (VID 303A, PID 1001). If it will not connect: hold BOOT, tap RST, release BOOT, try again.

### Build facts

- The build takes its configuration from `sdkconfig.defaults` only. An existing `firmware/sdkconfig` wins over the defaults, so after any change to `sdkconfig.defaults` (or after merging one) delete `firmware/sdkconfig` and rebuild. A stale one silently brought back old memory settings more than once.
- `firmware/dependencies.lock` is gitignored and regenerated. Component versions are pinned in each component's `idf_component.yml` (LVGL 9.4.0, esp_lvgl_port 2.9.0, esp-tflite-micro 1.3.x as ESPHome uses, esp32-camera 2.1.7, mdns 1.13.1).
- The build packs `firmware/assets/` into `build/assets.bin` and the wake word model into `build/wakeword_model.bin` (`orion_wakeword/tools/pack_model.py`). Switch models with `idf.py -D ORION_WAKE_MODEL=<path without extension> build`.
- The version is `firmware/version.txt`.

### Keys on a dev board

The app writes keys to the board during setup. For a board on your desk without the app, `python tools/cloud/provision.py` builds an NVS image from `.env` in the system temp folder, flashes it at 0x9000 and deletes it (`--dry-run` builds and shows it without flashing). This replaces every setting in NVS.

### Console

The board runs an `esp_console` REPL on the USB port (`orion>`). `help` lists everything. Useful ones:

| Command | Does |
|---|---|
| `state` | assistant state and the last turn's timings, transcript and reply |
| `ask <text>`, `ask hex:<utf8 hex>` | a full typed turn through the state machine, screen and voice |
| `talk <text>`, `say <text>` | a streamed reply without the state machine; speak a fixed line |
| `wake`, `cancel` | act as if the wake word fired; abandon the turn |
| `heap` | free internal heap, largest internal block, free PSRAM |
| `volume <0..100>` | set and save the volume (`vol` changes it until reset only) |
| `cloud_status`, `cloud_test llm\|stt\|tts`, `cloud_reload`, `cloud_selftest` | cloud stages and on-chip parser tests |
| `cfg_set`, `cfg_copy`, `cfg_del` | change NVS settings without the app (keys are copied on the board, never typed) |
| `ww ...`, `mic`, `micmon`, `spk ...`, `tone`, `wav`, `record`, `loopback`, `selftest` | wake word and audio |
| `cam ...`, `ui ...` (`ui shot`), `prov ...`, `power`, `bl`, `audio_en` | camera, screen, setup mode, power |

The console drops every byte above 0x7F, so Arabic goes in as `hex:` (`python tools/cloud/talk_hex.py "<arabic>"` prints the `talk hex:` form). Its receive buffer is small: a long line sent at once loses bytes, so keep typed lines short or send them in pieces of about 48 bytes, 30 ms apart. `ui shot` dumps the screen; `python tools/ui_shot.py <capture> <out.png>` turns it into a PNG.

## Wake word

Training runs in WSL2 or Linux, never on the Windows side, and its venv, datasets and checkpoints live outside git (`~/orion_ww` inside WSL, or the gitignored `wakeword/data/` and `wakeword/work/`). The full pipeline and every dataset source are in `wakeword/README.md`. Commit only scripts, the README, the shipped `.tflite` with its `.json` manifest and the small test clips. Run long training in a detached `tmux` session: WSL kills processes started by a `wsl.exe` call when that call returns, and `nohup` does not prevent it. Keep `*.sh` files LF (`wakeword/.gitattributes`), since `core.autocrlf` turns them CRLF and bash then fails on every line.

A new model reaches the board by copying the pair into `firmware/components/orion_wakeword/models/` (or pointing `ORION_WAKE_MODEL` at it), rebuilding and flashing the model partition. Report both measures the README describes (the confusable holdout and false accepts per hour on ambient audio) and keep the previous model for rollback.

## Code style

The long version is `docs/CODE_STYLE.md`. The short version: write like a careful person who wants the next reader to have an easy evening.

Everywhere:

- No em dashes and no emojis anywhere: code, comments, docs, logs, commit messages, UI copy, the board's screen and serial output. Use a comma, a period or a colon.
- Comments explain why, in one or two short plain lines, only where the code is not obvious. "The amp pops if the clock stops mid frame, so it never stops" is a good comment. No banners, no section dividers, no doc comments that repeat the name, no commented-out code. Dead code is deleted.
- Files under about 300 lines, functions short. Split by responsibility.
- Name things for what they are: `DeviceClient`, `OrbPainter`, `cloud_net_bind`. No `Impl`, `Manager`, `Helper`, `Utils`.
- A comment that records a measured number or a failure ("a 2 KB read held the first token until the last, so reads are 128 bytes") is the most valuable kind. Keep those, and add one when you change a number for a measured reason.

Dart:

- Feature first: `lib/features/<name>/{domain,data,presentation}`. `domain` is pure Dart (no Flutter import) with freezed models and repository interfaces; `data` implements them and wires providers; `presentation` reads providers and never imports `data` implementations or does HTTP.
- Riverpod with code generation for state, go_router for routes, freezed and json_serializable for models, dio for HTTP. Do not add another state, routing or model library. New dependencies need a reason written in `docs/ARCHITECTURE.md`.
- Platform differences live behind `PlatformInfo` (`lib/core/platform/`) or an interface chosen once in `data` (`NativeTools` has Windows and Linux classes). No `Platform.isWindows` in widgets.
- Files `snake_case.dart`, one public class per file named the same. Booleans read as questions (`isPaired`, `canHostHarness`). Callbacks `onSomething`.
- `final` by default, `const` constructors wherever possible, named parameters past two arguments, `switch` expressions over `if` chains, exhaustive on sealed types with no `default`.
- Errors: functions that can fail return `Result<T>` (`lib/core/result.dart`) with a typed `Failure`, or throw one typed exception documented on the interface. No bare `catch (e)` that swallows. No `.then` chains; `unawaited` only on purpose. Every `StreamSubscription` is cancelled.
- Widgets: `ConsumerWidget` by default, `ConsumerStatefulWidget` only for controllers and tickers, no `setState` in feature code. Watch narrowly with `select`; a widget that rebuilds on every WebSocket tick is a bug. Widgets under about 150 lines.
- Look and copy come from `brand/`: colors through the theme or the brand extension (never a hex literal in a widget), text through the named styles in `lib/core/theme`, spacing through `Space.*` tokens, visible controls from `lib/core/widgets`. Copy follows `brand/voice.md`: short, warm, direct, buttons are verbs, errors say what to do next.
- JSON on the wire is snake_case; `build.yaml` maps camelCase fields automatically.
- Tests mirror the source path. Parsers, mappers and repositories get unit tests against fixtures in `test/fixtures/`. `mocktail` for interfaces; mock the repository, not dio. Widget tests only where behavior is not obvious by eye.

C (firmware):

- ESP-IDF C for drivers and glue, C++17 only where a library needs it (TFLite Micro in `orion_wakeword`). No Arduino.
- One component per concern. Its public API is a small header in `include/`; other components reach it only through that header. Private helpers live in a `*_priv.h` or `*_internal.h` inside the component.
- Names: files `<prefix>_<thing>.c` inside a component (`cloud_tts.c`, `audio_mic.c`, `ui_star.c`), public functions `<component>_<verb>` (`orion_audio_play_begin`, `orion_cloud_reload`) or the component's short prefix where it already has one (`ui_set_text`, `sm_post`). `static` for everything not in the header. `snake_case`, `UPPER_CASE` constants and macros, `static const char *TAG = "<short>";` per file.
- Return `esp_err_t` and check it; `ESP_RETURN_ON_ERROR` and friends for early exits. A subsystem that fails at boot is logged and skipped so the screen can say what is wrong (`try_init` in `main.c`).
- Log with `ESP_LOGI/W/E` and a short tag. Never log a secret, an auth header or a request body that holds a key. Print a key's length (and at most its last four characters) when you need to show it exists.
- Pins only from `board/include/board_pins.h`. Colors, durations and easing on the screen only from the generated `orion_ui/ui_tokens.h`.

Python (tools): plain scripts runnable on their own, a header comment with the exact command lines, `argparse`, keys read from `.env` and never printed, UTF-8 stdout reconfigured when Arabic may be printed.

## Commits

- Conventional style, scope in parentheses, present tense, under about 70 characters: `feat(cloud): keep the tts socket open`, `fix(ui): room for the reset label`, `docs(harness): the approval tiers`, `chore: bump deps`, `release: firmware 1.1.0`.
- Scopes in use: `app`, `board`, `cloud`, `audio`, `ui`, `api`, `net`, `prov`, `wakeword`, `harness`, `providers`, `onboarding`, `camera`, `case`, `tools`, `docs`.
- One intent per commit. A body only when the why is not obvious, two or three plain lines, with the measured number if there is one.
- Never commit to `main` directly; work on a branch. Never force push, never rewrite `main`.
- Never commit `.env`, keys, tokens, NVS images, `firmware/build/`, `firmware/sdkconfig`, datasets, training checkpoints, or generated Dart files.

## Hard rules

### Secrets

- Keys live in exactly two places: the board's NVS (namespace `orion`, written by the app during setup or by `provision.py` on a dev board) and the OS keychain on the app side (`SecretStore`, backed by flutter_secure_storage). Never in `SettingsStore`/`AppSettings`, never in source, never compiled into firmware, never in a URL, a log line, a toast, a screenshot or a test fixture.
- Never print a key, including in a script's output or while debugging. Show its length and at most the last four characters. The API masks keys the same way (`"...4f2a"`).
- `.env` is for dev scripts only and is gitignored. If you find a key in a tracked file, remove it and say so in the commit message.
- The NVS image `provision.py` builds holds live keys: it is written outside the repo and deleted in a `finally`.
- The pairing token (`X-Orion-Token`) is a secret too. dsh gets its key through an env file with mode 0600, never on a command line.
- HTTPS always verifies certificates with the ESP-IDF bundle. Never turn verification off, not even to test.
- Test fixtures and docs carry no personal data: no real names, home paths, Wi-Fi names or addresses. Use `<you>` and placeholders.

### Generated files: do not edit by hand

| File | Regenerate with |
|---|---|
| `*.g.dart`, `*.freezed.dart` (gitignored) | `dart run build_runner build --delete-conflicting-outputs` |
| `lib/core/theme/tokens.dart` | `dart run tool/gen_tokens.dart` (from `brand/tokens.json`) |
| App icons and splash images | `python tool/gen_icons.py` (from `brand/assets/logo.png`) |
| `firmware/components/orion_ui/ui_tokens.h` | `python firmware/assets_src/ui/tools/build_tokens.py` |
| `firmware/assets_src/ui/fonts/*.c` | `python firmware/assets_src/ui/tools/build_fonts.py` (needs fontTools, brotli, node) |
| `firmware/assets_src/ui/images/*.c` | `python firmware/assets_src/ui/tools/build_images.py` |
| `firmware/sdkconfig`, `firmware/dependencies.lock` (gitignored) | the ESP-IDF build |
| Wake word `.tflite`/`.json` | the scripts in `wakeword/scripts/` |
| `case/stl/`, `case/orion_case.3mf`, `case/renders/` | the scripts in `case/cad/` and `case/blender/`, see `case/SPEC.md` |

To change one, change its source (`brand/tokens.json`, the SVG, the script) and rerun the generator.

### Firmware memory

Internal RAM is the scarce resource. With Wi-Fi, the screen, the wake word, the camera, two kept-alive TLS sessions and the LAN API running, about 27 to 40 KB of internal heap is left after a turn. Every rule here comes from a crash or a failed allocation.

- Big buffers go to PSRAM: `heap_caps_malloc(n, MALLOC_CAP_SPIRAM)`. `malloc` puts anything under 4 KB in internal RAM (`CONFIG_SPIRAM_MALLOC_ALWAYSINTERNAL=4096`), so many small allocations are internal too; avoid libraries that make lots of small nodes on a hot path (the cloud code does not use cJSON for that reason).
- DMA buffers stay internal: LCD draw buffers, I2S. Do not move them.
- Task stacks: a new task gets a PSRAM stack (`xTaskCreateWithCaps(..., MALLOC_CAP_SPIRAM)`) unless it touches flash. A task whose stack is in PSRAM must never run while the flash cache is off: no NVS reads or writes (`orion_config_*`), no SPIFFS reads, no partition writes. Read settings once into RAM at init; post writes to a task with an internal stack (the default event loop, as `orion_settings` does). The httpd task and the MJPEG task have PSRAM stacks, so their handlers never call `orion_config`.
- A task created with `...WithCaps` must not delete itself. Keep it permanent or park it with `vTaskSuspend(NULL)` and delete it from another task with `vTaskDeleteWithCaps` (`cloud_run_big` in `cloud_util.c`).
- The console task's stack is small (4 KB). A command that does TLS, JSON or anything deep runs on a helper task (`cloud_run_big` gives a 12 KB PSRAM stack) and waits for it.
- TLS buffers live in PSRAM (`MBEDTLS_EXTERNAL_MEM_ALLOC`), which is why hardware AES is off: it needed internal DMA bounce buffers per record and ran out mid turn. `esp_http_client` buffers are 4352 bytes on purpose, just over the internal threshold.
- Each kept-alive TLS connection costs about 4 KB of internal RAM. STT and TTS share one connection when they are on the same host (`cloud_net_bind`); think twice before adding a third.
- Bluetooth runs only in setup mode, which is a boot mode: the controller's memory is released with `esp_bt_mem_release` on every normal boot and cannot come back until reset. Never start BLE on a running system; set `prov_boot` and restart, as `orion_prov_request_async` does.
- Log `heap_int` and `psram_free` when you change anything that allocates, before and after (`heap` command, the per-boot `after <subsystem>` lines, the `turn_perf` line). A change that costs internal RAM needs a measured reason in the commit.
- Boot order in `main.c` matters (Wi-Fi first, since its receive buffers need DMA capable internal RAM that the screen, camera and wake word would otherwise take; the board owns I2C before the screen; audio clocks run before the amp is enabled). Read its comments before reordering.

### LVGL and the screen

- esp_lvgl_port owns the LVGL task and its lock. Any `lv_*` call from another task must hold `lvgl_port_lock(0)` and release it with `lvgl_port_unlock()`. Every public function in `orion_ui.h` takes the lock itself; code outside `orion_ui` calls only that header.
- Callbacks from the screen (`ui_on_tap`, menu buttons, `ui_on_wifi_setup`, the reset card) run on the LVGL task with the lock held. Never block there, never write NVS, never restart: hand the work to an `esp_timer` or the event loop (see `on_wifi_setup` and `factory_reset` in `main.c`).
- Never call `lv_refr_now` or take a snapshot from a foreign task while holding up the LVGL task; it deadlocks. `ui shot` runs on its own task and waits on a semaphore.
- Arabic depends on `CONFIG_LV_USE_BIDI` and `CONFIG_LV_USE_ARABIC_PERSIAN_CHARS`, and on fonts that include the Arabic presentation forms (U+FB50 to U+FEFC, lam-alef included). Without them Arabic renders as isolated letters in the wrong order. Check any new font's cmap for those ranges.
- All text goes through `ui_set_text`, which strips Fish voice cues (`[laugh]`) and keeps text inside the fixed 216x72 box. Nothing may draw outside the 240x240 screen; measure with `ui shot`.
- Brand on the glass: colors and timings from `ui_tokens.h`, the accent is light (hairlines, glow) and never a fill, borders are 1 px, no saturated status colors (error is neutral plus a shake, not red), motion eases and never bounces. SVGs are rasterized at build time; the chip has no RAM for LVGL's SVG decoder.
- `LV_COLOR_FORMAT_RGB565_SWAPPED` draws nothing in this LVGL build; swap bytes yourself.

### Protocol rules

`docs/DEVICE_PROTOCOL.md` is the contract between the app and the board, and `docs/HARNESS.md` the one between the board and a PC or phone brain. Change the doc first, then the firmware, the app and the mock (`tool/mock_device`) together, so neither side drifts. The rules that have bitten before:

- The board reads a brain's reply stream 128 bytes at a time, and `esp_http_client_read` only returns when all 128 are in or the stream ends. Anything shorter sits unread. So a keep-alive is an SSE comment padded to 128 bytes (`: working` plus spaces), sent at least every 3 s while a brain works, and one goes right after a spoken filler so it is read at once.
- The board's turn deadline is 30 s from the last bytes read, not 30 s in total.
- The board's chunker speaks a first piece only once it has 15 letters. A filler shorter than that waits for the answer ("One moment, I'm on it." is long enough).
- A brain's SSE answer starts with an empty `role` event: ESP-IDF's HTTP client keeps only the last body piece that arrives with the headers, which cost the first word before.
- Model control tokens (`<turn|>`, `<|im_end|>`) are dropped before the voice, by the brain and again on the board. Tool names never reach the voice (`withoutToolNames`).
- Every endpoint but `GET /api/info` and `POST /api/pair` needs `X-Orion-Token` (WebSocket and stream: `?token=`); a wrong or missing token is 401. LAN pairing shows a six digit code on the board's screen. The board keeps up to four paired tokens, so a phone and a PC both stay in.
- `POST /api/config` is a partial merge. For `api_key`: omitted keeps the stored key, `""` clears it, anything else replaces it. GET returns keys masked to the last four. Values with a quote, backslash or control character are refused.
- While a turn runs the board answers config tests and requests with 409 `busy`; the app retries.
- `/stream` serves two viewers; a third gets 409. The app closes the stream when the camera screen is not visible.
- Bluetooth: `orion-pair` is the first custom endpoint (characteristic 0xFF54) and `orion-config` the second (0xFF55), by creation order. `orion-config` bodies over about 400 bytes go in parts of 150 characters, since a GATT value tops out at 512 bytes.
- The ESP-IDF 5.5 WebSocket token check lives in `ws_post_handshake_cb` (`CONFIG_HTTPD_WS_POST_HANDSHAKE_CB_SUPPORT`), not in the URI handler.
- Fish Audio: always send `format: "pcm"` (the default is mp3) and `latency: "balanced"` (`normal` is about four times slower to first audio). Never send a `prosody` block: it costs about 9 dB of loudness. Fish WAV responses carry a placeholder RIFF header; build your own. Never send a language hint to speech to text: it made Whisper translate English into Arabic.
- Board HTTP: one kept-alive client per host; finish a response by reading it to the end (never `esp_http_client_flush_response`: it counts the skipped body without keeping it, and the next read crashed the board); `esp_http_client_close` closes the socket; `TCP_NODELAY` on cloud sockets.

### PC and phone brain safety

- Every tool has a tier in `ToolCatalog`: `safe` runs at once, `confirm` asks the first time, `always` asks every time (`agent_task`). Anything that can run a command, type, press keys or change files is `confirm` or stricter.
- The board's `pc.approval` (`ask` or `auto`) is the single source of truth for approvals; the desktop keeps a copy for when the board is away.
- Every call is logged to `~/Orion/logs/tools.jsonl` with who approved it. dsh runs only in `~/Orion/agent` with its own `DSH_HOME`, never the user's home.
- Spoken results are one or two sentences in the user's language: never paths, commands, code, URLs, JSON or long lists.
- The tool server takes port 7331 and the pairing token only.

## Testing on a real board, safely

There is usually one board and one serial port, shared by everything on the machine.

- Only one process may use the port at a time. On Windows every flash goes through `tools/flash.ps1` and every read through `tools/serial_capture.py`, `tools/board_session.py` or `tools/cloud/console_session.py`; all of them take the lock at `%USERPROFILE%\.orion\flash.lock` (stale after 10 minutes or when its holder process is gone). Never open the port any other way, and never run `idf.py monitor` from an automated agent: it never returns.
- A flash and the capture that tests it are separate lock holds, so something else can flash in between. For flash-then-test use `board_session.py`, and check the `App version` line in every capture before trusting its numbers.
- During development write the app partition only (`-Bin firmware\build\orion.bin -Address 0x10000`). A full flash rewrites the assets and model partitions, which can bring back an older system prompt or wake word from your branch. NVS is only rewritten by `provision.py`, `-Erase` or the release full image.
- Sound: people may be nearby. Send `volume 0` (or `vol 0` for this boot only) before a test that does not need sound; a typed turn at volume 0 still runs every stage in real time. Tell whoever is in the room before a test plays audio through the PC speakers or the board.
- Typed turns (`ask`, `talk`) test the whole loop without a microphone. `turn_perf` lines carry every stage's time; `heap` shows memory.
- Opening the port can reset the board; `serial_capture.py --no-reset` sets DTR and RTS low first. Output early in boot can be lost on USB re-enumeration; `main.c` repeats its report for that reason.
- Real voice tests: `tools/replay_clips.ps1 -Path wakeword\test_clips` plays clips through the PC speakers and counts detections; `-Negative` expects none. Synthetic clips overstate over-the-air recall; the real test is a person in the room.
- A board that looks dead may only have the audio enable (GPIO 18, active low, gates both mic and amp) or the camera power-down (GPIO 4) in the wrong state. Check `board_pins.h` before blaming hardware.
- Wi-Fi is 2.4 GHz only. A 5 GHz only network fails like a wrong password; `orion_net` scans and says which after three failed attempts.

## Key design decisions

Why things are the way they are. Change one only with a measurement that beats the reason.

- **The board is the product.** It runs wake word, speech to text, the model and the voice itself. The app configures, observes and triggers; it never proxies audio. A PC or phone only adds a brain for the words.
- **Brains in order.** A turn goes to the PC brain when PC control is on and its health check passed, then to a linked phone, then to the board's own model, moving on the moment one fails before its first word. The PC brain answers on a fast model and moves a turn to a thinking model the moment it acts (default Gemma 4 31B turbo to answer, GLM-5.3-Flash to act, both on DeepInfra): a fast model reported tasks done that it never checked.
- **Defaults.** Fish Audio for both voice stages: TTS on the free `s2.1-pro-free` model with Orion Voice (`9a68c1d739134940a4297c996c5ca6a1`), speech to text on `transcribe-1` (paid, about $0.36 per audio hour, streamed while the user talks). Every stage is switchable to any OpenAI-compatible endpoint, per config v2.
- **Streaming everywhere.** The model streams over SSE into a tag-safe chunker, each piece becomes a Fish REST request on a kept-alive socket, and audio plays from a PSRAM ring as soon as it holds anything. Fish's live WebSocket was measured and not used: slower to first audio than warm REST, and another TLS session the RAM cannot afford.
- **Kept-alive TLS.** A handshake on the chip costs 1.5 to 3 s. One socket per host lives for the whole run, is prewarmed at the wake word, and refreshed with a HEAD every 40 s because DeepInfra drops idle sockets after 60 to 90 s.
- **Wi-Fi tuned for audio.** All-channel scan to the strongest access point, 20 MHz, power save off, 64 dynamic RX buffers in PSRAM with a 32 KB TCP window: a 64 KB window against too few buffers caused 11 to 18 s of silence mid answer.
- **Speaker.** The amp averages both I2S slots, so mono is written to both (a 6 dB gain). The clock never stops and every stream fades in and out over 10 ms, so there is no pop. A DSP chain (high pass, presence, make-up gain, a -1 dBFS look-ahead limiter and a sustained power guard) makes it loud without clipping. One mic, no echo cancellation: the mic is muted while the speaker plays.
- **Mic.** A one pole DC blocker runs before anything reads the samples; without it every threshold measured the PDM offset.
- **Wake word.** A custom microWakeWord model for "Orion" in Arabic and English spellings, trained on Fish and Piper voices with standard and confusable negatives, packed into its own partition and memory mapped. A firmware energy gate rejects detections in near silence, because the model woke on the mic's own hum.
- **Setup mode is a boot mode.** BLE memory can be released only once per boot, so setup (no Wi-Fi, 30 s without the saved network, the menu, or `prov start`) reboots into a mode where nothing else runs. A wrong password never reaches flash.
- **Keys in NVS and the keychain only.** Firmware images are shareable and carry no key, password or address. A full release image blanks NVS; the per-partition update keeps it.
- **Emotion tags.** On Fish the model writes free-form voice cues (`[laugh]`, `[sigh]`, `[pause]`, `[laughing nervously]`) wherever the sound or feeling happens, as Fish's S2 docs describe. The rules sit in the prompt's `<fish>` section, sent only when TTS is Fish. Fish performs a cue and never speaks it; the screen, the app and any non-Fish TTS get the text without them. The Arabic spellings of Orion's name are sent to TTS as the Latin "Orion", which the voice says the English way.
- **Assets split.** `firmware/assets/` is exactly what the chip opens (earcons, the system prompt); build inputs live in `firmware/assets_src/`, so a font source never eats the 2 MB partition.
- **Quad PSRAM.** This board's PSRAM is an external quad chip, so GPIO 33 to 37 are free for the LCD and I2C. Never switch the config to octal.
- **One app, many platforms.** One Flutter codebase; the shell picks bottom nav or rail from `PlatformInfo`, the router adds the harness only where `canHostHarness`. Bluetooth setup runs on phones. The desktop asks Windows once (UAC) to allow port 7331 from the local subnet.
- **Approval is one setting.** Off, Ask me first, Act on your own, stored on the board and settable from the PC, the phone, or by voice.
