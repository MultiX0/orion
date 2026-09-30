# Testing

Orion is tested in four places: the app's own tests, the board driven over its console, the cloud services measured from a PC, and the brain run against real apps. The rule behind all of it: measure what the user will notice, on the real thing where possible, and write the number down.

## The app

```
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

`test/` mirrors `lib/`. Fixtures recorded from real services and real boards are in `test/fixtures/` (model lists from DeepInfra, OpenAI, Anthropic and Ollama, Fish credit, WebSocket events, beacons, an ESP32 MJPEG capture, `route print` and `ip route` output, Windows Search and Start Menu output, `nvidia-smi` and `/proc` samples, a dsh settings file).

| Area | Tests |
|---|---|
| Network | the MJPEG parser on real captures, the reconnecting socket (backoff, silence, sleep), discovery (every source, dedupe, confirmation), local address choice |
| Device | every WebSocket event type, the HTTP client |
| Onboarding | Bluetooth mappers, the provisioning repository over a scripted board, the whole Bluetooth flow as a widget test, the LAN hand-over, pairing with a code |
| Providers | model list parsing per provider, the model picker, the speech pickers, the board config repository against the real mock over HTTP (version 2 blocks, masking, the test endpoint, orion-config in parts), Fish |
| Harness | the tool server (auth, SSE streaming piece by piece), the PC brain, the phone brain host, memory, approval modes, native tool parsers, Windows tools, spoken tool names, dsh |
| Settings | about |
| App | boot without a board, the real wiring against fakes |
| Tools | the mock board, and the harness loop: the mock asks for a tool, the desktop approves, the result flows back |

The board config tests start the mock board themselves. Widget tests run on `useFakes`, with `NullAudioPlayer` so they never reach for an audio device.

### Against the mock board

```
dart run tool/mock_device/main.dart [--port 8080] [--fps 10] [--flaky] [--config-v1]
```

Every feature runs against it before it runs against a board. `--flaky` drops the WebSocket every 20 s to exercise reconnects; `--config-v1` is an older board. Its scripted keys: `bad` fails a stage test with 401, `nocredit` as the Fish speech to text key fails with 402, `busy` answers 409. `--dart-define=ORION_FAKE_BLE=true` runs Bluetooth setup against a scripted board (code `123456`, the password `wrongpass` fails, the hidden network `Observatory` joins).

## The board

Everything on the board can be driven over its serial console with nobody at the keyboard; see [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md). The checks worth running after a change:

| Check | Command | Healthy |
|---|---|---|
| Boot | `python tools/serial_capture.py --seconds 25 --out logs/boot.txt` | every `after <step>` line present, `reset reason: power on` or `software restart`, idle within 25 s |
| Memory | `heap` after a turn | 27 KB or more of internal RAM free |
| Speaker and mic | `selftest` | about 98 percent of the energy at 1 kHz, the tone far above the quiet reading |
| Wake word cost | `ww` | about 1.2 ms of CPU per 10 ms step, arena used under the declared size |
| Chunker and SSE | `cloud_selftest` | every case passes |
| Each stage | `cloud_test llm`, `cloud_test stt`, `cloud_test tts` | `ok` in well under a second on a warm board |
| A full turn, typed | `ask What is the capital of Jordan?`, then `ask hex:<...>` for Arabic | spoken answer; `turn_perf` first audio about 1.1 to 1.6 s |
| Camera | `cam bench 10` | 10 of 10, under 80 ms each once running |
| Screen | `ui perf` in each state, `ui shot` | 30 fps or more; the picture matches [FIRMWARE_SCREEN.md](FIRMWARE_SCREEN.md) |

Send `vol 0` first when nobody should hear the run: every stage still runs in real time at zero amplitude. Tell anyone in the room before a test plays sound.

`tools/board_session.py` holds the board lock for a whole sequence (write the app and model partitions, reset, capture, play clips on a timer), so nothing else can flash the board between your flash and your measurement:

```
python tools/board_session.py --app firmware/build/orion.bin --model firmware/build/wakeword_model.bin \
    --play logs/test/a.wav --play logs/test/b.wav --gap 40 --out logs/session.txt
```

### Over the network, from a PC

In `tools/cloud/`, all reading keys from `.env` and never printing them:

| Script | What it proves |
|---|---|
| `lan_api_test.py [--ip ...]` | finds the board by beacon, checks `/api/info`, 401 paths, `/api/state`, `/capture`, `/stream` rate, the WebSocket |
| `lan_config_test.py [--switch-stt]` | config version 2: masking, a bad value refused with nothing stored, a stage switched, tested and switched back, the version 1 block |
| `ble_pair_test.py --name Orion-1a2b --pop 123456 [--wrong-first] [--config]` | Bluetooth setup from the PC through ESP-IDF's own `esp_prov` modules: session, `orion-pair`, `orion-config` in parts, scan, a wrong password then the right one |
| `console_session.py --out <file> "<cmd>" ...` | a list of console commands, each waiting for its own result: the latency tables |
| `talk_hex.py "<Arabic>"` | the `talk hex:` line for an Arabic sentence |

### The wake word

`tools\replay_clips.ps1 -Path wakeword\test_clips` plays held-out clips through the PC speakers and counts detections from serial, one capture per clip. `-Negative` expects none. The training side has its own measurements; see [WAKEWORD.md](WAKEWORD.md#how-it-is-measured).

## The cloud services, from a PC

Numbers from the PC split a slow board turn into "the service" and "the board". In `tools/cloud/`:

| Script | Measures |
|---|---|
| `latency_probe.py [--runs 6] [--only asr,llm,tts]` | each stage over kept-alive sessions, the way the board calls them |
| `asr_speed.py` | every speech model on DeepInfra: latency, character error rate, whether English stays English |
| `llm_stream.py` | first token, first clause and completion over SSE |
| `keepalive_probe.py` | how long each host keeps an idle TLS connection |
| `loop_test.py` | the whole loop; `--latency-modes`, `--reuse`, `--gain-sweep`, `--prompt-bench`, `--questions` |
| `prompt_test.py [--speak]` | the system prompt against ten Arabic and five English questions, flagging what breaks speech |
| `chunker_test.py` | the chunker's cases, fed a few characters at a time (the same cases run on the board as `cloud_selftest`) |
| `make_earcons.py` | regenerates and scores the earcons |

## The brain, against real apps

```
dart run tool/brain_eval.dart google/gemma-4-31B-it-turbo --thinking=zai-org/GLM-5.3-Flash
```

Seven plain requests against the PC's real Spotify, Chrome and Calculator, checked on the screen (window titles, the Calculator's display), with the board's own prompt and "act on your own". It plays music for real. See [HARNESS.md](HARNESS.md#choosing-the-models-a-fast-one-to-answer-a-thinking-one-to-act) for the results and what they changed.

| Also | |
|---|---|
| `dart run tool/pc_brain_probe.dart "What time is it?"` | the brain alone with stand-in tools; prints what the board would say |
| `dart run tool/native_tools_check.dart [open\|stats\|shot\|media\|find\|lock]` | each native tool once, for real |
| `dart run tool/pc_harness.dart <board ip>` | the PC side without the window, against a real board |
| `DP_ORION_KEY=<key> dart run tool/dsh_e2e.dart` | one real dsh agent task |

## Before a release

By hand, on a real board and the real apps:

1. Flash the full image to a board that was factory reset. It boots into setup mode.
2. Set it up from a phone over Bluetooth, keys included. It joins, the app finds it, each stage's Test passes.
3. "Orion", then a question in Arabic and one in English. Both answered in the right language, first word under about 3 s.
4. "What do you see?" with something behind the board.
5. Pair the Windows app with a code. Both link dots light. Turn PC control on (the firewall prompt appears once), ask "open the calculator", then "close it".
6. Close the PC app; the phone answers a web question ("what's the weather in Amman?").
7. Close both; the board answers alone and says the PC app has to be open for a PC request.
8. Move it to another Wi-Fi from the app. Factory reset from the menu; it is back in setup mode.
9. Power it from a phone charger, and play a long answer at volume 100: no reset (`reset reason` after a reboot says why if there was one).
