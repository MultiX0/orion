# Security policy

Orion sits on your home network with a microphone, a camera, your API keys, and, if you turn on PC control, the ability to run things on your computer. Security reports are taken seriously and handled before feature work.

## Reporting a vulnerability

Please do not open a public issue, Discussion or pull request for a security problem.

Report it privately through GitHub:

1. Go to https://github.com/MultiX0/orion/security/advisories/new
   (or the repository's Security tab, then "Report a vulnerability").
2. Describe the problem, what an attacker needs (same Wi-Fi, Bluetooth range, physical access to the board, a malicious model reply), and what they get.
3. Include steps to reproduce: the firmware version (shown in the app and in `GET /api/info`), the app version and platform, and a request, script or log if you have one. Remove your own keys, tokens and passwords from anything you attach.

If private reporting is unavailable for some reason, contact the maintainer through GitHub at https://github.com/MultiX0 and ask for a private channel, without details of the problem.

What to expect:

- An acknowledgement within 7 days.
- An assessment and a plan within 30 days, or an explanation of why it will take longer.
- A fix released as a new firmware or app version, with a GitHub security advisory that credits you, unless you prefer not to be named.

Orion is maintained by one person in their own time, so these are targets rather than guarantees. Please give a reasonable time for a fix before publishing details.

## Supported versions

Only the newest release of each part gets security fixes.

| Part | Version | Supported |
|---|---|---|
| Firmware | 1.0.x | Yes |
| Firmware | before 1.0.0 (development builds) | No |
| App | the latest release | Yes |
| App | older releases and development builds | No |

A fix for the firmware ships as a new release on the Releases page. Update a board that is already set up with the steps in `docs/FIRMWARE.md`, which keep its settings.

## In scope

- **The board's LAN API**: the HTTP API on port 80, the `/ws` WebSocket, and the camera endpoints `/capture` and `/stream`. Every endpoint except `GET /api/info` must require the paired app's token (`X-Orion-Token`, or `?token=` on the WebSocket). A way around that, or a way to learn a token, is in scope.
- **Pairing**: pairing over the LAN with the six digit code on the board's screen (`POST /api/pair`), and pairing over Bluetooth in setup mode (ESP-IDF Unified Provisioning, security version 1, with a code on the screen as the proof of possession). Guessing, replaying or skipping the code, or pairing without seeing the screen, is in scope.
- **The PC harness on port 7331**: the tool server the desktop app runs when PC control is on. It listens on the LAN and must accept only the paired token. This includes `POST /tool`, the PC brain at `POST /v1/chat/completions`, the approval modes ("Ask me first" must really ask), the sandbox folder `~/Orion/agent`, and the Windows firewall rule the app adds for port 7331.
- **Key handling**: provider API keys and the pairing token. In the app they live in the OS keychain (flutter_secure_storage) and must never appear in settings files, logs, URLs or toasts. On the board they live in NVS and `GET /api/config` must only return the last four characters. A key leaking into a log, a crash dump, the serial console, a release file or a network request to anyone but its provider is in scope.
- **Prompt injection that crosses a boundary**: a web page, search result or model reply that makes Orion run a PC or phone tool the user did not ask for, or skip the approval step.
- **The release files**: anything in a published firmware image or app build that should not be there.

## Out of scope

- Attacks that need physical access to the board, such as reading its flash over USB. The firmware does not turn on flash encryption or secure boot, so someone holding the board can read the keys stored on it. Treat the board like a device that knows your keys, and use the factory reset in its menu before you give it away.
- Traffic on your LAN being readable. The board's API and the PC harness use plain HTTP inside your home network; calls from the board to Fish Audio and model providers use HTTPS with certificate checks. Reports that show a practical attack beyond "someone on the same network can read plain HTTP" are still welcome.
- The security of Fish Audio, your model provider, DeepSeek Harness, ESP-IDF or Flutter themselves. Report those to their projects. If Orion uses one of them in an unsafe way, that is in scope.
- What a model says. Wrong or rude answers are bugs for the issue tracker, not vulnerabilities.
- Denial of service by flooding the board from the same network.

## When you find a key in the repository

If you find something that looks like a real key, token or password anywhere in the repository or its history, report it privately the same way. Do not use it.
