# Orion documentation

Orion is a home voice assistant you build yourself: a LilyGO T-CameraPlus-S3 board that wakes on its name, listens, answers in Arabic or English with its own voice, and sees through its camera; a companion app for Android and Windows that sets it up and, on a PC or a phone, lends it a bigger brain with the web, a memory and real control of the computer; and a 3D printed case to put it in.

By MultiX0 (https://github.com/MultiX0), under the PolyForm Noncommercial License 1.0.0. Website: https://www.joinorion.io

## Start here

| | |
|---|---|
| [GETTING_STARTED.md](GETTING_STARTED.md) | What to buy, flashing the firmware, getting the app, setting up a board, power, updating and resetting |
| [USING.md](USING.md) | Talking to Orion, what it can do alone and with a PC or phone, the screen and the menu, the app's screens |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Real problems and their fixes: power, sound, Wi-Fi, pairing, PC control, the wake word, builds |

## How it works

| | |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | The whole system, a voice turn step by step, where answers are written, the board's states, where secrets live, why internal RAM shapes everything |
| [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md) | The board's API: discovery, Bluetooth setup, pairing, REST, the WebSocket, the brain interface, the mock board |
| [HARNESS.md](HARNESS.md) | PC control and the extended brain: the PC and phone brains, tools, approvals, memory, and how the models were chosen |
| [PROVIDERS.md](PROVIDERS.md) | The language model, speech to text and text to speech: presets, defaults, keys, Fish Audio credit |
| [VOICE.md](VOICE.md) | Orion Voice on Fish Audio, languages and register, emotion tags, the system prompt and how to change it, earcons |
| [WAKEWORD.md](WAKEWORD.md) | The "Orion" wake word: the model, its data and training, what the runs taught, the board runtime, retraining |

## The firmware

| | |
|---|---|
| [FIRMWARE.md](FIRMWARE.md) | Building and flashing, partitions, configuration, boot, tasks, memory, every component and every NVS key |
| [FIRMWARE_CLOUD.md](FIRMWARE_CLOUD.md) | The voice pipeline on the board: connections, speech to text, the model, the camera, the chunker, text to speech, latency |
| [FIRMWARE_AUDIO.md](FIRMWARE_AUDIO.md) | Microphone, end of speech, speaker, the loudness chain and why it is off, earcons |
| [FIRMWARE_SCREEN.md](FIRMWARE_SCREEN.md) | The 240x240 interface: brand, fonts and Arabic, states, text, menu, camera preview, setup screens |
| [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md) | The serial console: every command, and the logs worth reading |

## The app

| | |
|---|---|
| [APP.md](APP.md) | Structure, state, routes, networking, storage, Bluetooth setup, building for each platform, the mock board |
| [UI.md](UI.md) | Brand to Flutter, motion, the orb, the shell, every screen |

## The case

| | |
|---|---|
| [CASE.md](CASE.md) | The printed enclosure and stand: parts, printing, hardware, design decisions, rebuilding. The full spec is [`case/SPEC.md`](../case/SPEC.md). |

## Working on Orion

| | |
|---|---|
| [CODE_STYLE.md](CODE_STYLE.md) | How code, comments, tests and commits are written, for Dart, C and Python |
| [TESTING.md](TESTING.md) | App tests, the mock board, driving the board over serial, measuring the cloud, the brain eval, the release checklist |
| [RELEASING.md](RELEASING.md) | Cutting a firmware, app or wake word release |

## Elsewhere in the repository

| | |
|---|---|
| [`brand/`](../brand/) | Colours, type, spacing, motion, the logo and the voice of the copy: the design source for the app, the board and the case |
| [`wakeword/README.md`](../wakeword/README.md) | Every wake word training script and command |
| [`case/SPEC.md`](../case/SPEC.md) | Every case dimension with its source |
| `voice/VOICE.md`, `voice/VOICE_v1.md` | The full records of the library voice auditions that came before Orion Voice |
| `firmware/assets/README.md`, `firmware/assets_src/README.md` | What belongs in the runtime filesystem and what stays at build time |
| `harness/dsh/README.md` | Where the optional dsh agent keeps its files |

## Images

`docs/images/board/` holds screenshots taken from the real board with `ui shot`. `docs/screenshots/` holds the app's screenshots used by the top level README.
