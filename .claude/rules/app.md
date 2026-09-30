---
paths:
  - "lib/**"
  - "test/**"
---

# App rules

Full detail in `AGENTS.md` under "The app" and "Code style", and in `docs/ARCHITECTURE.md` and `docs/CODE_STYLE.md`.

- Feature first: `domain` is pure Dart (freezed models, repository interfaces, no Flutter import), `data` implements and wires providers, `presentation` reads providers. Screens never import a `data` implementation or make HTTP calls.
- Riverpod with code generation, go_router, freezed with json_serializable, dio. No other state, routing or model library. A new dependency needs its reason in `docs/ARCHITECTURE.md`.
- OS differences only through `PlatformInfo` or an interface chosen once in `data`. No `Platform.isX` in widgets.
- Visible things come from the brand: theme colors or the brand extension, named text styles, `Space.*` tokens, widgets from `lib/core/widgets`, motion from `lib/core/motion`. No hex literals, no inline `TextStyle`, no Material defaults for visible controls. Copy follows `brand/voice.md`.
- `ConsumerWidget` by default, `select` to watch narrowly, no `setState` for data. Every screen designs loading, empty, error and offline.
- Fallible work returns `Result<T>` with a typed `Failure`. No swallowed errors, no `.then` chains, every subscription cancelled.
- Keys only through `SecretStore`: never in `AppSettings`, logs, toasts, URLs or fixtures.
- Do not edit `*.g.dart`, `*.freezed.dart` or `lib/core/theme/tokens.dart`; regenerate them (`dart run build_runner build --delete-conflicting-outputs`, `dart run tool/gen_tokens.dart`).
- Anything that talks to the board follows `docs/DEVICE_PROTOCOL.md`, and the mock in `tool/mock_device` must keep up.
- Tests mirror the source path. Parsers, mappers and repositories are tested against fixtures in `test/fixtures/` with no personal data. `mocktail` for interfaces, never mock dio.
- Before a commit: `flutter analyze` clean, `dart format .` changes nothing, `flutter test` passes.
- No em dashes, no emojis, in code, comments or UI copy.
