# Changelog

All notable changes to Orion are written down here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The firmware follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html); its version is in `firmware/version.txt`. Firmware and app releases are listed together, and each entry says which part changed.

## [Unreleased]

## [1.1.0] - 2026-11-11

Firmware 1.1.0 (tag `fw-v1.1.0`) and app 1.1.0 (tag `v1.1.0`), and the first Orion Hub (0.1.1, in `hub/`).

### Firmware 1.1.0

#### Added

- Orion Hub: the board finds hubs on the network, pairs with one, and sends every question to the hub first. The first device a hub sees becomes its owner; any later one shows a four digit code on its screen until the owner approves it. The menu's first card shows the hub with a search, connect or disconnect button. The app does the same through `GET` and `POST /api/hub`, and the console through `hub`.
- Orion Link: every device has a permanent id and answers `GET /.well-known/orion`. The board's mDNS record and beacon carry its `id` and `kind`. When the hub's address changes, the board finds the same id again (mDNS, then a sweep of its /24 on port 8780), and it learns where the PC and the phone are from their links. See `docs/ORION_LINK.md`.
- A brain can ask for the reply without the wake word: when an answer ends in a question, the board plays the chime and listens at once.
- Any provider can be the board's own model. Each request carries what that provider takes: no `temperature` for Anthropic and OpenAI, `max_completion_tokens` for OpenAI, thinking off for Claude. Anything else is learned from the provider's first error.
- Console: `power watch` and `power ilim` for the charger, `spk supply` and `spk prio` for the speaker.

#### Changed

- The voice is Fish Drama 3 (`drama-3`) with the Orion Voice by default. It bills Fish API credit; `s2.1-pro-free` can still be picked in the app.
- The camera is used only when you ask for it in so many words ("take a photo", "look at this", "what do you see"). The model no longer decides to look on its own.
- Steadier sound on a weak USB port: the charger's input limit is 1500 mA instead of 500 and stays set, the voice follows the supply, Wi-Fi transmits more quietly while Orion speaks, and the audio writer runs at a higher priority while playing.
- Answers from the hub are spoken in whole bursts, one text to speech request each, instead of a piece at every comma.
- Playing a reply counts as progress, so a long spoken answer no longer runs into the 30 s turn deadline.
- The screen never shows voice cues, tokens or markers from a reply.

### App 1.1.0

#### Added

- An Orion Hub card in Settings: find a hub through the board, connect, see the approval code, or forget the hub.
- Orion Link ids for the desktop app (`pc-...`) and the phone app (`phone-...`), served on the brain's port. When the board's address changes, the app finds the board again by its id.
- Anthropic and OpenAI work as the PC's and the phone's model, with the request fields each one takes.

#### Changed

- The PC agent has full control of the computer: DeepSeek Harness 0.2.2-rc.1, pinned, with Playwright MCP (a visible Edge on Windows) for the web, winapp MCP for Windows applications, and Cua Driver on macOS and Linux. The task reaches it on stdin, and its settings are the headless profile's own patch. Whether a task runs at all is still the PC control choice: off, ask me first, or act on your own.
- The Windows setup program carries Node.js 24 for the PC agent, so it works on a PC that has never had Node. It is not added to the PATH and is removed with Orion. The zip has the same Node in `node\`.
- Fish Drama 3 is the default voice model, and the Fish credit note says what uses credit.

### Orion Hub 0.1.1

- A voice agent for a home server, in `hub/`: DeepSeek Harness on Claude Haiku 5.5 with Docker, network scans, SSH logins kept in a local vault, a memory file, and a log of every action. One Docker Compose service, with images for `linux/amd64` and `linux/arm64` on Docker Hub as `multix00/orion-hub`. See `hub/README.md`.
- The first device a new hub sees becomes its owner; every later one waits for the owner's approval, even after all of them were removed. Passwords said for an SSH login are kept out of the hub's logs, which only root can read.
- When the hub cannot answer before anything was said, the board hands the question to its next brain.

### Known issues

- With Drama 3 as the default voice, a Fish account with no API credit cannot speak. Pick `s2.1-pro-free` in the app for free speech; hearing still needs credit.
- The board has no battery. On a weak USB port the voice can still break up; a strong 5 V charger fixes it.
- When Orion Link finds the board or the hub again at a new address, it trusts the device that answers with the right id. A device on the same network that pretends to be one of them can receive that pairing's token. See `SECURITY.md`.

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

[Unreleased]: https://github.com/MultiX0/orion/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/MultiX0/orion/releases/tag/v1.1.0
[1.0.0]: https://github.com/MultiX0/orion/releases/tag/fw-v1.0.0
