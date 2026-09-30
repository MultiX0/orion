# The app

One Flutter codebase in `lib/` for the Orion companion app. It finds and sets up a board, shows what it is doing, remotes it, streams its camera, chooses its models and voice, and, on a Windows PC or a phone, acts as its extended brain.

| Platform | Status |
|---|---|
| Android | Runs against real boards: Bluetooth setup, pairing with a code, dashboard, camera, the phone brain with a foreground service |
| Windows | Runs against real boards: Bluetooth setup through WinRT, the whole dashboard, and the harness (PC control and the PC brain) |
| iOS | Same code; Bluetooth and local network usage strings are configured. Not verified on a device. The phone brain answers only while the app is open. |
| Linux | The target exists and the harness has Linux native tools with fixture tests. Not built or run. |

The screens and motion are described in [UI.md](UI.md), the harness in [HARNESS.md](HARNESS.md), the model and voice choices in [PROVIDERS.md](PROVIDERS.md), and the wire format in [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md).

## Structure

Feature first, three thin layers, Riverpod everywhere.

```
lib/
  main.dart            moves old Windows app data, sets up the desktop window, runs the app
  app/                 MaterialApp.router, the route table, the shell (bottom bar on phones, side rail on desktop)
  core/
    platform/          PlatformInfo: the one place that knows the OS
    theme/             tokens generated from brand/tokens.json, ThemeData, named text styles
    widgets/           the design system: buttons, cards, fields, KeyField, chips, toast, select field, mark
    motion/            durations, curves, the orb painter and its simulation, route transitions
    network/           DeviceApi (dio), the reconnecting WebSocket, MJPEG parser, discovery, local address
    storage/           SecretStore (keychain), SettingsStore (one JSON), the Windows data folder move
    audio/             AudioPlayer over audioplayers, for voice previews
    result.dart        Result<T> and typed failures
  features/<feature>/
    domain/            freezed models and repository interfaces, pure Dart
    data/              implementations, API clients, parsers, the providers that wire them
    presentation/      screens and widgets; no HTTP, no JSON
```

| Feature | What it holds |
|---|---|
| `onboarding` | discovery, pairing with a code, Bluetooth setup (`data/ble/`), the onboarding journey |
| `device` | `DeviceClient` (REST and `/ws`), the board's state, config and events |
| `home` | the orb and the last exchange |
| `conversation` | turn history, live turns from `/ws` |
| `camera` | the MJPEG stream, snapshots, "Ask about this" |
| `talk` | hold to talk, typed questions |
| `providers` | model, speech to text and text to speech choices, keys, model pickers, stage tests, Fish Audio |
| `settings` | board settings, Wi-Fi change, unpair, about |
| `harness` | the tool server, PC brain, phone brain, native tools, desktop control, approvals, dsh |

A screen never imports from `data`, and a repository never imports Flutter. `lib/core/project.dart` holds the author, URL and license, shown in Settings, About.

## State

- Riverpod 3 with code generation (`riverpod_annotation`, `riverpod_generator`). A `Notifier` per feature for mutable state; `StreamProvider`s for the board's events and camera frames; derived values as their own providers so widgets can `select` narrowly (the orb rebuilds on a mode change, not on every signal strength tick).
- `keepAlive` for the device connection, settings, the harness and the router; everything else auto-disposes.
- Models are `freezed` with `json_serializable`, field names in snake_case to match the protocol.
- `useFakesProvider` switches the whole app onto in-memory fakes (board, storage, providers, harness). It is off in the app and on in widget tests.

## Routes

`lib/app/router.dart`, go_router. With no board paired every route redirects to `/onboarding`.

```
/onboarding                     the journey
/onboarding/pair/:deviceId      pairing with a board found on the LAN
/onboarding/bluetooth           Bluetooth setup
/                               home
/conversation
/camera
/talk
/providers
/providers/:id                  one language model provider
/settings
/settings/wifi                  change Wi-Fi
/harness                        desktop only
/harness/confirm/:id            desktop only, an approval as a modal
```

## Talking to the board

- **REST.** `DeviceApi` over dio adds `X-Orion-Token` to every request and maps errors to typed failures. Paths are in `lib/core/network/api_paths.dart`, shared with the mock board so they cannot drift.
- **WebSocket.** `ReconnectingSocket` connects to `/ws?token=...&client=pc|phone[&brain=host:port]`, pings every 5 s (the board drops a link after 15 s of silence and its dot goes out), drops a socket that stays silent for 25 s, notices a laptop waking from sleep by the wall clock jumping, and reconnects after 1, 2, 4, 8, then every 15 s.
- **Discovery.** `LanDiscovery` merges the UDP beacon on 7332, mDNS, a sweep of every /24 on up to three local interfaces (default route first, virtual adapters last) and the names `orion.local` and `orion-<last4>.local`, confirms every hit with `GET /api/info` (400 ms, 64 at once) and shows each as it arrives with its source. It also tries `localhost:8080`, which is how it finds the mock board.
- **Camera.** `HttpCameraSource` reads `/stream` with the MJPEG parser (any boundary, with or without `Content-Length`, CRLF or LF), takes each frame's size from the JPEG SOF marker, retries a 409 every 2 s while the screen is open, and reconnects with backoff. A snapshot is saved to `~/Orion/snapshots` on desktop and the app's documents folder (`snapshots/`) on a phone.
- **Local address.** When the PC tells the board where its brain is, `LocalAddress` picks the adapter on the board's own subnet (from the local end of a TCP connection to the board), falling back to the default route (`route print` on Windows, `ip route` on Linux) and never a virtual adapter unless it is the only one.

## Storage

- **Keychain** (`flutter_secure_storage`): `pairing_token`, `fish_api_key`, and `provider_key_<id>` per language model provider (the speech presets share these by account). Nothing else holds a key.
- **Settings** (`shared_preferences`): one `AppSettings` JSON: the paired board, reduced motion, PC control on or off and its approval mode, the providers and their chosen models, the Fish settings, the voice stages.
- **Windows data folder.** The app's data folder is named after the company and product in the exe's version info, `MultiX0` and `Orion`. Builds before that used `%APPDATA%\dev.orion\orion`; on first start the app copies `shared_preferences.json` and `flutter_secure_storage.dat` across when the new folder has none, so an update keeps its pairing, keys and PC control.

## Setting up a board

The onboarding journey is Welcome, Find, Pair, Brain and voice, Hands (desktop only), Ready, drawn as a line of stars with the current one lit. Every step after Pair has "Later".

**Bluetooth setup** (`lib/features/onboarding/data/ble/`) uses `esp_ble_prov_dart` 0.5.0 on `universal_ble` 1.2.0 (pinned: the first requires 1.x of the second). It was chosen because it is the only package that does Security1 with a proof of possession, `prov-scan`, `prov-config` with status and named custom endpoints over one session. The flow:

1. A live scan for `Orion-<last4>` with signal strength (through `universal_ble` directly).
2. The six digit code; a failed Security1 handshake while the link is up means a wrong code.
3. `orion-pair` at once, reusing the token already in the keychain or generating one. The token is stored only after the board accepts it.
4. The "Brain and voice" step over `orion-config`, in parts when the JSON is over 400 bytes. Testing is hidden here, since the board has no network yet.
5. The board's own Wi-Fi scan, strongest first; a password; the join with live status ("Code accepted", "Joining ...", "Found on your network"). "Disconnected" between driver retries reads as still joining; no verdict in 45 s is a timeout. A wrong password offers "Try another password" in the same session.
6. The hand-over to the LAN: find the board, confirm it with `/api/info`, and show "Brain and voice" again with Test working.

`orion-pair` is the first custom endpoint (0xFF54) and `orion-config` the second (0xFF55); if the firmware ever adds another endpoint first, change `BleContract` in `ble_contract.dart`.

Permissions: Android asks for `BLUETOOTH_SCAN` (never for location) and `BLUETOOTH_CONNECT` on 12 and newer, and fine location on 11 and older, which cannot scan without it. iOS needs `NSBluetoothAlwaysUsageDescription` and `NSLocalNetworkUsageDescription`. Windows needs Bluetooth switched on. The Android emulator has no Bluetooth.

**Pairing with a code** for a board already on the network: pick it in Find, the board shows six digits, type them (`POST /api/pair`).

**Changing Wi-Fi**: Settings, Change Wi-Fi. Online, "Move Orion" sends the new network over the LAN with the token. Out of reach, it explains setup mode and "Set up over Bluetooth" runs the flow above, keeping the token.

**Unpairing** works with the board out of reach, and is offered from the offline Settings view.

## The extended brain

On Windows, the harness starts with the app when PC control was on. On Android and iOS, `phoneBrainProvider` starts the phone brain once a board is paired, tells the board its address in the `/ws` link, and on Android starts `BrainService` (`android/app/src/main/kotlin/dev/orion/orion/BrainService.kt`), a foreground service of type `connectedDevice`, so the brain keeps answering while another app is in front. Details in [HARNESS.md](HARNESS.md).

## Building

Prerequisites: Flutter stable with Dart 3.12 or newer (`flutter doctor` lists what each platform still needs), and for Windows the Visual Studio C++ workload.

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

Generated files (`*.g.dart`, `*.freezed.dart`) are gitignored and must be regenerated after every checkout and every model change.

| Target | Run | Release build |
|---|---|---|
| Windows | `flutter run -d windows` | `flutter build windows --release`; the app is `build\windows\x64\runner\Release\orion.exe` with its DLLs and `data\` folder |
| Android | `flutter run -d <device id>` | `flutter build apk --release`, then `adb install -r build/app/outputs/flutter-apk/app-release.apk` |
| iOS | `flutter run -d <device id>` | open `ios/Runner.xcworkspace` in Xcode, set a signing team for `dev.orion.orion`, archive |
| Linux | `flutter run -d linux` | `flutter build linux --release` (not verified) |

Notes:

- **Windows path length.** A Windows build from a path longer than about 200 characters fails with MSB3491 in a plugin's tracking log. Build from a short path (a `subst` drive letter works; a junction does not).
- **Windows Firewall** asks on first launch for the discovery sockets (mDNS and the UDP beacon on 7332). If that prompt is dismissed, discovery still works through the sweep and names. PC control asks separately for its own rule.
- **Android release** needs `INTERNET` in the main manifest (it is there); without it a release APK cannot reach the board at all, while debug builds can.
- The app's version in `pubspec.yaml` is independent of the firmware's.

## Working without a board

```
dart run tool/mock_device/main.dart                # a fake board on :8080
flutter run -d windows                             # finds it as localhost:8080
flutter run -d windows --dart-define=ORION_FAKE_BLE=true   # a scripted Bluetooth board, code 123456
```

The mock serves the whole protocol, beacons, streams frames from `tool/mock_device/frames/` and walks scripted turns. See [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md#the-mock-board) for its switches and scripted keys. The Android emulator reaches it at `10.0.2.2:8080` (the beacon and the sweep do not cross the emulator's NAT). Stop the mock before testing a real board, or it shows up in discovery too.

## Dependencies

From `pubspec.yaml`, with the reason for the less obvious ones:

| Package | For |
|---|---|
| `flutter_riverpod`, `riverpod_annotation` | state |
| `go_router` | routes |
| `freezed_annotation`, `json_annotation` | models |
| `dio`, `web_socket_channel` | REST and `/ws` |
| `multicast_dns` | mDNS discovery |
| `flutter_secure_storage`, `shared_preferences`, `path_provider` | keychain, settings, folders |
| `shelf`, `shelf_router`, `shelf_web_socket` | the tool server (and the mock board) |
| `process_run`, `win32`, `ffi` | desktop tools on Windows |
| `window_manager`, `screen_retriever`, `tray_manager` | the desktop window |
| `audioplayers` | voice previews on every platform |
| `esp_ble_prov_dart` 0.5.0, `universal_ble` 1.2.0 | Bluetooth setup |
| `url_launcher` | the Fish key link, and `open_link` on the phone |
| `flutter_animate` | one-off entrance motion (the orb is hand painted) |
| `package_info_plus`, `device_info_plus`, `uuid`, `intl` | versions, device names, tokens, date formats |

Dev: `build_runner`, `riverpod_generator`, `freezed`, `json_serializable`, `custom_lint`, `riverpod_lint`, `flutter_lints`, `mocktail`.

## Generators

- `dart run tool/gen_tokens.dart` rebuilds `lib/core/theme/tokens.dart` from `brand/tokens.json`. Do not edit `tokens.dart` by hand.
- `python tool/gen_icons.py` rebuilds every Android, iOS and Windows icon, the splash and the SVG copies from `brand/assets/logo.png`.
