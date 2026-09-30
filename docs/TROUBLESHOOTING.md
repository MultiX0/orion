# Troubleshooting

Real problems and their fixes. Most answers start with the board's serial log: `python tools/serial_capture.py --seconds 30 --out logs/boot.txt` for a boot, or `--no-reset` to watch a running board. The console commands are in [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md).

## Power and sound

### The board resets when it speaks

The boot log says why the last run ended: `reset reason: brownout` or `power on` in the middle of an answer is the USB supply sagging under the speaker, not a crash. Dense, loud phrases draw the most current in bursts.

- Use a wall charger or a good power bank instead of a laptop port.
- Keep the loudness chain off (`spk boost off`, the default). With +12 dB of make-up gain it reset the board on a laptop port two times out of two on "say the alphabet backwards".
- Turn the volume down a little if it still happens.

### Crackle or swallowed syllables

The same cause, short of a reset: the supply sags and the amplifier distorts. Same fixes. If you turned `spk boost on`, the limiter's pumping adds to it.

### The answer goes silent in the middle, then carries on (or stops)

Look at the `turn_perf` line: `gap_ms` is how long the speaker ran dry.

- **Weak Wi-Fi.** At -80 dBm answers stalled for 11 to 18 s. Check the signal on the menu's network card; move the board or the access point. The board joins the strongest access point with the saved name at boot, so restart it after moving.
- **An old `sdkconfig`.** The fix for this was 64 Wi-Fi receive buffers and a 32 KB TCP window. A build with a stale `firmware/sdkconfig` goes back to 32 buffers and a 64 KB window, and 24 kHz audio bursts overflow them. Delete `firmware/sdkconfig` and rebuild.
- **The power guard** only exists with `spk boost on`, and only turns the sound down by up to 12 dB after 4 s above -5 dBFS; `spk stats` shows whether it tripped.

### A click when the answer pauses

The speaker waits for 350 ms of audio before a piece plays and 700 ms after running dry, and fades to silence instead of cutting. If you set `tts_cushion 0`, set it back to 350.

### No sound at all, or the mic hears nothing

- The speaker must be in the socket marked "Audio" on the back.
- GPIO 18 enables both the microphone and the amplifier, active low. `audio_en 1` turns the path on; `selftest` should report the 1 kHz tone at about 98 percent. If both look dead with no error, this line is the first suspect.
- `vol` may be 0 from a test session. `volume 80` sets and stores it.

### Too quiet

Volume 100 is the loudest plain setting (100 is unity; there is no digital gain above it). On a strong supply, `spk boost on` adds make-up gain behind a limiter; judge it by ear, and go back if it crackles. Do not ask Fish for more loudness with a `prosody` block: that makes it about 9 dB quieter.

### The volume came back at 70, or at 100

`vol <n>` changes the volume until the next restart; `volume <n>` and the app store it. `tools/cloud/provision.py` rewrites the whole settings partition and sets `VOLUME` from `.env` (100 if unset).

### The board goes dark on a power bank

Some power banks switch off when the current draw is low. Turn on the power bank's low-current mode, or use a charger.

## Wi-Fi and finding the board

### The board will not join the network

- **5 GHz.** The ESP32-S3 has no 5 GHz radio. After three failed attempts the log prints every 2.4 GHz network it can see and says `'<name>' is not in the 2.4 GHz scan` when yours is not there. Turn on 2.4 GHz on the router, or use its 2.4 GHz name. The Bluetooth setup's network list only ever shows what the board can join.
- **Wrong password.** Setup says so and lets you try again in the same session. On some routers the verdict takes about 24 s.
- A board whose saved network does not answer within 30 s of boot goes into setup mode by itself.

### The app does not find the board

- **Windows Firewall.** On first launch Windows asks about the app's discovery sockets. If the prompt was dismissed or the network is marked Public, mDNS and the beacon on UDP 7332 are blocked. Discovery still tries the subnet sweep and the `orion.local` name; allowing `orion.exe` on private networks brings the others back.
- **mDNS filtered by the router.** The beacon and the sweep cover it.
- **Different subnets.** The phone or PC must be on the same network as the board. Guest networks and some mesh systems isolate clients from each other.
- **Manual entry** always works: the board's IP address is on the menu's network card.
- **Android emulator**: the beacon and the sweep do not cross its NAT; use `10.0.2.2:8080` for the mock board.
- **A board you did not expect** at `localhost:8080` is the mock board still running. Stop it.

### The board says the wrong time

The board's clock comes from `pool.ntp.org`, and its time zone from the app: Settings, Device, Time zone. On Automatic the app sends its own device's zone each time it reaches the board, so open the app once after summer time starts or ends. Pick a fixed offset there if the board lives somewhere else. Until the clock syncs after boot, the model is told nothing about the time and says it does not know. With PC control on, the PC's own clock and time zone are used.

## Setup and pairing

### The board does not show up over Bluetooth

- It must be in **setup mode**: the screen shows "// BLUETOOTH SETUP", its name and a six digit code. A board with Wi-Fi saved is not in setup mode; use the menu's Wi-Fi setup button, or `prov start` on the console. Setup mode ends after 10 minutes.
- Bluetooth on, on the phone or PC. On Android 12 and newer allow Nearby devices; on Android 11 and older, location must be on as well.
- The Android emulator has no Bluetooth. Windows needs a Bluetooth adapter that is switched on.

### "That is not the code"

The code is new every time setup mode starts, and a pairing code over the LAN lasts two minutes. After five wrong codes over the LAN, ask again for a new one.

### The app gets 401, or the board keeps dropping off

The board does not know this app's token.

- After a **factory reset** every paired app is forgotten. Unpair in the app (works while the board is out of reach) and set it up again.
- `tools/cloud/provision.py` rewrites the whole settings partition. Apps paired before it are forgotten, except the `APP_TOKEN` in `.env`.
- The board keeps **four** paired apps. Pairing a fifth drops the oldest.
- Pair again with a code: the Find step, pick the board, type the six digits.

### The Windows app lost its pairing after an update

From version 1.0.0 the Windows data folder is named after the publisher (`%APPDATA%\MultiX0\Orion`). The app copies the old folder's settings and keychain across on first start. If it started empty anyway, pair again with a code.

## PC control

### The board never uses the PC

Check the menu's PC card on the board: none, found or connected.

- **PC control is off** or the Orion app is closed. PC control starts with the app when it was on at exit.
- **The firewall.** Turning PC control on raises Windows' consent prompt once, to allow TCP 7331 to 7339 from the local subnet and remove Block rules left by a dismissed prompt. If you said No, PC control stays off; turn it on again to be asked again. A home network marked Public never shows the ordinary firewall prompt, which is why the app asks itself.
- **The address.** The Harness header shows the address the board was told. It must be on the board's subnet. A VPN or an unusual adapter can confuse it; turn PC control off and on with the board online so it is told again.
- **The port.** If another program holds 7331, the server moves to 7332 up to 7339 (the rule covers all of them) and tells the board. `tool/pc_harness.dart` and the app both want 7331; run one at a time.
- **No model on the PC.** The PC brain answers 503 when no provider, model or key is set in the app, and the board answers with its own model. Set one in Providers.

The board checks the PC at every wake and every 40 s; the PC card's refresh button checks at once.

### "One moment, I'm on it", then a long wait

Tasks on the PC take 10 to 60 seconds: the thinking model opens the app, looks, clicks and checks. The board keeps waiting as long as the PC shows signs of life. Under "Ask me first", a tool may be waiting for your approval on the Harness screen; there is no system notification, and after 20 s the brain tells you it is waiting.

### Orion says it did something it did not

The thinking model checks its work, and the default (GLM 5.3 Flash) is the one that was most honest about unfinished tasks in testing. A fast model on its own reports success it never checked; do not make the fast model the thinking model. Picking the original song among covers in Spotify's results is still the hardest task for every model tried.

### The board says to open the Orion app on the PC

No PC is linked, or the linked one did not answer, and the request needs the PC. Open the app on the PC with PC control on.

### Agent tasks say "no dsh"

dsh needs Node 22.19 or newer (or 24+). The first probe downloads the package through `npx`, which can take longer than the 60 s window; restart the app after it finishes. Agent tasks are optional: the UI tools handle most tasks without dsh.

## The phone brain

### Android stops answering when another app is in front

The app runs a foreground service with the notification "Orion is thinking on this phone". If the notification is missing, allow the app's notifications and exclude it from battery optimisation. On iOS the phone brain answers only while the app is open.

## Listening and the wake word

### It does not wake

- Say "Orion" at a normal speaking volume, within a few metres. The model turns down more very soft and very noisy "Orion"s than it used to, in exchange for far fewer false wakes; see [WAKEWORD.md](WAKEWORD.md#the-shipped-model).
- The log shows `gated: ...` when the model heard it but the energy gate thought it too quiet next to the noise floor.
- `ww` shows whether the pipeline runs (it stops during a turn and runs in idle and offline).
- Tap the screen or press the side button instead; the app's Talk screen works too.

### It wakes by itself

- `ww debug 1`, then leave the board; every detection's audio lands in `logs/wake_clips/` when captured with `serial_capture.py`. Listen to what woke it.
- `ww cutoff 250` makes it stricter until the next restart (the shipped 0.96 is 244 out of 255).
- TV and speech in the room are the hardest case; the model wakes about twice an hour on continuous conversation.

### The first word of the question is lost

Say the question straight after the name: the recording starts at the wake word, not after the chime. If the first word is still lost, check that the board runs the current firmware.

### "Sorry, could you say that again?" every time

The recorder heard no speech within 4 s of the wake, or speech to text came back empty. Speech starts when two 20 ms frames pass four times the noise floor and at least RMS 100: speak up, come closer, and start talking within a few seconds of the chime. `micmon 8` while you talk shows the levels (silence reads about 4 to 13, speech 40 to 180). If the room is loud, the floor rises with it.

### The error sound every time

A stage is failing. `cloud_status` shows which keys are set; `cloud_test llm`, `stt` and `tts` (or Test in the app) say which stage fails and how: `http_401` a bad key, `http_402` no credit, `http_404` a bad model, `timeout`, `unreachable`. The 30 s deadline without any progress also ends a turn with the error sound.

The most common one: a Fish account with **no API credit** answers 402 on every speech to text path, while text to speech still works on the free model, so Orion can speak but not hear. Add API credit at https://fish.audio/app/developers, or switch speech to text to another provider in the app.

## What Orion says

### It answers with an old voice or an old personality

The prompt and earcons live in the `assets` partition, which a full flash from an older build overwrites. Write the current `assets.bin` at `0x510000` again.

### The app shows a different voice id than Orion Voice

On a board that never stored a voice, `GET /api/config` reports an older default id (`81c63e6a...`) while the board actually speaks with Orion Voice. Saving the voice from the app stores Orion Voice explicitly and the two agree.

### Brackets like [laugh] are spoken or shown

They are Fish Audio voice cues. Fish performs them; the screen and the app strip them. With a non-Fish text to speech the prompt asks for none and the board removes any before speaking. If one is spoken, the text to speech is not Fish and the firmware predates tag stripping; update it.

### It answers in the wrong language

Orion answers in the language of the question; any Arabic words make it Arabic. Speech to text sometimes writes English words in Arabic letters, which can tip a mixed sentence. Speak the question in one language.

## Building and flashing

| Problem | Fix |
|---|---|
| `fatal error: opening dependency file ... No such file or directory` | The checkout path is too long for Windows. Build into a short directory: `idf.py -B C:\ob build`. |
| `MSys/Mingw is not supported` | Running ESP-IDF from Git Bash. Use `tools\idf.ps1`, which clears the MSYS variables. |
| The build ignores a change to `sdkconfig.defaults` | Delete `firmware/sdkconfig` and `sdkconfig.old`. |
| Flashing cannot connect | Hold BOOT, tap RST, release BOOT, try again. Close anything holding the port. |
| `flash.ps1` waits for the lock | Another flash or capture holds `%USERPROFILE%\.orion\flash.lock`. A lock older than 10 minutes or whose process is gone is taken over automatically. |
| The board resets whenever the serial port opens | Use `tools/serial_capture.py --no-reset`, which opens the port with DTR and RTS low. |
| Arabic typed on the console arrives empty | The console drops non-ASCII bytes. Use `ask hex:` with `tools/cloud/talk_hex.py`. |
| Console commands get lost | Too many at once. Use `tools/cloud/console_session.py`, which waits for each. |
| Flutter: missing `*.g.dart` or `*.freezed.dart` | `dart run build_runner build --delete-conflicting-outputs` |
| Windows app build fails with MSB3491 | The path is too long; build from a short path (a `subst` drive letter works). |
| Android release APK cannot reach the board | The `INTERNET` permission must be in the main manifest; it is in this repository. |
