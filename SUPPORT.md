# Getting help

Orion is maintained by one person, so the fastest answers usually come from the docs and from other builders.

## Read first

- `README.md`: what Orion is and how to run the app.
- `docs/FIRMWARE.md`: flashing a board, updating without losing settings, first start, power, Wi-Fi changes and factory reset.
- `docs/PROVIDERS.md`: setting up the language model and Fish Audio.
- `docs/HARNESS.md`: PC control on the desktop app, including the Windows firewall and port 7331.
- `docs/TROUBLESHOOTING.md`: common problems and their fixes.

## Ask a question

Use GitHub Discussions: https://github.com/MultiX0/orion/discussions

Good for: "how do I", setup trouble, which power bank or speaker works, printing the case, wake word training, ideas you want to talk through before writing code.

## Report a bug

Open an issue: https://github.com/MultiX0/orion/issues/new/choose

Use it when something is broken and you can describe what happened. Search the open and closed issues first.

## What to include

The more of this you give, the faster it gets fixed:

- **What you did, what you expected, what happened.** One or two sentences each.
- **Versions.** Firmware version (in the app, or in `GET /api/info` from the board). App version and platform: Android, iOS or Windows, and the OS version.
- **Your setup.** Which language model provider and model, which speech provider, whether PC control is on and in which mode. Never the keys themselves.
- **How the board is powered.** Charger or power bank. Some power banks switch off at low current.
- **Logs.** The board's serial console output around the problem over its USB-C port (`idf.py monitor`, or any serial terminal), the app's output from `flutter run`, or the PC control log in `~/Orion/logs`.
- **Wi-Fi.** The board is 2.4 GHz only. Say if your router mixes 2.4 and 5 GHz under one name, and roughly how far the board is from it.
- **For voice and wake word problems:** the language you spoke, how far you were from the board, the room noise, and whether it fails every time or sometimes.

Before you post, remove API keys, pairing tokens, Wi-Fi passwords, and anything personal from logs and screenshots. The board's config masks keys to the last four characters, but serial logs and your own scripts may not.

## Security problems

Do not post them in Discussions or issues. See `SECURITY.md`.

## Commercial use

Orion is free for personal and non-commercial use under the PolyForm Noncommercial License 1.0.0. To use it in a product, a paid service or at a company, ask the author through GitHub: https://github.com/MultiX0
