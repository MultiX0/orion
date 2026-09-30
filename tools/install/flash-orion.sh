#!/usr/bin/env bash
# Orion one-click installer for Linux (macOS works too).
#
# Puts the Orion firmware on a LilyGO T-CameraPlus-S3 connected by USB-C.
# Run it from a terminal:
#
#   bash flash-orion.sh
#
# Options, for people who want them:
#   --port /dev/ttyACM0   use this port instead of finding the board
#   --firmware file.bin   flash this file instead of the release
#   --dry-run             do everything except write to the board
#
# Needs no root. Everything it downloads goes to ~/.cache/orion-flasher and
# can be deleted afterwards.

set -u

FIRMWARE_URL="${ORION_FIRMWARE_URL:-https://github.com/MultiX0/orion/releases/latest/download/orion-firmware-full.bin}"
WORK_DIR="${ORION_WORK_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/orion-flasher}"
USB_VID="${ORION_USB_VID:-303a}"
WAIT_SECONDS="${ORION_WAIT_SECONDS:-90}"
# For testing without a board: a fake /sys tree, and a way to skip Python.
SYSFS="${ORION_SYSFS:-/sys}"
SKIP_PYTHON="${ORION_SKIP_PYTHON:-0}"

# Espressif's standalone esptool, used when Python is not available.
ESPTOOL_VERSION="v5.4.0"
ESPTOOL_BASE="https://github.com/espressif/esptool/releases/download/$ESPTOOL_VERSION"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=""
FIRMWARE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --port) PORT="${2:-}"; shift 2 ;;
        --firmware) FIRMWARE="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1"; exit 2 ;;
    esac
done

if [ -t 1 ]; then
    C_STEP=$'\033[36m'; C_GOOD=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_STEP=""; C_GOOD=""; C_WARN=""; C_BAD=""; C_OFF=""
fi

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
good() { printf '    %s%s%s\n' "$C_GOOD" "$*" "$C_OFF"; }
warn() { printf '    %s%s%s\n' "$C_WARN" "$*" "$C_OFF"; }
die()  { printf '\n'; for l in "$@"; do printf '%s%s%s\n' "$C_BAD" "$l" "$C_OFF"; done; exit 1; }

no_board_help() {
    say ""
    say "${1:-No Orion board was found. Things to try:}"
    say "  1. Use a different USB-C cable. Many cables only charge and carry no data."
    say "  2. Plug straight into the computer, not through a hub or a monitor."
    say "  3. Put the board in download mode: hold the BOOT button on its side,"
    say "     tap the RST button once, then let go of BOOT. Then run this again."
    say "  4. Try another USB port."
}

OS="$(uname -s)"

# ---------------------------------------------------------------------------
# Finding the board
# ---------------------------------------------------------------------------

# Prints every serial port that belongs to an Espressif USB device (VID 303a).
find_board_ports() {
    if [ "$OS" = "Darwin" ]; then
        # macOS names the ESP32-S3's built-in USB port cu.usbmodem<serial>.
        for dev in /dev/cu.usbmodem*; do
            [ -e "$dev" ] || continue
            if ioreg -r -c IOUSBHostDevice -l 2>/dev/null | grep -qi "\"idVendor\" = $((16#$USB_VID))"; then
                echo "$dev"
            fi
        done
        return
    fi
    for tty in "$SYSFS"/class/tty/ttyACM* "$SYSFS"/class/tty/ttyUSB*; do
        [ -e "$tty/device" ] || continue
        # Walk up from the USB interface to the USB device, which holds idVendor.
        dir="$(readlink -f "$tty/device")"
        while [ -n "$dir" ] && [ "$dir" != "/" ] && [ "$dir" != "." ]; do
            if [ -f "$dir/idVendor" ]; then
                vid="$(tr '[:upper:]' '[:lower:]' < "$dir/idVendor")"
                if [ "$vid" = "$USB_VID" ]; then
                    echo "/dev/$(basename "$tty")"
                fi
                break
            fi
            dir="$(dirname "$dir")"
        done
    done
}

select_board_port() {
    if [ -n "$PORT" ]; then
        good "Using the port you gave: $PORT"
        return
    fi
    local waited=0 told=0 ports count
    while :; do
        ports="$(find_board_ports)"
        count=$(printf '%s' "$ports" | grep -c . || true)
        if [ "$count" -eq 1 ]; then
            PORT="$ports"
            good "Found the board on $PORT"
            return
        fi
        if [ "$count" -gt 1 ]; then
            warn "More than one board is connected:"
            local i=1
            while read -r p; do say "      $i. $p"; i=$((i + 1)); done <<< "$ports"
            printf '    Type the number of the board to use: '
            read -r pick < /dev/tty
            PORT="$(printf '%s\n' "$ports" | sed -n "${pick}p" 2>/dev/null)"
            [ -n "$PORT" ] || die "That was not one of the numbers. Unplug the boards you do not want to use and run this again."
            return
        fi
        if [ "$waited" -ge "$WAIT_SECONDS" ]; then
            no_board_help
            die "" "Stopped: no board found."
        fi
        if [ "$told" -eq 0 ]; then
            warn "No board yet. Plug the board in with a USB-C data cable now."
            warn "Already plugged in? Hold BOOT on its side, tap RST, then let go of BOOT."
            warn "Waiting up to $WAIT_SECONDS seconds..."
            told=1
        fi
        sleep 2
        waited=$((waited + 2))
    done
}

check_port_access() {
    [ "$DRY_RUN" -eq 1 ] && return
    [ -e "$PORT" ] || return
    if [ ! -r "$PORT" ] || [ ! -w "$PORT" ]; then
        local group
        group="$(stat -c '%G' "$PORT" 2>/dev/null || echo dialout)"
        die "Your user is not allowed to use $PORT yet." \
            "This is a one-time Linux setting. Run this command, then log out and back in:" \
            "" \
            "    sudo usermod -aG $group \$USER" \
            "" \
            "Then run this installer again."
    fi
}

# ---------------------------------------------------------------------------
# Getting esptool
# ---------------------------------------------------------------------------

ESPTOOL=()

esptool_major() {
    local out
    out="$("$@" version 2>/dev/null)" || return 1
    printf '%s\n' "$out" | grep -oE '[0-9]+\.[0-9]+' | head -n 1 | cut -d. -f1
}

works() { esptool_major "$@" >/dev/null; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

download() {
    # download <url> <file>; fails on HTTP errors
    if command -v curl >/dev/null 2>&1; then
        curl -fsL --retry 2 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$2" "$1"
    else
        die "This computer has neither curl nor wget, so nothing can be downloaded." \
            "Install one of them, or put orion-firmware-full.bin next to this script."
    fi
}

get_esptool() {
    # A standalone esptool left by an earlier run
    local cached
    cached="$(find "$WORK_DIR/esptool-$ESPTOOL_VERSION" -type f -name esptool 2>/dev/null | head -n 1)"
    if [ -n "$cached" ] && works "$cached"; then
        ESPTOOL=("$cached")
        good "Using esptool from an earlier run."
        return
    fi

    local py=""
    [ "$SKIP_PYTHON" = "1" ] || for c in python3 python; do
        if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' 2>/dev/null; then
            py="$c"; break
        fi
    done

    if [ -n "$py" ]; then
        if works "$py" -m esptool; then
            ESPTOOL=("$py" -m esptool)
            good "Using the esptool that is already installed."
            return
        fi
        local venv_py="$WORK_DIR/venv/bin/python"
        if [ -x "$venv_py" ] && works "$venv_py" -m esptool; then
            ESPTOOL=("$venv_py" -m esptool)
            good "Using esptool from an earlier run."
            return
        fi
        say "    Python found. Installing esptool into a private folder (a few MB)..."
        if "$py" -m venv "$WORK_DIR/venv" >/dev/null 2>&1 &&
            "$venv_py" -m pip install --disable-pip-version-check --quiet esptool >/dev/null 2>&1 &&
            works "$venv_py" -m esptool; then
            ESPTOOL=("$venv_py" -m esptool)
            good "esptool is ready."
            return
        fi
        warn "Could not install esptool with Python. Downloading it from Espressif instead."
    else
        say "    Python is not installed. That is fine: using the esptool that Espressif publishes."
    fi

    # Espressif's standalone build, checked against the SHA256 GitHub lists for it.
    local asset sha
    case "$OS-$(uname -m)" in
        Linux-x86_64|Linux-amd64) asset="linux-amd64";   sha="61648fbae20735cabb342f2fbe8fc89b3046e1ed6f9c3e09528d837dc9a9b152" ;;
        Linux-aarch64|Linux-arm64) asset="linux-aarch64"; sha="2964fff085071c1403f2cf812a7a1d425f987f9992851a60236bbee17b6e7dcc" ;;
        Linux-armv7l|Linux-armv7*) asset="linux-armv7";   sha="ee542ac6b60aee2604289ee418fccd0ff6eead6f702b51bbe4f0e483477e31d9" ;;
        Darwin-x86_64)             asset="macos-amd64";   sha="910bb64fe39a84c792752701293c8aa294faeef229fe8705ecd6955b01db3778" ;;
        Darwin-arm64)              asset="macos-arm64";   sha="ba332671130939e2e6db90c2784488f7e62a1459b0fe3c5ec66e9a366821de7a" ;;
        *) die "Espressif does not publish esptool for this computer ($OS $(uname -m))." \
               "Install Python 3, then run this again." ;;
    esac

    local tool_dir="$WORK_DIR/esptool-$ESPTOOL_VERSION" exe
    local tarball="$WORK_DIR/esptool-$ESPTOOL_VERSION-$asset.tar.gz"
    say "    Downloading esptool $ESPTOOL_VERSION (about 70 to 85 MB, only the first time)..."
    download "$ESPTOOL_BASE/esptool-$ESPTOOL_VERSION-$asset.tar.gz" "$tarball" ||
        die "Could not download esptool from GitHub." "Check that this computer is online, then run this again."
    if [ "$(sha256_of "$tarball")" != "$sha" ]; then
        rm -f "$tarball"
        die "The esptool download is damaged or not the expected file, so it was not used." \
            "Run this again. If it keeps happening, your network may be changing downloads."
    fi
    rm -rf "$tool_dir"
    mkdir -p "$tool_dir"
    tar -xzf "$tarball" -C "$tool_dir" || die "Could not unpack esptool."
    rm -f "$tarball"
    exe="$(find "$tool_dir" -type f -name esptool | head -n 1)"
    [ -n "$exe" ] && chmod +x "$exe"
    if [ -z "$exe" ] || ! works "$exe"; then
        die "esptool was downloaded but does not start."
    fi
    ESPTOOL=("$exe")
    good "esptool is ready."
}

# ---------------------------------------------------------------------------
# Getting the firmware
# ---------------------------------------------------------------------------

read_sha_file() {
    grep -oE '[0-9a-fA-F]{64}' "$1" 2>/dev/null | head -n 1 | tr '[:upper:]' '[:lower:]'
}

find_local_firmware() {
    if [ -n "$FIRMWARE" ]; then
        echo "$FIRMWARE"
        return
    fi
    if [ -f "$SCRIPT_DIR/orion-firmware-full.bin" ]; then
        echo "$SCRIPT_DIR/orion-firmware-full.bin"
        return
    fi
    # A versioned release file, such as orion-firmware-1.0.0-full.bin. Newest first.
    ls -t "$SCRIPT_DIR"/orion-firmware-*-full.bin 2>/dev/null | head -n 1
}

BIN=""

get_firmware() {
    local local_bin expected
    if [ -n "$FIRMWARE" ] && [ ! -f "$FIRMWARE" ]; then
        die "The file $FIRMWARE does not exist."
    fi
    local_bin="$(find_local_firmware)"
    if [ -n "$local_bin" ]; then
        good "Using the firmware file $local_bin"
        expected=""
        [ -f "$local_bin.sha256" ] && expected="$(read_sha_file "$local_bin.sha256")"
        if [ -n "$expected" ]; then
            [ "$(sha256_of "$local_bin")" = "$expected" ] ||
                die "$(basename "$local_bin") does not match its checksum file." \
                    "The file is damaged or incomplete. Download it again."
            good "Checksum matches."
        else
            warn "No checksum file next to it, so it could not be checked."
        fi
        BIN="$local_bin"
        return
    fi

    BIN="$WORK_DIR/orion-firmware-full.bin"
    local sha_file="$BIN.sha256"
    rm -f "$BIN" "$sha_file"
    say "    Downloading the latest Orion firmware..."
    if ! download "$FIRMWARE_URL" "$BIN"; then
        rm -f "$BIN"
        die "Could not download the Orion firmware." \
            "Address: $FIRMWARE_URL" \
            "Check that this computer is online. If it is, the release may not be published yet:" \
            "download orion-firmware-full.bin from https://github.com/MultiX0/orion/releases," \
            "put it in the same folder as this script, and run this again."
    fi
    local size
    size=$(wc -c < "$BIN" | tr -d ' ')
    [ "$size" -ge 65536 ] || die "The downloaded firmware is only $size bytes, which is too small to be real. Try again later."
    good "Downloaded $((size / 1024)) KB."

    expected=""
    if download "$FIRMWARE_URL.sha256" "$sha_file" 2>/dev/null; then
        expected="$(read_sha_file "$sha_file")"
    fi
    if [ -n "$expected" ]; then
        if [ "$(sha256_of "$BIN")" != "$expected" ]; then
            rm -f "$BIN"
            die "The firmware download does not match its published checksum, so it was not used." \
                "Run this again. If it keeps happening, your network may be changing downloads."
        fi
        good "Checksum matches the release."
    else
        warn "The release has no checksum file, so the download could not be checked."
    fi
}

# ---------------------------------------------------------------------------
# Flashing
# ---------------------------------------------------------------------------

flash() {
    # esptool 5 renamed write_flash to write-flash and warns about the old name.
    local write="write_flash" major
    major="$(esptool_major "${ESPTOOL[@]}")"
    [ -n "$major" ] && [ "$major" -ge 5 ] && write="write-flash"
    for baud in 460800 115200; do
        local cmd=("${ESPTOOL[@]}" --chip esp32s3 --port "$PORT" --baud "$baud" "$write" 0x0 "$BIN")
        if [ "$DRY_RUN" -eq 1 ]; then
            warn "Dry run, nothing written. Would run: ${cmd[*]}"
            return 0
        fi
        say "    Writing at $baud baud. Do not unplug the board..."
        if "${cmd[@]}"; then
            return 0
        fi
        if [ "$baud" != "115200" ]; then
            warn "That did not work. Trying again more slowly."
            sleep 2
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------

say ""
say "  Orion installer"
say "  This puts the Orion software on your LilyGO T-CameraPlus-S3."
say "  It takes a few minutes. Keep the board plugged in until it says Done."
[ "$DRY_RUN" -eq 1 ] && say "  ${C_WARN}Dry run: the board will not be written.${C_OFF}"

mkdir -p "$WORK_DIR" || die "Could not create $WORK_DIR."

step "Step 1 of 4: finding your board"
select_board_port
check_port_access

step "Step 2 of 4: getting the flashing tool"
get_esptool

step "Step 3 of 4: getting the Orion firmware"
get_firmware

step "Step 4 of 4: installing Orion on the board"
if ! flash; then
    no_board_help "The board did not answer. Things to try:"
    say "  5. Close any other program that may be using the board (Arduino, a serial monitor)."
    die "" "Stopped: the firmware could not be written. Nothing is broken; you can run this again."
fi

say ""
if [ "$DRY_RUN" -eq 1 ]; then
    say "${C_GOOD}Dry run finished. Everything is ready; nothing was written.${C_OFF}"
else
    say "${C_GOOD}Done. Orion is installed.${C_OFF}"
    say "The board restarts by itself and shows a setup screen with its name and a code."
    say "If the screen stays dark, tap the RST button on the side of the board once."
    say ""
    say "Next: open the Orion app on your phone or PC and tap \"Find my Orion\"."
    say "Get the app here: https://github.com/MultiX0/orion/releases/latest"
fi
