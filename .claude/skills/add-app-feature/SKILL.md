---
name: add-app-feature
description: Add a screen or a feature to the Orion Flutter app the way the codebase is built, feature first with domain, data and presentation layers, Riverpod code generation, go_router, freezed models and the brand's widgets, tested and checked against the mock board. Use when adding or reshaping a screen, a setting, a data flow from the board, or any user-visible app feature.
---

# Add an app screen or feature

## 1. Read first

- `docs/ARCHITECTURE.md` (layers, state, routing, dependencies) and `docs/CODE_STYLE.md`.
- `docs/UI.md` and the relevant files in `brand/` (`colors.md`, `typography.md`, `spacing-layout.md`, `motion.md`, `components.md`, `voice.md`). The brand wins when the two disagree.
- If the feature needs something from the board: `docs/DEVICE_PROTOCOL.md`. If the endpoint or event does not exist yet, the change is a protocol change; see step 6.
- A similar existing feature. `lib/features/talk` is small and complete; `lib/features/conversation` shows a list from the board plus live WebSocket events.

## 2. Domain: models and interfaces (pure Dart)

`lib/features/<feature>/domain/`. No `package:flutter` imports here.

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'thing.freezed.dart';
part 'thing.g.dart';

/// One line on what this is, only if the name does not say it.
@freezed
abstract class Thing with _$Thing {
  const factory Thing({required String id, String? label}) = _Thing;

  factory Thing.fromJson(Map<String, dynamic> json) => _$ThingFromJson(json);
}
```

JSON on the wire is snake_case; `build.yaml` maps camelCase fields for you, so `@JsonKey(name:)` is only for names that differ otherwise. A repository interface goes here too, with methods that return `Result<T>` (`lib/core/result.dart`) or throw one typed `Failure` documented on the method.

## 3. Data: implementation and providers

`lib/features/<feature>/data/`. Implement the interface over `DeviceClient`, dio or storage, and wire it with a generated provider:

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'thing_providers.g.dart';

@riverpod
Future<List<Thing>> things(Ref ref) async {
  final result = await ref.watch(deviceClientProvider).things();
  return result.getOrThrow();
}
```

- Mutable state is one small `@riverpod` Notifier per feature (see `TalkNotifier`). Derived values get their own provider so widgets can watch narrowly. `keepAlive` only when the state must outlive the screen.
- Anything that reaches the network, storage or the OS has a fake used when `useFakesProvider` is true, so widget tests never touch real I/O.
- Keys only through `SecretStore`. Settings through `SettingsStore` and `AppSettings`.
- OS differences go behind an interface picked once from `PlatformInfo`, never `Platform.isX` in a widget.

Then generate:

```
dart run build_runner build --delete-conflicting-outputs
```

## 4. Presentation: the screen

`lib/features/<feature>/presentation/`. One widget per file, under about 150 lines, split into private or sibling widgets as it grows.

- `ConsumerWidget` by default; `ConsumerStatefulWidget` only to own a controller or ticker. No `setState` for data, no HTTP, no JSON, no `data` implementation imports.
- Watch narrowly: `ref.watch(thingProvider.select((t) => t.label))`.
- Design every state: loading (the brand's motion or a skeleton, not a bare spinner), empty, error with what to do next, and offline, which is the most common real state.
- Build from `lib/core/widgets` (`Atmosphere`, `OrionAppBar`, `OrionCard`, `OrionButton`, `OrionTextField`, `OrionChip`, `OrionSwitch`, `OrionSelectField`, `KeyField`, `showOrionToast`, `StatusDot`, `MonoLabel`, `Skeleton`, `EmptyState`) and the theme: text through the named styles, colors from the theme or the brand extension, spacing through `Space.*`, motion through `lib/core/motion`. No hex literals, no inline `TextStyle`, no Material defaults for visible controls.
- Copy per `brand/voice.md`: short, warm, direct, buttons are verbs, errors say what to do. No em dashes, no emojis.
- Respect reduced motion. Keep layouts working from a 390 px phone to a 1100x720 desktop window.

## 5. Route and navigation

- Add the route to `lib/app/router.dart` with `orionTabPage` (inside the shell) or `orionPage` (onboarding) or `orionModalPage`. Desktop-only screens sit behind `platform.canHostHarness`, the way `/harness` does.
- A top-level destination also gets a `ShellTab` in `lib/app/shell/shell_tabs.dart` and a place in the `mobile`, `more` and `desktop` lists. Most features belong inside an existing screen instead.

## 6. When the board is involved

Change `docs/DEVICE_PROTOCOL.md` first, then the app (`lib/core/network`, `lib/features/device`), then the mock in `tool/mock_device/` so the feature works with no board, and say what the firmware needs. Parse every new response or event in a unit test with a recorded fixture in `test/fixtures/`.

## 7. Tests

Tests mirror the source path under `test/`. Unit-test parsers, mappers and repositories against fixtures (`mocktail` for interfaces, never mock dio). Widget-test only behavior a glance would miss, with `useFakesProvider.overrideWithValue(true)` and in-memory stores (see `test/features/settings/about_test.dart`).

## 8. Check and try it

```
flutter analyze
dart format .
flutter test
dart run tool/mock_device/main.dart          # second terminal
flutter run -d windows                       # and on an Android device or emulator
```

Pair with the mock (`localhost:8080`, or `10.0.2.2:8080` from the emulator, code `123456`), walk the feature through its loading, empty, error and offline states (stop the mock for offline, `--flaky` for reconnects), and confirm nothing rebuilds on every state tick. Report what you checked and on which platforms.
