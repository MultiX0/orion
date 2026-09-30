# Contributing to Orion

Thanks for looking. Orion is a voice assistant you build yourself: a LilyGO T-CameraPlus-S3 board running its own ESP-IDF firmware, a custom "Orion" wake word, a Flutter companion app, and a 3D printed case. It is maintained by one person, MultiX0 (https://github.com/MultiX0), so small, focused changes get reviewed fastest.

Before you start, read the license section below. Orion is source-available under the PolyForm Noncommercial License 1.0.0, not an OSI open source license, and that applies to what you contribute too.

## Where things are

```
firmware/        ESP-IDF 5.5.5 project for the board (main/, components/, assets/)
lib/             the Flutter app: app/, core/, features/
test/            app tests, mirroring lib/ paths, fixtures in test/fixtures/
tool/            Dart tools: the mock board, token generator, harness probes
tools/           Python and PowerShell tools for the board: flashing, serial console, cloud probes
wakeword/        training scripts and the shipped wake word model
harness/         DeepSeek Harness config used by the desktop app
case/            the printed case, its sources and renders
brand/           colors, fonts, spacing, motion and copy tone
docs/            how everything works, and the journals
```

The docs worth reading first:

- `docs/ARCHITECTURE.md`: app layers, state, routing, dependencies.
- `docs/DEVICE_PROTOCOL.md`: the contract between the app and the board. Both sides implement it, and so does the mock.
- `docs/FIRMWARE.md`: flashing, releases, reset and power.
- `docs/HARNESS.md`: PC control on the desktop app.
- `docs/PROVIDERS.md`: language model and speech provider settings.
- `docs/UI.md` and `brand/`: screens, motion, and the look.
- `docs/CODE_STYLE.md`: how code is written here. Please read this one.
- The code comments and the area docs record what was measured and why. Read them before you "fix" something that looks odd; there is often a measured reason.

## Setting up

### The app

- Flutter stable. CI uses 3.44.1 (Dart 3.12). `flutter doctor` tells you what is missing for your platform.
- For Windows desktop: Visual Studio with the "Desktop development with C++" workload.
- For Android: Android Studio or the command line SDK. For iOS: a Mac with Xcode.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Generated files (`*.g.dart`, `*.freezed.dart`) are not committed. Run build_runner again after you change a freezed model, a JSON model or a Riverpod provider.

No board? Run the mock in a second terminal. It implements the whole device protocol:

```
dart run tool/mock_device/main.dart
flutter run -d windows
```

On first launch, enter `localhost:8080` as the board address. The mock's pairing code is always `123456`.

### The firmware

- ESP-IDF v5.5.5 exactly. Other 5.x versions may build, but they are not what the release was built and tested with.
- A LilyGO T-CameraPlus-S3 (V1.2) if you want to run what you build, and a USB-C data cable.

From `firmware/`, with the ESP-IDF environment loaded:

```
idf.py build
idf.py -p <port> flash monitor
```

On Windows, `tools/idf.ps1` loads the environment and runs `idf.py` for you, and `tools/flash.ps1` flashes with a lock so two scripts never fight over the port.

Things that trip people up:

- The build reads `sdkconfig.defaults` only. `firmware/sdkconfig` is generated and gitignored. After you change `sdkconfig.defaults`, delete `firmware/sdkconfig` or the old values stay.
- `idf.py build` also packs `firmware/assets/` into the assets partition and the wake word model into the model partition. A plain `idf.py flash` writes both.
- To build with another wake word model: `idf.py -D ORION_WAKE_MODEL=<path without extension> build`, pointing at a `.tflite` and its `.json` manifest.
- Flashing the full image erases the board's settings (Wi-Fi, keys, paired apps). See `docs/FIRMWARE.md` for how to update the app only.

### Python tools

- Python 3.11 or newer for the scripts in `tools/`. They use `requests`, `numpy`, `websockets`, `pyserial` and `esptool`; install what the script you run imports.
- The wake word training in `wakeword/` has its own pinned `requirements.txt` and was run on Python 3.11 in WSL2 Ubuntu. Read `wakeword/README.md` before starting; training takes hours and several GB of disk.
- Scripts that call Fish Audio or a model provider read keys from your environment or a local `.env`, which is gitignored. Never commit a key.

## Checking your change

### App

Every pull request must pass these, and CI runs the same:

```
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
```

`flutter analyze` must report no issues at all, warnings included.

Also run the app against the mock, and against a real board if your change touches the protocol. Say in the pull request which platforms you ran it on.

Add unit tests for parsers, mappers and repositories, using recorded fixtures in `test/fixtures/`. Fixtures must not contain personal data: no real names, addresses, keys or tokens.

### Firmware

CI builds the firmware in the `espressif/idf:v5.5.5` container. A clean build with zero new warnings is the minimum.

The firmware is tested on the board: flash it, watch the serial console, and run the path you changed. The console has commands for this, such as `ask <text>` to run a full turn without the microphone, `say <text>` to hear a line without the model, `prov start` to enter setup mode, and `cloud_selftest` to run the sentence chunker cases (the same cases as `tools/cloud/chunker_test.py`, which runs on a PC). In the pull request, say what you ran on the board and what you saw: latency, free internal RAM after a few turns, anything the log printed. If you do not have a board, say so; a build-only change is still welcome, it just needs testing by someone who has one.

If you change the device protocol, change `docs/DEVICE_PROTOCOL.md`, the firmware and the mock device in the same pull request, so the three never disagree.

## Code style

The full rules are in `docs/CODE_STYLE.md`. The short version:

- Plain English in code, comments, docs, commits and UI strings. No em dashes, no emojis.
- Comments explain why, in one line where possible. No banner comments, no doc comments that repeat the name.
- Dart: Riverpod for state, go_router for navigation, freezed for models, dio for HTTP. No other state or routing library. Files under 300 lines, widgets under 150. `const` wherever possible. Colors and text styles come from the theme, never literals.
- C: 4 spaces, the brace on its own line for functions, `static` for anything file-local, `ESP_LOG*` with a short `TAG`. Match the component you are in.
- Do not add a dependency without saying why in the pull request.
- `.editorconfig` sets indentation and line endings for your editor.

## Commits

Conventional style, scope in parentheses, present tense, under 70 characters:

```
feat(camera): save a snapshot from the live view
fix(audio): no click when the stream stalls
docs(firmware): how to update without losing settings
```

One intent per commit. Add a body only when the reason is not obvious, and keep it to two or three plain lines. Common scopes: `app`, `fw`, `audio`, `net`, `ui`, `api`, `prov`, `wakeword`, `harness`, `camera`, `case`, `docs`.

## Proposing a change

1. For anything bigger than a small fix, open an issue or a Discussion first and say what you want to change and why. It saves you writing code that does not fit.
2. Fork the repository and branch from `main`.
3. Make the change, with tests where they make sense.
4. Open a pull request against `main` and fill in the template.

### What makes a good pull request

- It does one thing. A bug fix and a refactor are two pull requests.
- It says what changed and why, in a few plain sentences.
- It says how it was tested: which platforms, the mock or a real board, and what you saw.
- It includes screenshots or a short video for UI changes, and numbers for performance or audio changes.
- It updates the docs it makes wrong.
- It contains no keys, tokens, Wi-Fi passwords, IP addresses of your own network, or recordings of people who did not agree to share them.
- CI is green.

The maintainer may ask for changes, or say no to something that does not fit the project. That is about the change, not about you.

## License of contributions

Orion is licensed under the PolyForm Noncommercial License 1.0.0 (see `LICENSE`). Anyone may use, change and share it for personal and non-commercial purposes. Commercial use needs the author's permission.

By opening a pull request, you agree that your contribution is licensed under the same PolyForm Noncommercial License 1.0.0 and may be distributed with Orion under it. In practice:

- Only contribute work you wrote yourself, or have the right to contribute.
- Do not paste code from projects whose licenses do not allow this, such as GPL code. Permissive third-party code (MIT, BSD, Apache 2.0) is fine when its license and notice come with it; say so in the pull request.
- Contributing does not give you or anyone else a commercial license to Orion.
- Third-party parts (ESP-IDF, LVGL, TensorFlow Lite Micro, the Flutter packages, the fonts, the `okay_nabu` model) keep their own licenses.

If you are unsure whether something can go in, ask in the issue before you write it.

## Getting help

See `SUPPORT.md`. For security problems, do not open an issue; see `SECURITY.md`.

Everyone taking part is expected to follow the `CODE_OF_CONDUCT.md`.
