# The serial console

The board runs an `esp_console` REPL on its USB port (the ESP32-S3's USB-Serial-JTAG, 115200 baud), prompt `orion>`. Every component registers its own commands, so the whole board can be driven and measured with nobody at the keyboard: no finger on the screen, no voice in the room.

## Talking to it

Use `tools/serial_capture.py`. It opens the port without toggling DTR and RTS (which would reset the board), captures for a fixed time, writes a file and exits. It shares the flash lock with `tools/flash.ps1`, so a capture and a flash never collide.

```
python tools/serial_capture.py --seconds 20 --out logs/boot.txt                 # reset, capture the boot
python tools/serial_capture.py --no-reset --seconds 15 --send "state" --out logs/state.txt
python tools/serial_capture.py --no-reset --seconds 30 --send "vol 0" --send "ask what time is it" --out logs/ask.txt
```

- `--send` may be repeated; lines go out 1.5 s apart (`--send-delay`).
- `--no-reset` keeps the running state. Without it the board restarts at open, which is what you want for a boot log.
- Wake word debug clips framed as `ORION_CLIP_BEGIN <name> <rate>` ... `ORION_CLIP_END` are written to `logs/wake_clips/<name>.wav`.
- Any serial terminal works too (the console falls back to a plain line mode when the terminal does not answer its probe). Avoid `idf.py monitor` for scripted use: it never returns.

Things to know:

- **The console drops every byte above 0x7F**, so Arabic cannot be typed. `ask`, `talk` and `say` take `hex:<utf8 hex>` instead: `python tools/cloud/talk_hex.py "شو عاصمة الأردن؟"` prints the `talk hex:...` line. Use `ask hex:` for a full turn.
- **Long lines are dropped** past the USB receive buffer. Send long hex lines in pieces (48 bytes, 30 ms apart), which `tools/cloud/console_session.py` does.
- **Commands queue up.** While a turn keeps the console busy, lines sent too fast pile up and some are lost. `tools/cloud/console_session.py` sends one command, waits for its own result line, then sends the next, and sends `vol 0` first so a measurement run is silent.
- Keys never go through the console as text. `cfg_set` refuses any `*_key` and `wifi_pass`; copy a stored key with `cfg_copy`.

## Every command

### The assistant (main)

| Command | Does |
|---|---|
| `state` | current state, turn count, the last turn's timings, what was heard and replied |
| `wake` | as if the wake word fired |
| `cancel` | abandon the current turn |
| `ask <text>`, `ask hex:<utf8 hex>` | a full turn on typed text, through the state machine, the brains, the screen and the voice, minus the microphone |
| `heap` | free internal RAM, largest internal block, free PSRAM |
| `volume <0..100>` | set the volume and store it in NVS |
| `help` | every command with its help line |

### board

| Command | Does |
|---|---|
| `power` | SY6970: VBUS, VBAT, VSYS, charge current and state |
| `audio_en <0\|1>` | the mic and amp enable line |
| `bl <0\|1>` | the backlight |

### Audio

| Command | Does |
|---|---|
| `tone [hz] [ms]` | a sine through the speaker, default 1 kHz |
| `wav <name> [open]` | play `/assets/<name>`; `open` keeps the mic running through it |
| `vol [0..100]` | volume until the next restart (use `volume` to store it) |
| `assets` | list the assets partition |
| `mic` | noise floor, RMS, level, chunk, mute and drop counters |
| `micmon [sec]` | RMS every 250 ms |
| `loopback [sec] [open]` | record, then play it back |
| `record` | one utterance with the end of speech detector, played back |
| `selftest` | speaker to mic check with a 1 kHz tone: quiet RMS, RMS during the tone, share of energy at 1 kHz |
| `spk [stats]` | loudness numbers for the last stream: peak and RMS in and out, limiter depth, clipped samples, guard trips |
| `spk boost on\|off` | the loudness chain (off by default) |
| `spk gain <db>`, `spk presence <db>`, `spk treble <db>`, `spk hpf <hz>`, `spk mud <db>` | tune the chain live |
| `spk slots left\|both` | fill one or both I2S slots (both is right for this board) |

### Wake word

| Command | Does |
|---|---|
| `ww [stats]` | steps, inferences, detections, feature and inference time, arena use, CPU load |
| `ww start`, `ww stop` | run or park the pipeline |
| `ww debug <0\|1>` | dump 2 s of audio around every detection over serial (stored in NVS as `debug_clips`) |
| `ww clip [name]` | dump the last 2 s of microphone audio now |
| `ww cutoff <0..255>` | the probability cutoff until the next restart (the manifest's 0.96 loads as 244) |

A detection logs `DETECTED "Orion" #n avg <0..255> max <0..255>`, and a detection the energy gate rejected logs `gated: model avg ..., but loudest 100 ms in 1.5 s was rms ..., need ...`.

### Camera

| Command | Does |
|---|---|
| `cam [jpeg]` | one 640x480 JPEG, size and time |
| `cam bench [n]` | n captures, average, minimum and maximum time and size |
| `cam dump` | a JPEG over serial as base64 between `ORION_JPEG_BEGIN` and `ORION_JPEG_END` |
| `cam preview [w h]` | RGB565 preview frames, with the frame rate |
| `cam ircut <0\|1>` | the IR cut filter |
| `cam info` | sensor and settings |

### Cloud

| Command | Does |
|---|---|
| `talk <text>`, `talk hex:<utf8 hex>` | stream a reply to this text and speak it, without the state machine or the screen |
| `say <text>`, `say hex:<utf8 hex>` | speak this exact line, no model |
| `asr_test [file.wav]` | speech to text on a WAV from the assets partition |
| `prewarm` | open the TLS connections to every host now |
| `cloud_status` | network, which keys are set (by length), the last turn's timings |
| `cloud_test llm\|stt\|tts` | the smallest real request for one stage, as `POST /api/config/test` does |
| `cloud_reload` | reread the cloud settings from NVS, as the API does after a change |
| `cloud_selftest` | the chunker and SSE parser test cases, run on the chip |
| `tts_rate [16000\|24000\|32000\|44100]` | the sample rate asked of Fish until the next restart |
| `tts_cushion [ms]` | audio a reply waits for before it plays (350 by default); 0 plays at once |
| `cfg_set <key> <value>` | store a setting in NVS (not keys) |
| `cfg_copy <from> <to>` | copy a stored value to another key, for example `cfg_copy di_key stt_key` |
| `cfg_del <key>` | remove a setting, so its older key or the default applies |

After `cfg_set`, `cfg_copy` or `cfg_del`, run `cloud_reload` (or restart) for the cloud to pick it up.

Switching a stage without the app, for example speech to text to DeepInfra:

```
cfg_set stt_prov openai_compatible
cfg_set stt_url https://api.deepinfra.com/v1/openai
cfg_copy llm_key stt_key
cfg_set stt_model Qwen/Qwen3-ASR-1.7B
cloud_reload
cloud_test stt
```

### Bluetooth setup

| Command | Does |
|---|---|
| `prov [status]` | name, id, whether setup mode runs, its code, network state |
| `prov start` | restart into setup mode |
| `prov stop` | leave setup mode |
| `prov token <token>` | store an app token (8 to 64 characters) as a paired app |

### Screen

| Command | Does |
|---|---|
| `ui state <name>` | show a state: `boot`, `idle`, `wake`, `listening`, `thinking`, `speaking`, `error`, `offline` |
| `ui text <utf8>` | set the text box |
| `ui level <0..1>` | the listening level |
| `ui tap` | a tap on the glass |
| `ui menu [ip] [rssi] [pc] [conn]` | open the menu with sample values (restart afterwards) |
| `ui cam [live]` | the camera card from a compiled-in test JPEG, or live |
| `ui setup [off]` | the Bluetooth setup screen |
| `ui ar <1\|2>`, `ui tags <1\|2>` | compiled-in Arabic and tagged test strings |
| `ui fps`, `ui perf` | frame rate |
| `ui shot` | the screen as base64 RGB565; `tools/ui_shot.py` turns a capture into a PNG |
| `ui mem` | LVGL and heap memory |

## Logs worth reading

| Line | Means |
|---|---|
| `reset reason: brownout` | the supply sagged; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#the-board-resets-when-it-speaks) |
| `after wifi heap int ...` | internal RAM after each boot step |
| `sm: idle -> wake` | state changes |
| `turn: heard: ...`, `turn: reply: ...` | the transcript and the answer |
| `turn=<n> asr_ms=... total_ms=... heap_int=...` | one line per turn |
| `turn_perf speech_end_to_audio_ms=...` | the full timing breakdown |
| `cloud_pc: pc brain at ... online` | the PC brain answered its check |
| `orion_api: links: pc on, phone off` | which apps are linked |
| `orion_net: '<ssid>' is not in the 2.4 GHz scan` | the network is 5 GHz only or out of range |
| `wakeword: gated: ...` | a detection the energy gate turned down |
