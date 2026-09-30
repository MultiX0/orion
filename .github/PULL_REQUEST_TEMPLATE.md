## What and why

<!-- A few plain sentences. Link the issue: "Fixes #12". -->

## Part

- [ ] Firmware
- [ ] App
- [ ] PC control (harness)
- [ ] Wake word
- [ ] Case
- [ ] Docs

## How it was tested

<!--
Which platforms (Android, iOS, Windows), the mock board or a real one, and what you saw.
For firmware: what you ran on the board, and numbers where they exist (latency, free internal RAM after a few turns).
For UI changes: a screenshot or a short video.
If you have no board, say so.
-->

## Checklist

- [ ] One intent in this pull request.
- [ ] `dart format --output=none --set-exit-if-changed lib test tool` changes nothing.
- [ ] `flutter analyze` reports no issues.
- [ ] `flutter test` passes, with new tests for parsers, mappers or repositories I changed.
- [ ] The firmware builds with ESP-IDF 5.5.5 with no new warnings, if I touched it.
- [ ] `docs/DEVICE_PROTOCOL.md`, the firmware and the mock device agree, if I changed the protocol.
- [ ] Docs updated where this change made them wrong.
- [ ] New dependencies, if any, are named above with the reason.
- [ ] No keys, tokens, passwords, personal data or private network addresses anywhere in the diff.
- [ ] No em dashes and no emojis in code, comments, docs, commits or UI strings.
- [ ] I agree that this contribution is licensed under the PolyForm Noncommercial License 1.0.0, as described in `CONTRIBUTING.md`.
