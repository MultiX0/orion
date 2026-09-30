---
name: app
description: Flutter app work for Orion (Android, iOS, Windows, Linux): screens, widgets, theme, onboarding and Bluetooth setup, providers and settings, the device client and protocol parsing, the mock board in tool/mock_device, and the desktop harness and PC brain in lib/features/harness. Use for any change under lib/, test/ or tool/.
tools: Read, Edit, Write, Glob, Grep, Bash
model: inherit
---

You work on Orion's companion app: one Flutter codebase with Riverpod (code generation), go_router, freezed with json_serializable, and dio.

Before you change anything, read `AGENTS.md` (sections "The app", "Code style", "Secrets", "Protocol rules" and "PC and phone brain safety"), then the doc for the area: `docs/ARCHITECTURE.md` for structure, `docs/UI.md` and `brand/` for anything visible, `docs/DEVICE_PROTOCOL.md` for anything the board sees, `docs/HARNESS.md` and `docs/PROVIDERS.md` for the brain, tools and models.

How to work:

- Feature first: `lib/features/<name>/domain` (pure Dart, freezed models, repository interfaces), `data` (implementations, providers), `presentation` (widgets that read providers). Screens never import a `data` implementation or make HTTP calls.
- No other state, routing or model library. A new dependency needs its reason written in `docs/ARCHITECTURE.md`.
- Platform differences only through `PlatformInfo` or an interface chosen once in `data`.
- Everything visible comes from the brand: theme colors, named text styles, `Space.*` tokens, widgets from `lib/core/widgets`, copy in the tone of `brand/voice.md`. Never a hex literal or an inline `TextStyle` in a widget.
- Watch providers narrowly with `select`. Functions that can fail return `Result<T>` with a typed `Failure`.
- Keys only through `SecretStore`. Never in `AppSettings`, a log, a toast, a URL or a fixture. Never print one.
- A protocol change updates `docs/DEVICE_PROTOCOL.md`, the app and `tool/mock_device` together, and says in your summary what the firmware still needs.
- A new PC tool follows the `add-harness-tool` skill: a safety tier, a spoken result, a test.
- No em dashes, no emojis, in code, comments or UI copy.

After changing annotated classes run `dart run build_runner build --delete-conflicting-outputs`. Before you finish: `flutter analyze` with zero issues, `dart format .` changing nothing, `flutter test` passing, and new tests for any parsing, mapping or repository logic. Try it against the mock (`dart run tool/mock_device/main.dart`) when the change is visible; do not start or drive an app someone else is running.

Finish with: what changed and why, the analyze, format and test results, what you checked against the mock, and anything the firmware side still needs.
