# Changelog

All notable changes to Orion are written down here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The firmware follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html); its version is in `firmware/version.txt`. Firmware and app releases are listed together, and each entry says which part changed.

## [Unreleased]

## [1.0.0] - 2026-09-24

The first public release: firmware 1.0.0 for the LilyGO T-CameraPlus-S3 (tag `fw-v1.0.0`), and app 1.0.0 with builds for Android and Windows (tag `v1.0.0`). iOS is set up in the same code but has not been built or tried on a device yet. Website: https://www.joinorion.io.

### Firmware 1.0.0

#### Added

- The whole voice loop runs on the board. Say "Orion", ask your question, and the board transcribes it, asks your language model, and speaks the answer through its own speaker. No PC or phone is needed once it is set up.
- A custom "Orion" wake word, trained for this board and running on the chip.
- Answers in Modern Standard Arabic by default, in a female voice (Orion Voice on Fish Audio).
- Any OpenAI-compatible language model, with presets for DeepInfra, OpenAI, Anthropic, Groq, OpenRouter and Ollama, plus a custom endpoint.
- Speech to text and text to speech through Fish Audio or an OpenAI-compatible speech endpoint.
- With a Fish Audio voice, replies carry natural voice cues, such as a laugh or a pause, where a person would sound that way. Any other voice gets plain text with no brackets. The screen shows the reply without the cues.
- Setup over Bluetooth. A new board shows its name and a six digit code. The app scans for Wi-Fi through the board, then sends the network, the pairing and your provider keys over the encrypted Bluetooth session. The board is 2.4 GHz only.
- Setup mode also starts by itself when the saved network does not answer within 30 seconds of boot, so a board that moves house can be set up again. It closes after 10 minutes.
- Pairing over your network with a six digit code on the board's screen, for a second phone, a PC, or a reinstalled app. Up to four apps stay paired at once.
- The board shows up in the app on its own, through mDNS and a UDP broadcast on port 7332, with manual address entry as a fallback.
- A LAN API and a live WebSocket for the app: board state, settings, typed questions, spoken lines, stop, conversation history and restart. Every request except the board's basic info needs the paired app's token. Keys are never sent back in full, only their last four characters.
- A live camera stream at about 10 frames per second, 640x480, for up to two viewers at a time, plus single snapshots.
- A screen with an idle face, an animated four-point star, the reply as text, and two lights for the phone and PC connections.
- A menu on the screen with Wi-Fi setup and a factory reset that needs a second tap within 4 seconds.
- With PC control on in the desktop app, the board sends each question to the PC first, so answers can use the time, the web and the PC itself. If the PC does not answer, the board falls back to a linked phone, then to its own model.
- The clock is set from the network, so Orion knows the time and date. The time zone follows the app's device, or a fixed offset chosen in the app.
- The wake word can be turned off from the app. The board then stops listening for its name and a tap starts a turn.
- Runs from any USB-C charger or power bank after flashing, and restarts by itself after a crash.
- Release files: one full image for a new board, separate images for updating a board without losing its settings, and `SHA256SUMS.txt`. No key, password or address is built into any of them.
- One-click installers in `tools/install/`: double-click `flash-orion.bat` on Windows, or run `flash-orion.sh` on Linux and macOS. They find the board, get esptool, download the full image from the latest release, check its SHA256 and write it. No admin rights needed.
- A 3D printable case in `case/`, with a small fit test to print first.

### App, first public release

#### Added

- Setup in seven steps: welcome, find the board, pair, choose the brain, choose the voice, choose PC control, ready. Keys are checked against the real provider before you continue.
- Home screen with an orb that follows what the board is doing: listening, thinking, speaking.
- Talk: type a question and hear the board answer.
- Conversation history from the board. Voice cues such as [laugh] are hidden in the transcript, as on the board's screen.
- Live camera view, with snapshots saved to your device.
- Providers screen to change the language model, the thinking model used for PC tasks, and the speech providers. Models are picked from the provider's own list, with search.
- Settings, including PC control with three choices: off, ask me first, or act on your own. The same choice is available on the phone and reaches the board.
- PC control on Windows: open apps, lock the screen, read system stats, take a screenshot and describe it, find files, control media, search the web and read pages. Bigger tasks go to DeepSeek Harness, working in a sandbox folder under `~/Orion/agent`. Risky actions ask first unless you chose otherwise. Every call is logged to `~/Orion/logs`.
- Turning PC control on adds a Windows firewall rule for port 7331, limited to the local network, after asking you through Windows' own prompt.
- Harness screen on the desktop: a live feed of tool calls, and the calls waiting for your approval.
- API keys and the pairing token are kept in the operating system's secure storage and sent only to the board you paired with.
- A mock board (`dart run tool/mock_device/main.dart`) to try the whole app without hardware.

### Known issues

- Rough edges remain in places. Common problems and their fixes are in `docs/TROUBLESHOOTING.md`.
- The board only joins 2.4 GHz Wi-Fi.
- Some power banks switch off at the board's low current draw. Use the power bank's low-current mode or a charger.
- The 3D case model measurements are not fully accurate yet and are being fixed. Print the fit test first.
- The full image clears the board's settings, so a board flashed with it starts Bluetooth setup again. The separate images update a board and keep them.
- The Android APK is signed with a development key, so a later build signed with a release key may need this one uninstalled first. The Windows app is not code signed, so SmartScreen warns on first run.

[Unreleased]: https://github.com/MultiX0/orion/compare/fw-v1.0.0...HEAD
[1.0.0]: https://github.com/MultiX0/orion/releases/tag/fw-v1.0.0
