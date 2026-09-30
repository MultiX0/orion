# Code style

Write it like a careful person who wants the next reader to have an easy evening. These rules hold for the Dart app, the C firmware, the Python tools and the docs.

## Everywhere

- **Plain English**, in code, comments, docs, commit messages and UI copy. No "leverages", "utilizes", "robust", "seamless". Say "uses".
- **No em dashes and no emojis**, anywhere: code, comments, docs, commits, UI strings, logs. Use a comma, a full stop or a colon.
- **Files under 300 lines**, widgets under 150. Split by responsibility, not by line count. A few files have grown past it (`pc_brain.dart`, `desktop_control.dart`, `orion_api.c`, `cloud_reply.c`) and are the first to split when they are next touched.
- **Dead code is deleted**, not commented out.
- **Name things for what they are**: `DeviceClient`, `OrbPainter`, `cloud_net.c`. No `Impl`, `Manager`, `Helper`, `Utils`.
- **Secrets never touch git or a log.** Keys live in `.env` (gitignored), the OS keychain, or the board's NVS. Log a key by its length, never its value. A key never goes in a URL, a command-line argument or a toast. If you find one in a file, remove it and say so in the commit message.

## Comments

- Explain **why**, not what. If the code says what, no comment.
- One line where possible, two if the reason needs it. Never a paragraph, except at the top of a file where the design is not obvious from the code.
- A measured reason is the best comment: "Asked for 2 KB, a short answer's first token sat in the buffer until its last one arrived." That is what stops the next person from undoing it.
- No banners, no section dividers, no doc comments that restate the name. `/// Returns the device state.` on `getDeviceState()` gets deleted.
- Doc comments on public interfaces only when the contract is not obvious.

Good:

```dart
// The board drops the first request after wake, so retry once.
final res = await _retryOnce(() => _dio.post('/api/talk', data: body));
```

```c
// A task whose stack is in PSRAM must never run with the flash cache off, so
// the settings are read once here, on main's internal stack.
```

Bad:

```dart
/// This method sends a talk request to the device and handles retries
/// in a robust manner to ensure reliability across network conditions.
```

## Dart

- `final` by default. `late` only for controllers set up in `initState`.
- Named parameters for anything with more than two arguments.
- `switch` expressions over `if` chains for enums, exhaustive, no `default` on sealed types.
- `freezed` for every model; never hand-write `copyWith` or `==`. JSON through `json_serializable`, field names in snake_case to match the protocol.
- Errors: the sealed `Failure` family in `lib/core/result.dart`. Functions that can fail return `Result<T>` or throw one typed exception documented on the interface. No bare `catch (e)` that swallows, no stringly typed errors.
- Async: `await`, not `.then` chains. `unawaited` on purpose, never by accident. Every `StreamSubscription` is cancelled in `dispose` or lives in an auto-dispose provider.
- One public class per file, named like the file.

### Layers

- `domain` is pure Dart: models and repository interfaces. Importing Flutter there is a mistake.
- `data` holds the implementations and the providers that wire them.
- `presentation` never imports from `data` and never touches HTTP or JSON.
- Platform differences live behind `PlatformInfo` and interfaces in `data` (`NativeTools` has Windows and Linux implementations). No `Platform.isWindows` in widgets.
- No global mutable state, no singletons outside Riverpod.

### Widgets

- `const` constructors wherever possible.
- `ConsumerWidget` by default; `ConsumerStatefulWidget` only for controllers and tickers. No `setState` in feature code.
- Read narrowly: `ref.watch(deviceStateProvider.select((s) => s.mode))`. A widget that rebuilds on every WebSocket tick is a bug.
- No business logic in `build`.
- Layout with `Column`, `Row`, `Padding`, `SizedBox` and spacing tokens. No `Container` for padding alone. Text through the theme's named styles, colours through the theme or the brand extension; never a hex literal or an inline `TextStyle(fontSize: 14)` in a widget.
- Images from the board through `Image.memory` with `gaplessPlayback`, lists through `ListView.builder`, animation through `CustomPainter` or `AnimatedBuilder` with a ticker.

### Lints

`analysis_options.yaml` uses `flutter_lints` plus `riverpod_lint` through `custom_lint`, with `prefer_const_constructors`, `prefer_const_declarations`, `avoid_print`, `always_declare_return_types`, `prefer_single_quotes`, `unawaited_futures`, `require_trailing_commas` and `avoid_dynamic_calls`. `flutter analyze` is clean and `dart format .` changes nothing at every commit.

## C firmware

- C for everything; C++17 only where TensorFlow Lite Micro needs it (`ww_model.cpp`).
- **Pins come only from `board_pins.h`.** Nobody hardcodes a GPIO anywhere else.
- **A component talks to another only through its public header** in `include/`. Private headers (`*_priv.h`) stay inside the component.
- **Big buffers in PSRAM** (`heap_caps_malloc(..., MALLOC_CAP_SPIRAM)`). Internal RAM is for what must be there: DMA, Wi-Fi, task control blocks, the draw buffers, the wake word arena. Every new internal allocation needs a reason.
- **A task with a PSRAM stack never touches flash**: no NVS, no SPIFFS, no `orion_config`. Read settings once on an internal stack; post writes to the default event loop.
- **One owner per piece of state.** Everything posts events to the state machine; every `ui_` call comes from the state machine task.
- **Fail soft at boot.** A subsystem that fails logs why and the boot goes on, so the screen can say what is wrong.
- **Measure before tuning.** Every threshold, timeout and gain in the firmware has the measurement that set it in a comment next to it. Keep it that way.
- Keys are logged by length. `orion_config_report` is the model.
- Each component exposes `<name>_register_cmds()` for its console commands, so the board can be driven over serial with nobody at the keyboard.

## Python tools

- Standard library where possible; `pyserial` for the serial tools.
- Read keys from `.env` through `tools/cloud/cloud_api.py`, never print them.
- On Windows, reconfigure stdout to UTF-8 (`sys.stdout.reconfigure(encoding="utf-8")`) before printing Arabic; the default code page fails on it.
- Anything that touches the board takes the shared lock (`tools/serial_capture.py`'s `Lock`), because there is one port.
- Shell scripts that run in WSL are LF only (`wakeword/.gitattributes`).

## Tests

- Unit tests for parsers, mappers, protocol logic and repositories against recorded fixtures in `test/fixtures/`. Anything with parsing or protocol logic has one.
- `mocktail` for interfaces; mock the repository a screen uses, not dio.
- Widget tests where behaviour is not obvious from a look: the orb's state mapping, router redirects, the approval queue, the model picker.
- A test file mirrors its subject's path.

## Commits

- A conventional prefix with a scope, present tense, under 70 characters: `feat(camera): mjpeg view`, `fix(ws): reconnect after sleep`, `docs: ...`, `chore: ...`.
- A body only when the why is not obvious: two or three plain lines, with the measurement if there is one.
- One intent per commit.
- Never commit generated files (`*.g.dart`, `*.freezed.dart`, `firmware/sdkconfig`, `firmware/dependencies.lock`, build output, `logs/`).
- Never force push, never rewrite `main`. Work on a branch.
