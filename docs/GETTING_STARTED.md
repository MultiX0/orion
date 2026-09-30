# Getting started

From a bare board to "Orion, what time is it?". About half an hour if you already have the keys.

## What you need

**Hardware**

- A **LilyGO T-CameraPlus-S3 V1.2**: ESP32-S3 with 16 MB flash and 8 MB PSRAM, OV2640 camera, 1.3 inch 240x240 ST7789 touch screen (CST816S), MP34DT05 PDM microphone, MAX98357A amplifier, SY6970 power chip. Earlier revisions (V1.0, V1.1) use different pins and will not work with this firmware as it is.
- The **speaker** that plugs into the socket marked "Audio" on the back of the board. The firmware is tuned for the FUET FS2112 (8 ohm, 1 W, 20.8 x 11.8 x 7 mm) that LilyGO sells with it.
- The board's **Wi-Fi antenna** on its IPEX connector.
- A **USB-C data cable** (not a charge-only one) and a USB power source. See "Power" below: a weak port makes the board reset when it speaks loudly.
- Optional: the printed case from [CASE.md](CASE.md).

**Accounts and keys**

- A **Fish Audio** API key from https://fish.audio (the app has a "Get your Fish Audio API key" button). Text to speech on the free `s2.1-pro-free` model costs nothing. Speech to text on Fish bills API credit separately: $0.36 per hour of audio, so $1 is about 2.8 hours of listening, or about 2,500 questions of 4 seconds. The account needs at least $1 of API credit for Orion to hear you.
- A key for a **language model** with an OpenAI compatible API. The default is DeepInfra (Gemma 4 31B to answer, GLM 5.3 Flash for tasks on the PC). OpenAI, Anthropic, Groq, OpenRouter, Ollama and any custom endpoint work too. See [PROVIDERS.md](PROVIDERS.md).

**A device to set it up with**

- An Android phone or a Windows PC with Bluetooth, running the Orion app. iOS is set up in the same code but has not been built or tried on a device yet. The board has no Wi-Fi yet, so the first setup is over Bluetooth. The phone or PC must be on a 2.4 GHz Wi-Fi network the board can join (the ESP32-S3 has no 5 GHz radio).

## 1. Flash the firmware

Connect the board with the USB-C data cable.

### The easy way

- **Windows 10 or 11:** download `tools/install/flash-orion.bat` and double-click it. If SmartScreen says it protected your PC, choose *More info*, then *Run anyway*.
- **Linux or macOS:** `bash <(curl -fsSL https://raw.githubusercontent.com/MultiX0/orion/main/tools/install/flash-orion.sh)`. macOS is supported by the same script but has been tested less than Linux.

The installer finds the board, gets esptool (through Python if you have it, otherwise Espressif's standalone build, so Python is not needed), downloads `orion-firmware-full.bin` from the latest release, checks it against its `.sha256`, and writes it at `0x0`. It needs no admin rights. Details and options: [`tools/install/README.md`](../tools/install/README.md).

### From a release

Each firmware release has one full image and the separate parts:

| File | Address | What it is |
|---|---|---|
| `orion-firmware-full.bin` | `0x0` | Everything in one image, for a new board. It also blanks the settings. The one-click scripts in `tools/install/` download this exact name, with its `.sha256`. |
| `bootloader.bin` | `0x0` | Second stage bootloader |
| `partition-table.bin` | `0x8000` | Partition table |
| `orion.bin` | `0x10000` | The application |
| `assets.bin` | `0x510000` | Earcons and the system prompt |
| `wakeword_model.bin` | `0x710000` | The "Orion" wake word model |
| `SHA256SUMS.txt` | | Checksums |
| `LICENSE` | | The license, with its required notice |

No key, password or address is built into any of them.

With esptool (`pip install esptool`):

```
python -m esptool --chip esp32s3 --baud 460800 write_flash 0x0 orion-firmware-full.bin
```

Or in Chrome or Edge with Espressif's web flasher, https://espressif.github.io/esptool-js/: connect, set the address to `0x0`, pick the full image, program.

If the port does not appear or the flash cannot connect: hold **BOOT**, tap **RST**, release **BOOT**, and try again. Both buttons are on the right edge of the board.

### From source

Install ESP-IDF v5.5.5, then from `firmware/`:

```
idf.py build
idf.py -p <port> flash
```

On Windows the repo has wrappers that find ESP-IDF and serialise access to the port: `powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build` and `tools\flash.ps1`. See [FIRMWARE.md](FIRMWARE.md#building-and-flashing).

## 2. Get the app

Download it from the [latest release](https://github.com/MultiX0/orion/releases/latest): `Orion-<version>-android.apk` for Android, or `Orion-<version>-windows-x64.zip` for Windows (unzip it anywhere and run `orion.exe`).

Or build it yourself. The app is built from this repository with Flutter (stable channel, Dart 3.12 or newer). From the repo root:

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows            # or: flutter run -d <android device id>
```

For an installable Android package: `flutter build apk --release`, then `adb install -r build/app/outputs/flutter-apk/app-release.apk`. Windows: `flutter build windows --release`. Details for every platform are in [APP.md](APP.md#building).

## 3. Set it up

Power the board. With no Wi-Fi saved it goes straight into **setup mode**: the screen says to open the Orion app, shows the board's name (`Orion-a1b2`) and a six digit code.

Open the app and follow it:

1. **Welcome.** "Find my Orion".
2. **Find.** Boards already on your network appear as they are found. A new board is not on the network yet: under "Not on the network yet", choose **A new Orion**. Allow the Bluetooth permission (Nearby devices on Android 12 and newer; location as well on Android 11 and older). Pick `Orion-<last4>`.
3. **Code.** Type the six digits from the board's screen.
4. **Brain and voice.** Your keys, sent to the board over the encrypted Bluetooth session. It opens with the defaults filled in: DeepInfra for the language model, Fish Audio for listening and speaking, Orion Voice. Paste the keys, press "Later" to do it afterwards from Settings, or change any stage.
5. **Wi-Fi.** The board scans and shows the networks it can hear, strongest first. Pick yours (or "Hidden network") and type the password. A wrong password says so and lets you try again without starting over.
6. **Found on your network.** The board joins, turns Bluetooth off and starts its voice loop. The app finds it on the LAN and shows the "Brain and voice" step again, now with a working **Test** for each stage.
7. **Hands** (Windows only). Whether Orion may use this PC: Off, Ask me first, or Act on your own. See [HARNESS.md](HARNESS.md).
8. **Ready.**

Say **"Orion"**. The star lights up and listens. Ask something.

The two small dots on the board's idle screen show whether the phone app and the PC app are linked right now. The board works on its own without either; a linked PC or phone adds control of that device, the web and memory of the conversation.

### A second app, or a reinstall

A board that is already on the network pairs with a code: in the app's Find step, pick the board. It shows six digits on its screen for two minutes; type them. Up to four apps stay paired at once, so a phone and a PC can both hold the same board.

## Power

Once flashed the board needs no computer. Any USB-C power works: a phone charger or a power bank.

- The speaker draws current in bursts. A weak laptop port can sag under a loud, dense phrase and reset the board mid sentence. The firmware plays the voice as Fish sends it, without extra make-up gain, which keeps the draw low; if the board still resets while speaking, use a wall charger. The boot log names the reason for the last reset (`reset reason: brownout` means the supply).
- Some power banks switch off when the current is low. If the board goes dark after a while on a power bank, turn on its low-current mode or use a charger.
- The USB console drops its output when nothing is listening, so it never holds the board up. After a crash the board restarts by itself.

## Updating a board

Write only the application, assets and model, so the settings (Wi-Fi, keys, paired apps, volume) stay:

```
python -m esptool --chip esp32s3 --baud 460800 write_flash 0x10000 orion.bin 0x510000 assets.bin 0x710000 wakeword_model.bin
```

The full image would erase the settings, and the board would start setup again.

## Moving and resetting

- **A new Wi-Fi network.** Open the board's menu (the small round button in the top left corner of the screen, or a long press anywhere) and tap **إعداد الواي فاي** (Wi-Fi setup) on the network card. The board restarts in setup mode; in the app go to Settings, Change Wi-Fi. While the board is still online, the app can also move it directly over the LAN. A board that boots somewhere its saved network never answers goes into setup mode by itself after 30 s.
- **Factory reset.** In the menu, scroll to the reset card, tap **امسح كل شي**, then tap again within 4 seconds to confirm. It erases every setting: Wi-Fi, keys, paired apps, volume. The board restarts in setup mode, as on the first start. In the app, unpair the old board from Settings.

## Next

- [USING.md](USING.md): what Orion does day to day.
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md): when something does not work.
