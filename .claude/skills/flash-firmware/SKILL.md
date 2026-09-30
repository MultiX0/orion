---
name: flash-firmware
description: Build the Orion firmware with ESP-IDF 5.5.5 and write it to a LilyGO T-CameraPlus-S3 board safely, then confirm on the serial console that the new build is the one running. Use when asked to build, flash, update or test firmware on the board, or to write only the assets (system prompt, earcons), the wake word model or the keys.
---

# Build and flash the firmware

The board is shared hardware and people may be near it. Ask before you flash or play sound, and never open the serial port except through the repo's tools.

## 1. Before you start

1. Confirm the user wants the board flashed now, and which port it is on. The port lives in `tools/port.txt` (Windows) or is passed with `-Port COMx` or `-p /dev/ttyACM0`.
2. If `firmware/sdkconfig.defaults` changed since the last build (yours or a merge), delete `firmware/sdkconfig`. An existing `sdkconfig` wins over the defaults and silently keeps old settings.
3. Decide what has to be written:

| Changed | Write |
|---|---|
| Code in `firmware/main` or `firmware/components` | the app partition only (default) |
| `firmware/assets/` (system prompt, earcons) | the assets partition |
| The wake word model | the model partition |
| `partitions.csv`, the bootloader, or a new board | everything |
| Keys or Wi-Fi on a dev board with no app | NVS through `tools/cloud/provision.py` |

Writing only what changed keeps the board's settings and avoids bringing back an older prompt or model from your branch.

## 2. Build

Windows, from the repo root (PowerShell or Git Bash):

```
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build
```

From a deep checkout path (nested worktrees), build into a short directory, or esp-tflite-micro's object paths pass the 260 character limit ("opening dependency file ... No such file or directory"):

```
powershell -ExecutionPolicy Bypass -File tools\idf.ps1 -B C:\ob build
```

Linux:

```
. ~/esp/esp-idf/export.sh
cd firmware && idf.py build
```

The build must end with "Project build complete" and add no new warnings in Orion's own code. It produces `orion.bin` (app), `assets.bin` and `wakeword_model.bin` in the build directory. To build with another wake word model: `idf.py -D ORION_WAKE_MODEL=<path without extension> build`.

## 3. Flash

Windows, always through `tools/flash.ps1`: it takes the board lock, waits up to 15 minutes for it, and releases it. Replace `firmware\build` with your `-B` directory if you used one.

```
powershell -ExecutionPolicy Bypass -File tools\flash.ps1 -Bin firmware\build\orion.bin -Address 0x10000            # app
powershell -ExecutionPolicy Bypass -File tools\flash.ps1 -Bin firmware\build\assets.bin -Address 0x510000          # assets
powershell -ExecutionPolicy Bypass -File tools\flash.ps1 -Bin firmware\build\wakeword_model.bin -Address 0x710000  # model
powershell -ExecutionPolicy Bypass -File tools\flash.ps1                                                           # everything
```

The last form (and `-App`, `-Erase`) loses the port on the way to `idf.py` (Windows PowerShell binds `-p` to its own `-PipelineVariable`), so idf.py picks the port itself. With more than one serial device attached, write each partition with the `-Bin` forms, which pass the port explicitly.

`powershell -ExecutionPolicy Bypass -File tools\cloud\build_flash_app.ps1` builds into `C:\ocl_build` and writes the app only if the build succeeded.

Linux:

```
idf.py -p /dev/ttyACM0 app-flash
python -m esptool --chip esp32s3 -p /dev/ttyACM0 write_flash 0x510000 build/assets.bin
python -m esptool --chip esp32s3 -p /dev/ttyACM0 write_flash 0x710000 build/wakeword_model.bin
idf.py -p /dev/ttyACM0 flash
```

Keys on a dev board without the app (replaces all of NVS from `.env`, never prints the keys):

```
python tools/cloud/provision.py --dry-run
python tools/cloud/provision.py
```

If flashing cannot connect: hold BOOT, tap RST, release BOOT, run it again. If `flash.ps1` waits on the lock, something else is using the board. Do not delete the lock file by hand; the script takes over a lock whose holder process is gone or that is over 10 minutes old.

## 4. Confirm it runs

Windows:

```
python tools/serial_capture.py --seconds 25 --out logs/boot.txt
python tools/serial_capture.py --seconds 8 --no-reset --send "volume 0" --send "heap" --out logs/heap.txt
```

Check in `logs/boot.txt`:

- the `App version` line matches your build (another process may have flashed in between);
- the `reset reason` is `power on` or `software restart`, not `panic` or a watchdog;
- each `after <subsystem> heap int` line, and that no subsystem logs `failed`;
- `system prompt loaded, <n> bytes` (not "using the built in prompt"), and the wake word model line with its cutoff.

A typed turn exercises the whole loop at volume 0, with nobody hearing it:

```
python tools/cloud/console_session.py --out logs/turn.txt "vol 0" "ask What is the capital of Jordan?" "heap"
```

Read the `turn_perf` line for stage timings and `heap_int` after the turn. For a flash-then-test sequence that nothing can interrupt, use `python tools/board_session.py --app <build dir>/orion.bin --out logs/run.txt --seconds 60`.

On Linux a person can watch with `idf.py -p /dev/ttyACM0 monitor` (Ctrl+] to leave). An automated agent must not run it: it never returns.

## 5. Report

Say what was built, which partitions were written, the `App version` seen, heap numbers before and after if memory changed, and anything that failed with the exact log line.
