# Board tools

Scripts for building, flashing, reading and measuring the Orion board. The Dart tools for the app (the mock board, the harness utilities, the brain eval) are in `tool/` at the repo root.

| Script | Does |
|---|---|
| `idf.ps1` | finds and activates ESP-IDF, runs `idf.py` in `firmware/` (or esptool with `--esptool`); works from PowerShell 5.1 and Git Bash |
| `flash.ps1` | the only way to flash: takes the board lock, then a full flash, `-App`, `-Bin <image> -Address <addr>` or `-Erase` |
| `port.txt` | the board's serial port, read by `flash.ps1` and the Python tools |
| `serial_capture.py` | reads the serial port for a fixed time, sends console commands, saves wake word clips; shares the lock |
| `board_session.py` | flash, reset, capture and play test clips as one locked session |
| `replay_clips.ps1` | plays wake word clips through the PC speakers and counts detections |
| `ui_shot.py` | turns a `ui shot` capture into a PNG of the board's screen |
| `cloud/provision.py` | writes the keys from `.env` into the board's settings partition |
| `cloud/*.py` | the LAN, Bluetooth and cloud measurement scripts |

How to use them: [docs/FIRMWARE.md](../docs/FIRMWARE.md#building-and-flashing), [docs/FIRMWARE_CONSOLE.md](../docs/FIRMWARE_CONSOLE.md) and [docs/TESTING.md](../docs/TESTING.md).
