# Orion installer

These scripts put the Orion firmware on a LilyGO T-CameraPlus-S3. Connect the board with a USB-C data cable, then:

- **Windows:** double-click `flash-orion.bat`.
- **Linux:** open a terminal in this folder and run `bash flash-orion.sh`. macOS should work the same way.

That is all. Each script finds the board, gets Espressif's esptool (through Python if you have it, otherwise the standalone build from Espressif's GitHub releases, checked against its published SHA256), downloads `orion-firmware-full.bin` from the latest Orion release, checks it against `orion-firmware-full.bin.sha256` when the release has one, and writes it at address `0x0`. No admin rights are needed.

Offline, or want a specific version? Put the firmware file (`orion-firmware-full.bin`, or a versioned `orion-firmware-<version>-full.bin`) in this folder, with its `.sha256` file if you have it, and the script uses it instead of downloading.

## If the board is not found

1. Try another USB-C cable. Many cables only charge.
2. Plug into the computer directly, not through a hub.
3. Hold the BOOT button on the side of the board, tap RST, let go of BOOT, and run the script again.
4. On Linux, if it says your user is not allowed to use the port, run `sudo usermod -aG dialout $USER` once (the script prints the exact group), then log out and back in.

## Options

| Windows | Linux | What it does |
|---|---|---|
| `-Port COM7` | `--port /dev/ttyACM0` | Use this port instead of looking for the board |
| `-Firmware file.bin` | `--firmware file.bin` | Flash this file instead of the release |
| `-DryRun` | `--dry-run` | Do everything except write to the board |
| `-WorkDir folder` | `ORION_WORK_DIR=folder` | Where downloads go |

Downloads are kept in `%LOCALAPPDATA%\Orion\flasher` on Windows and `~/.cache/orion-flasher` on Linux, so a second run is quick. Delete the folder whenever you like.

This writes the full image, which also clears the board's saved settings. To update a board that is already set up and keep its settings, see [docs/FIRMWARE.md](../../docs/FIRMWARE.md).
