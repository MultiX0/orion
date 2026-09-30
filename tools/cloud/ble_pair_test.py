"""Pairs with the board over Bluetooth LE from this PC, the way the phone does.

Drives Espressif's Unified Provisioning through the modules of ESP-IDF's own
tools/esp_prov (transport, security 1, protobuf), so what passes here passes
for any standard provisioning library on the phone. Adds the orion-pair
endpoint from docs/DEVICE_PROTOCOL.md, which esp_prov.py cannot reach because
its custom endpoint name is hard coded.

    python tools/cloud/ble_pair_test.py --name Orion-1a2b --pop 123456
    python tools/cloud/ble_pair_test.py --name Orion-1a2b --pop 123456 --wrong-first

Wi-Fi credentials come from .env and are never printed. The app token it
generates is written to logs/ble_pair_token.txt (gitignored) so the LAN API
tests can use it.
"""

import argparse
import asyncio
import json
import os
import secrets
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def find_esp_prov():
    roots = [os.environ.get("ORION_IDF_PATH"), os.environ.get("IDF_PATH")]
    roots += [str(p) for p in sorted(Path("C:/Espressif/frameworks").glob("esp-idf-*"), reverse=True)]
    for root in roots:
        if root and (Path(root) / "tools" / "esp_prov" / "esp_prov.py").exists():
            return Path(root) / "tools" / "esp_prov"
    sys.exit("esp_prov not found under ORION_IDF_PATH, IDF_PATH or C:/Espressif/frameworks")


ESP_PROV = find_esp_prov()
# esp_prov's proto package builds its protobuf modules from $IDF_PATH.
os.environ.setdefault("IDF_PATH", str(ESP_PROV.parents[1]))
sys.path.insert(0, str(ESP_PROV))
import esp_prov  # noqa: E402


def env_dict():
    env = {}
    for line in (REPO / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def read_env():
    env = {}
    for line in (REPO / ".env").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    ssid = env.get("WIFI_SSID", "")
    pwd = env.get("WIFI_PASSWORD", "")
    if not ssid:
        sys.exit("WIFI_SSID is empty in .env")
    return ssid, pwd


async def poll_until(tp, sec, wanted, timeout_s):
    """Polls prov-config status once a second. Returns (state, seconds)."""
    t0 = time.time()
    while time.time() - t0 < timeout_s:
        state = await esp_prov.get_wifi_config(tp, sec)
        if state in wanted:
            return state, round(time.time() - t0, 2)
        await asyncio.sleep(1)
    return "timeout", round(time.time() - t0, 2)


async def send_and_apply(tp, sec, ssid, pwd):
    if not await esp_prov.send_wifi_config(tp, sec, ssid, pwd):
        raise RuntimeError("prov-config set failed")
    if not await esp_prov.apply_wifi_config(tp, sec):
        raise RuntimeError("prov-config apply failed")


async def pair(tp, sec, token, device_name):
    req = json.dumps({"app_token": token, "device_name": device_name})
    enc = sec.encrypt_data(req.encode()).decode("latin-1")
    resp = await tp.send_data("orion-pair", enc)
    return json.loads(sec.decrypt_data(resp.encode("latin-1")).decode())


async def send_config(tp, sec, body, slice_len):
    """orion-config, in parts of slice_len characters. Returns the last answer."""
    text = json.dumps(body)
    chunks = [text[i:i + slice_len] for i in range(0, len(text), slice_len)]
    resp = None
    for i, chunk in enumerate(chunks, 1):
        req = json.dumps({"part": i, "parts": len(chunks), "data": chunk})
        enc = sec.encrypt_data(req.encode()).decode("latin-1")
        raw = await tp.send_data("orion-config", enc)
        resp = json.loads(sec.decrypt_data(raw.encode("latin-1")).decode())
        if i < len(chunks) and resp != {"ok": True, "part": i}:
            raise RuntimeError(f"part {i} answered {resp}")
    return resp, len(chunks)


def masked_ok(cfg):
    keys = [cfg[s]["api_key"] for s in ("llm", "stt", "tts")]
    return all(k is None or (k.startswith("...") and len(k) <= 7) for k in keys)


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True, help="BLE name shown on the board, Orion-xxxx")
    ap.add_argument("--pop", required=True, help="the six digit code on the screen")
    ap.add_argument("--wrong-first", action="store_true", help="send a wrong password first")
    ap.add_argument("--device-name", default="Orion")
    ap.add_argument("--no-scan", action="store_true")
    ap.add_argument("--config", action="store_true", help="send the .env keys over orion-config")
    a = ap.parse_args()

    ssid, pwd = read_env()
    token = secrets.token_hex(16)
    timings = {}

    t0 = time.time()
    tp = await esp_prov.get_transport("ble", a.name)
    if tp is None:
        sys.exit("could not connect over BLE; is the board in setup mode and Bluetooth on?")
    timings["ble_connect_s"] = round(time.time() - t0, 2)

    try:
        if not await esp_prov.has_capability(tp, "wifi_scan"):
            print("warning: board does not advertise wifi_scan")
        sec = esp_prov.get_security(1, 0, "", "", a.pop, False)
        t1 = time.time()
        if not await esp_prov.establish_session(tp, sec):
            sys.exit("session failed: wrong code?")
        timings["session_s"] = round(time.time() - t1, 2)

        t2 = time.time()
        resp = await pair(tp, sec, token, a.device_name)
        timings["pair_s"] = round(time.time() - t2, 2)
        print("orion-pair ->", resp)
        if not resp.get("ok"):
            sys.exit("orion-pair refused")
        (REPO / "logs").mkdir(exist_ok=True)
        (REPO / "logs" / "ble_pair_token.txt").write_text(token)
        (REPO / "logs" / "ble_pair_device.txt").write_text(json.dumps(resp))

        if a.config:
            env = env_dict()
            bad, _ = await send_config(tp, sec, {"volume": 500}, 200)
            print("orion-config bad value ->", bad)
            if bad.get("error") != "invalid_config":
                sys.exit("orion-config accepted volume 500")
            body = {"llm": {"api_key": env["DEEPINFRA_API_KEY"]},
                    "stt": {"provider": "fish", "api_key": env["FISH_API_KEY"]},
                    "tts": {"provider": "fish", "api_key": env["FISH_API_KEY"]}}
            t5 = time.time()
            cfg, parts = await send_config(tp, sec, body, 60)
            timings["config_s"] = round(time.time() - t5, 2)
            timings["config_parts"] = parts
            if "error" in cfg or not masked_ok(cfg):
                sys.exit(f"orion-config failed: {cfg.get('error')} {cfg.get('message')}")
            print("orion-config ok, keys", [cfg[s]["api_key"] for s in ("llm", "stt", "tts")])

        if not a.no_scan:
            t3 = time.time()
            aps = await esp_prov.scan_wifi_APs("ble", tp, sec)
            timings["scan_s"] = round(time.time() - t3, 2)
            hit = [x for x in (aps or []) if x["ssid"] == ssid]
            print(f"scan: {len(aps or [])} networks, target {'seen rssi %s' % hit[0]['rssi'] if hit else 'NOT seen'}")

        if a.wrong_first:
            print("sending a wrong password")
            await send_and_apply(tp, sec, ssid, "definitely-wrong-" + secrets.token_hex(2))
            state, secs = await poll_until(tp, sec, ("failed", "connected"), 40)
            timings["wrong_password_result"] = state
            timings["wrong_password_s"] = secs
            if state != "failed":
                sys.exit(f"expected failed, got {state}")

        print("sending the real credentials")
        t4 = time.time()
        await send_and_apply(tp, sec, ssid, pwd)
        state, secs = await poll_until(tp, sec, ("connected", "failed"), 40)
        timings["real_result"] = state
        timings["apply_to_connected_s"] = round(time.time() - t4, 2)
    finally:
        await tp.disconnect()

    print("timings:", json.dumps(timings))
    if timings.get("real_result") != "connected":
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
