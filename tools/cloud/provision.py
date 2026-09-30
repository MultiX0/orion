# Writes the keys from .env into the board's nvs partition, and nothing else.
#
# This is the only path a secret takes to the board. Nothing here is compiled
# into the firmware, so the .bin can be shared and the repo can be public.
#
#   python tools/cloud/provision.py              build, flash, delete the image
#   python tools/cloud/provision.py --dry-run    build and show, do not flash
#   python tools/cloud/provision.py --keep       keep the image for inspection
#
# The CSV and the .bin both hold live keys, so both are written into the system
# temp directory, never into the repo, and both are deleted in a finally block
# even if the flash fails.

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

NVS_OFFSET = "0x9000"
NVS_SIZE = 0x6000  # 24 KB, from firmware/partitions.csv

DEEPINFRA = "https://api.deepinfra.com/v1/openai"

# Config version 2, see docs/DEVICE_PROTOCOL.md: each stage has its own
# provider, URL, key and model. The .env names of version 1 still work, so an
# existing .env provisions the same board it did before:
#   FISH_API_KEY      the key for stt and tts when they are on Fish
#   DEEPINFRA_API_KEY the key for the language model, and for any stage that
#                     is on DeepInfra's OpenAI compatible API
#   FISH_VOICE_ID, FISH_TTS_MODEL, ASR_PROVIDER, ASR_MODEL, LLM_MODEL
# and the version 2 names override them: LLM_BASE_URL, LLM_API_KEY,
# STT_PROVIDER, STT_BASE_URL, STT_API_KEY, STT_MODEL, TTS_PROVIDER,
# TTS_BASE_URL, TTS_API_KEY, TTS_MODEL, TTS_VOICE.

SECRET_KEYS = {"wifi_pass", "llm_key", "stt_key", "tts_key", "app_token"}

# The volume the user chose, 0 to 100. It lives in the same partition, so a
# provision run that leaves it out resets the board to its default of 70. Stored
# as i32, the type main.c reads with orion_config_get_i32.
DEFAULT_VOLUME = 100

# Orion's voice on Fish when .env names none: "Orion Voice", designed for the
# project and unlisted, so any Fish key can use it. The firmware falls back to
# the same id.
FISH_DEFAULT_VOICE = "9a68c1d739134940a4297c996c5ca6a1"


def env(*names, default=""):
    for n in names:
        v = c.env(n, "").strip()
        if v:
            return v
    return default


def stage(prefix, prov, fish_model, openai_model, fish_voice=None):
    """(provider, url, key, model, voice) for stt or tts, v2 names first."""
    is_fish = prov == "fish"
    url = env(prefix + "_BASE_URL", default="" if is_fish else DEEPINFRA)
    key = env(prefix + "_API_KEY", "FISH_API_KEY" if is_fish else "DEEPINFRA_API_KEY")
    model = env(prefix + "_MODEL", *(["FISH_TTS_MODEL"] if (is_fish and prefix == "TTS") else []),
                *(["ASR_MODEL"] if (not is_fish and prefix == "STT") else []),
                default=fish_model if is_fish else openai_model)
    voice = env(prefix + "_VOICE", *(["FISH_VOICE_ID"] if is_fish and fish_voice else []),
                default=FISH_DEFAULT_VOICE if is_fish and fish_voice else "")
    return ("fish" if is_fish else "openai_compatible"), url, key, model, voice


def collect():
    """Reads .env. Returns (rows, missing_required). A row is (key, value, type)."""
    rows = []
    missing = []

    def put(key, value, kind="string"):
        if value != "":
            rows.append((key, value, kind))

    ssid = env("WIFI_SSID")
    if not ssid:
        missing.append("WIFI_SSID")
    put("wifi_ssid", ssid)
    put("wifi_pass", env("WIFI_PASSWORD"))
    # Normally set by the phone during Bluetooth pairing. From .env only when
    # testing the LAN API without a phone.
    put("app_token", env("APP_TOKEN"))
    put("device_name", env("DEVICE_NAME"))

    llm_key = env("LLM_API_KEY", "DEEPINFRA_API_KEY")
    llm_url = env("LLM_BASE_URL", default=DEEPINFRA)
    if not llm_key and llm_url.startswith("https://"):
        missing.append("LLM_API_KEY or DEEPINFRA_API_KEY")
    put("llm_prov", env("LLM_PROVIDER", default="deepinfra"))
    put("llm_url", llm_url)
    put("llm_key", llm_key)
    put("llm_model", env("LLM_MODEL", default="google/gemma-4-31B-it-turbo"))

    stt_prov = env("STT_PROVIDER", default="")
    if not stt_prov:
        stt_prov = "openai_compatible" if env("ASR_PROVIDER") == "deepinfra" else "fish"
    stt_prov = "fish" if stt_prov == "fish" else "openai_compatible"
    p, url, key, model, _ = stage("STT", stt_prov, "transcribe-1", "Qwen/Qwen3-ASR-1.7B")
    if not key:
        missing.append("STT_API_KEY or " + ("FISH_API_KEY" if p == "fish" else "DEEPINFRA_API_KEY"))
    put("stt_prov", p)
    put("stt_url", url)
    put("stt_key", key)
    put("stt_model", model)

    tts_prov = "fish" if env("TTS_PROVIDER", default="fish") == "fish" else "openai_compatible"
    p, url, key, model, voice = stage("TTS", tts_prov, "s2.1-pro-free", "Qwen/Qwen3-TTS",
                                      fish_voice=True)
    if not key:
        missing.append("TTS_API_KEY or " + ("FISH_API_KEY" if p == "fish" else "DEEPINFRA_API_KEY"))
    put("tts_prov", p)
    put("tts_url", url)
    put("tts_key", key)
    put("tts_model", model)
    put("tts_voice", voice)

    put("wake_phrase", env("WAKE_PHRASE", default="Orion"))
    put("vision_mode", env("VISION_MODE", default="tool"))
    volume = int(env("VOLUME", default=str(DEFAULT_VOLUME)))
    put("volume", str(max(0, min(100, volume))), "i32")
    return rows, missing


def describe(rows):
    print("keys going into nvs:")
    for key, value, kind in rows:
        if key in SECRET_KEYS:
            print("  %-12s present, %d chars, ends ...%s" % (key, len(value), value[-4:]))
        else:
            print("  %-12s %s%s" % (key, value, "  (i32)" if kind == "i32" else ""))


def write_csv(path, rows):
    lines = ["key,type,encoding,value",
             "orion,namespace,,"]
    for key, value, kind in rows:
        if "," in value or '"' in value:
            raise SystemExit("value for %s contains a comma or a quote, "
                             "nvs_partition_gen cannot take it" % key)
        lines.append("%s,data,%s,%s" % (key, kind, value))
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def find_idf_python():
    """nvs_partition_gen.py imports esp_idf_nvs_partition_gen, which is only
    installed in the IDF virtualenv, not in the system python."""
    env_root = Path.home() / ".espressif" / "python_env"
    if env_root.exists():
        for child in sorted(env_root.iterdir(), reverse=True):
            exe = child / "Scripts" / "python.exe"
            if exe.exists():
                return str(exe)
            exe = child / "bin" / "python"
            if exe.exists():
                return str(exe)
    return sys.executable


def find_nvs_tool():
    """nvs_partition_gen.py ships with ESP-IDF."""
    roots = []
    for var in ("ORION_IDF_PATH", "IDF_PATH"):
        if os.environ.get(var):
            roots.append(Path(os.environ[var]))
    roots += [Path("C:/Espressif/frameworks"), Path.home() / "esp", Path("C:/esp")]

    for root in roots:
        if not root.exists():
            continue
        hit = root / "components" / "nvs_flash" / "nvs_partition_generator" / "nvs_partition_gen.py"
        if hit.exists():
            return hit
        for child in sorted(root.glob("esp-idf*"), reverse=True):
            hit = child / "components" / "nvs_flash" / "nvs_partition_generator" / "nvs_partition_gen.py"
            if hit.exists():
                return hit
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="build but do not flash")
    ap.add_argument("--keep", action="store_true", help="do not delete the image")
    ap.add_argument("--port", default=None)
    args = ap.parse_args()

    rows, missing = collect()
    if missing:
        print("\nThese are empty in .env and the board cannot work without them:")
        for name in missing:
            print("  %s" % name)
        if "WIFI_SSID" in missing or "WIFI_PASSWORD" in missing:
            print("\nThe ESP32-S3 is 2.4 GHz only, so use a 2.4 GHz SSID.")
            print("Windows will not hand the Wi-Fi password to a script without")
            print("Location services and an admin shell, so type it into .env.")
        raise SystemExit(1)

    describe(rows)

    nvs_tool = find_nvs_tool()
    if not nvs_tool:
        raise SystemExit("nvs_partition_gen.py not found. Set IDF_PATH.")

    workdir = Path(tempfile.mkdtemp(prefix="orion_nvs_"))
    csv_path = workdir / "orion_nvs.csv"
    bin_path = workdir / "orion_nvs.bin"

    try:
        write_csv(csv_path, rows)
        cmd = [find_idf_python(), str(nvs_tool), "generate", str(csv_path),
               str(bin_path), str(NVS_SIZE)]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            # The CSV holds live keys, so only the last line of any error is
            # shown and the file itself is never printed.
            tail = (result.stderr or result.stdout).strip().splitlines()
            print("nvs_partition_gen failed: %s" % (tail[-1] if tail else "?"))
            raise SystemExit(1)

        size = bin_path.stat().st_size
        print("\nbuilt a %d byte nvs image for offset %s" % (size, NVS_OFFSET))
        if size > NVS_SIZE:
            raise SystemExit("image is bigger than the %d byte partition" % NVS_SIZE)

        if args.dry_run:
            print("dry run, not flashing")
            return

        flash = c.REPO / "tools" / "flash.ps1"
        cmd = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(flash),
               "-Bin", str(bin_path), "-Address", NVS_OFFSET]
        if args.port:
            cmd += ["-Port", args.port]
        print("flashing the nvs partition only, app untouched")
        code = subprocess.run(cmd).returncode
        if code != 0:
            raise SystemExit("flash.ps1 exited %d" % code)
        print("provisioned. Check it with the serial command: cloud_status")

    finally:
        if args.keep:
            print("kept %s, it contains live keys, delete it yourself" % workdir)
        else:
            shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
