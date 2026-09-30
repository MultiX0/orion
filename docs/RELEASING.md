# Cutting a release

Orion has three things that ship: the firmware, the app, and the wake word model (which ships inside the firmware). They are versioned separately.

| What | Version lives in | Tag |
|---|---|---|
| Firmware | `firmware/version.txt` | `fw-v<version>`, for example `fw-v1.0.0` |
| App | `version:` in `pubspec.yaml` | `v<version>` |
| Wake word model | the manifest's `evaluation.source` and the file name | shipped with the firmware |

Every release is under the PolyForm Noncommercial License 1.0.0 in `LICENSE`, with its `Required Notice` line for MultiX0. Anyone who passes Orion on must pass on that file; put it in every release.

## Firmware

1. **Set the version** in `firmware/version.txt`. It becomes the app version the board reports (`fw_version` in `/api/info`, the beacon and mDNS, and the boot line).
2. **Build clean from the defaults.** Delete `firmware/sdkconfig` and `firmware/sdkconfig.old`, so the release comes from `sdkconfig.defaults` alone and not from anyone's local tuning, then build:

```
idf.py fullclean
idf.py build
```

   Check the build has no warnings in Orion's own components.

3. **Check nothing personal is inside.** No key, password, network name, address or local path is compiled in; keys and Wi-Fi only ever come from NVS. A quick check on the images: search them for your Wi-Fi name, your key prefixes and your user name.
4. **Test it** on a factory reset board with the release checklist in [TESTING.md](TESTING.md#before-a-release).
5. **Collect the images** from `firmware/build/` into a folder under `dist/` (gitignored):

| File | From | Address |
|---|---|---|
| `bootloader.bin` | `build/bootloader/bootloader.bin` | `0x0` |
| `partition-table.bin` | `build/partition_table/partition-table.bin` | `0x8000` |
| `orion.bin` | `build/orion.bin` | `0x10000` |
| `assets.bin` | `build/assets.bin` | `0x510000` |
| `wakeword_model.bin` | `build/wakeword_model.bin` | `0x710000` |

6. **Merge the full image** for new boards:

```
python -m esptool --chip esp32s3 merge_bin --output orion-firmware-full.bin \
  --flash_mode dio --flash_freq 80m --flash_size 16MB \
  0x0 bootloader.bin 0x8000 partition-table.bin 0x10000 orion.bin \
  0x510000 assets.bin 0x710000 wakeword_model.bin
```

   `dio` in the image header is right: ESP-IDF writes DIO into the header on the S3 and the bootloader switches to QIO afterwards (`CONFIG_ESPTOOLPY_FLASHMODE_QIO` is set).

7. **`flash_args`**: copy `build/flash_args` next to the images and change its two nested paths to the flat names (`0x0 bootloader.bin`, `0x8000 partition-table.bin`), so `python -m esptool --chip esp32s3 write_flash @flash_args` works from the release folder. `esptool merge_bin -o check.bin @flash_args` must give a file identical to `orion-firmware-full.bin`.
8. **Checksums and license**: `SHA256SUMS.txt` over every `.bin` and `flash_args`, `orion-firmware-full.bin.sha256` (one line, `<hash>  orion-firmware-full.bin`) for the one-click scripts, and a copy of `LICENSE`. Both checksum files keep LF line endings: with CRLF, `sha256sum -c` fails on every name.
9. **Tag** `fw-v<version>` (annotated, `git tag -a fw-v<version> -m "Orion firmware <version>"`) and publish it as in [Publishing on GitHub](#publishing-on-github), with the flashing instructions from [GETTING_STARTED.md](GETTING_STARTED.md#1-flash-the-firmware): the full image at `0x0` for a new board, and the three parts for an update that keeps the settings.

The full image blanks the settings partition, so a board flashed with it starts Bluetooth setup again. Say so in the release notes.

## App

1. **Set the version** in `pubspec.yaml` (`version: <x.y.z>+<build>`). On Windows it becomes the exe's file version; the company (`MultiX0`), product (`Orion`) and description are in `windows/runner/Runner.rc`. Changing those renames the app's Windows data folder, which is why the app carries its old folder across on first start ([APP.md](APP.md#storage)).
2. **Regenerate and check**:

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
dart format --output=none --set-exit-if-changed .
flutter test
```

3. **Icons**, if the mark changed: `python tool/gen_icons.py` from `brand/assets/logo.png`.
4. **Build** each platform:

```
flutter build windows --release        # build\windows\x64\runner\Release\ (zip the whole folder)
flutter build apk --release            # build/app/outputs/flutter-apk/app-release.apk
flutter build ipa --release            # needs a signing team in Xcode
```

   Build Windows from a short path; a long one fails with MSB3491.

   Then make the Windows builds work on a PC that has never had the Visual C++ Redistributable: copy `msvcp140.dll`, `vcruntime140.dll` and `vcruntime140_1.dll` from Visual Studio's `VC\Redist\MSVC\<ver>\x64\Microsoft.VC145.CRT` into the `Release` folder before zipping it, and build the setup program with [Inno Setup](https://jrsoftware.org/isinfo.php) 6.3 or later:

```
ISCC /DAppVersion=<version> /DRedistDir="<that CRT folder>" windows\installer\orion.iss
```

   It writes `build\installer\Orion-<version>-windows-x64-setup.exe`, which installs Orion for the current user without admin rights, adds it to the Start menu and uninstalls cleanly from Settings. It is not code signed, so SmartScreen shows "Windows protected your PC" until the file builds a reputation; *More info*, then *Run anyway*.

   The Android build compiles the full path of the generated plugin registrant into `libapp.so`, so an APK built under your home folder carries your user name. Build it from a short path on the same drive, for example a junction (`mklink /J C:\orb <checkout>`); a `subst` drive breaks the Kotlin incremental cache.

5. **Test** against a real board, Bluetooth setup included, on each platform you ship.
6. **Name and check the builds**: `Orion-<version>-android.apk`, `Orion-<version>-windows-x64-setup.exe`, `Orion-<version>-windows-x64.zip` (the whole `Release` folder, with `LICENSE` and the three runtime DLLs inside), and `SHA256SUMS.txt` over all three, with LF line endings. `aapt2 dump badging` on the APK and the file version of `orion.exe` must both say `<version>`.
7. **Tag** `v<version>` (annotated, `git tag -a v<version> -m "Orion <version>"`) and publish it as in [Publishing on GitHub](#publishing-on-github), with the builds, the `LICENSE` and the notes.

## Publishing on GitHub

The repository is https://github.com/MultiX0/orion and the project website is https://www.joinorion.io. The one-click scripts in `tools/install/` depend on exact names:

| The scripts fetch | From |
|---|---|
| `flash-orion.ps1` (the `.bat` fetches it when it is not next to it) | `https://raw.githubusercontent.com/MultiX0/orion/main/tools/install/flash-orion.ps1` |
| `orion-firmware-full.bin` | `https://github.com/MultiX0/orion/releases/latest/download/orion-firmware-full.bin` |
| `orion-firmware-full.bin.sha256` | the same address with `.sha256` added |

The README and the website also send people to `releases/latest` for the app. So the release marked **Latest** must carry the newest full image with its `.sha256`, the three flash scripts and the newest app builds. GitHub picks Latest by date and version unless told, and both tags usually sit on the same commit, so always say it: `--latest` on the release that should be Latest, `--latest=false` on the other. A later firmware-only release is marked Latest and carries the current app builds too; a later app-only release carries the current full image. Keep the repository public, or none of these addresses work for anyone else.

What goes on which release (the two `SHA256SUMS.txt` files have the same name, so each goes on its own release):

| Release | Assets |
|---|---|
| `v<version>`, Latest | `Orion-<version>-android.apk`, `Orion-<version>-windows-x64-setup.exe`, `Orion-<version>-windows-x64.zip`, the app `SHA256SUMS.txt`, `orion-firmware-full.bin`, `orion-firmware-full.bin.sha256`, `flash-orion.bat`, `flash-orion.ps1`, `flash-orion.sh`, `LICENSE` |
| `fw-v<version>`, not Latest | `orion-firmware-full.bin`, `orion-firmware-full.bin.sha256`, `bootloader.bin`, `partition-table.bin`, `orion.bin`, `assets.bin`, `wakeword_model.bin`, `flash_args`, the firmware `SHA256SUMS.txt`, `flash-orion.bat`, `flash-orion.ps1`, `flash-orion.sh`, `LICENSE` |

Push `main` and the two tags, then create the firmware release first and the app release last, from the folder that holds `app/`, `firmware/` and `flash/`:

```
git push -u origin main
git push origin v<version> fw-v<version>

gh release create fw-v<version> --verify-tag --latest=false --title "Orion firmware <version>" --notes-file RELEASE_NOTES.md \
  firmware/orion-firmware-full.bin firmware/orion-firmware-full.bin.sha256 firmware/bootloader.bin \
  firmware/partition-table.bin firmware/orion.bin firmware/assets.bin firmware/wakeword_model.bin \
  firmware/flash_args firmware/SHA256SUMS.txt flash/flash-orion.bat flash/flash-orion.ps1 flash/flash-orion.sh LICENSE

gh release create v<version> --verify-tag --latest --title "Orion <version>" --notes-file RELEASE_NOTES.md \
  app/Orion-<version>-android.apk app/Orion-<version>-windows-x64-setup.exe app/Orion-<version>-windows-x64.zip app/SHA256SUMS.txt \
  firmware/orion-firmware-full.bin firmware/orion-firmware-full.bin.sha256 \
  flash/flash-orion.bat flash/flash-orion.ps1 flash/flash-orion.sh LICENSE
```

On the website instead: Releases, *Draft a new release*, pick the existing tag, drop the files in, and tick or untick *Set as the latest release* as above.

Then check it the way a stranger would:

```
curl -fsSLO https://github.com/MultiX0/orion/releases/latest/download/orion-firmware-full.bin
curl -fsSLO https://github.com/MultiX0/orion/releases/latest/download/orion-firmware-full.bin.sha256
sha256sum -c orion-firmware-full.bin.sha256
```

And the whole Windows path without a board, from an empty folder in `cmd`: download the `.bat` from its raw address and run `flash-orion.bat -DryRun -NoPause -Port COM99`. It must fetch `flash-orion.ps1`, download the firmware, print `Checksum matches the release.` and finish the dry run. On Linux: `bash <(curl -fsSL https://raw.githubusercontent.com/MultiX0/orion/main/tools/install/flash-orion.sh) --dry-run --port /dev/ttyACM0`.

## Wake word model

1. Train and measure it as in [WAKEWORD.md](WAKEWORD.md#retraining). Fill the manifest's `evaluation` block with every measure, side by side with the model it replaces.
2. Keep `author: "MultiX0"` and `website` in the manifest.
3. Copy the pair into `wakeword/models/` and `firmware/components/orion_wakeword/models/` as `orion.*`, keeping the previous pair under its own name for rollback.
4. Release it with the next firmware.

## Docs

Update these docs in the same change as the code they describe. A release is a good moment to check that every command, path, port and number in them still matches.
