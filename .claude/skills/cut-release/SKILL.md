---
name: cut-release
description: Cut a release of the Orion firmware (fw-vX.Y.Z, the per-partition images plus one merged full image, checksums and LICENSE) or of the Flutter app (vX.Y.Z), with a clean build from the committed config, a check that no secret or local detail is inside, a test on hardware, the docs updated and an annotated tag. Use when asked to release, tag or package a version.
---

# Cut a release

Releases are built from committed files only, carry no key, password, network name, address or local path, and ship the `LICENSE` file (PolyForm Noncommercial 1.0.0, with its required notice). Ask before pushing tags or publishing anything.

Tags in use: `fw-vX.Y.Z` for firmware, `vX.Y.Z` for the app. Release commits: `release: firmware X.Y.Z`, `release: app X.Y.Z`.

## Firmware

1. Start from a clean tree on the branch being released, with everything merged and `git status` empty.

2. Set the version in `firmware/version.txt` (ESP-IDF reads it into the app description; the board prints it at boot and in `/api/info`).

3. Build from `sdkconfig.defaults` alone, in a fresh build directory, so no local `sdkconfig` can leak in:

   ```
   rm -f firmware/sdkconfig
   powershell -ExecutionPolicy Bypass -File tools\idf.ps1 -B C:\orion_release build     # Windows
   cd firmware && idf.py -B /tmp/orion_release build                                     # Linux
   ```

   The build must finish with no warnings in Orion's own code (warnings from managed components are theirs).

4. Collect the images into `dist/` (gitignored):

   | From the build directory | Address |
   |---|---|
   | `bootloader/bootloader.bin` | `0x0` |
   | `partition_table/partition-table.bin` | `0x8000` |
   | `orion.bin` | `0x10000` |
   | `assets.bin` | `0x510000` |
   | `wakeword_model.bin` | `0x710000` |

   Copy `LICENSE` in as well.

5. Merge the full image, from `dist/` (`pip install esptool` if it is not on your PATH outside ESP-IDF):

   ```
   python -m esptool --chip esp32s3 merge_bin --output orion-firmware-full.bin --flash_mode dio --flash_freq 80m --flash_size 16MB 0x0 bootloader.bin 0x8000 partition-table.bin 0x10000 orion.bin 0x510000 assets.bin 0x710000 wakeword_model.bin
   ```

   The full image blanks the NVS area, so a board flashed with it starts in setup mode. That is intended for a new board and wrong for an update.

6. Check that nothing private is inside. This prints only the names of `.env` entries whose values appear in an image, never the values:

   ```
   python -c "import pathlib;env=dict(l.split('=',1) for l in pathlib.Path('.env').read_text(encoding='utf-8').splitlines() if '=' in l and not l.lstrip().startswith('#'));bins=[p.read_bytes() for p in pathlib.Path('dist').glob('*.bin')];vals={k:v.strip().strip(chr(34)) for k,v in env.items()};print('found:',[k for k,v in vals.items() if len(v)>=6 and any(v.encode() in b for b in bins)] or 'nothing')"
   ```

   Also search the images for your user name and home path. Anything found stops the release.

7. Checksums, from `dist/`:

   ```
   sha256sum *.bin LICENSE > SHA256SUMS.txt                                        # Linux or Git Bash
   $lines = Get-FileHash *.bin, LICENSE -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLower())  $(Split-Path $_.Path -Leaf)" }; [IO.File]::WriteAllText("$PWD\SHA256SUMS.txt", ($lines -join "`n") + "`n")   # PowerShell
   ```

   Keep LF line endings: with CRLF, `sha256sum -c` reads every name with a trailing `\r` and fails. `Set-Content` writes CRLF.

8. Test on hardware, with the owner's permission, since both steps rewrite the board:
   - New board path: write the full image at `0x0`. The board must boot into setup mode with a code on screen, pair and set up from the app over Bluetooth, and answer a question.
   - Update path: on a board that is already set up, write the three parts as `docs/FIRMWARE.md` shows. Wi-Fi, keys and paired apps must survive.
   - In both, the boot capture shows the new version, `reset reason` is clean, and `system prompt loaded` and the wake word model line appear. Say "Orion" once in the room.

9. Update the Releases table in `docs/FIRMWARE.md` (version, date, one line of notes) and anything the release changed in flashing or setup.

10. Commit and tag:

    ```
    git add firmware/version.txt docs/FIRMWARE.md
    git commit -m "release: firmware X.Y.Z"
    git tag -a fw-vX.Y.Z -m "Orion firmware X.Y.Z, <one line on what is new>"
    ```

    Push the tag and publish only when the owner asks, for example `gh release create fw-vX.Y.Z dist/* --title "Orion firmware X.Y.Z" --notes-file <notes>`.

## App

1. Set `version:` in `pubspec.yaml` (`X.Y.Z+build`). The Windows file version and the Android version name and code come from it.

2. Clean checks:

   ```
   flutter pub get
   dart run build_runner build --delete-conflicting-outputs
   flutter analyze
   dart format .
   flutter test
   ```

3. Build what is being released, from a short checkout path:

   ```
   flutter build windows --release        # build/windows/x64/runner/Release/
   flutter build apk --release            # build/app/outputs/flutter-apk/app-release.apk
   flutter build linux --release          # build/linux/x64/release/bundle/
   ```

   The Android build compiles the full path of the generated plugin registrant into `libapp.so`, so an APK built under your home folder carries your user name. Build it from a short path on the same drive, for example a junction (`mklink /J C:\orb <checkout>`); a `subst` drive breaks the Kotlin incremental cache.

   The Android release build is signed with the debug key (`android/app/build.gradle.kts`). A store release needs its own signing config first; say so rather than publishing a debug-signed APK as final.

4. Smoke test each build against the mock (`dart run tool/mock_device/main.dart`) and, when one is available, a real board: onboarding, a typed turn in Talk, the camera, Settings, and on Windows the Harness with PC control on.

5. Update `README.md` and the docs for anything user-visible, and replace screenshots in `docs/screenshots/` if the screens changed (taken against the mock, with no real keys, names or addresses visible).

6. Commit `release: app X.Y.Z` and tag `git tag -a vX.Y.Z -m "<one line on what is new>"`. Push and publish only when asked.
