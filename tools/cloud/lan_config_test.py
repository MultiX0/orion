"""Config version 2 over the LAN API, against a real board.

Checks /api/info (config_version, providers), GET /api/config masking, a bad
value rejected with nothing stored, a stage switch read back and tested with
POST /api/config/test, and the version 1 fish block. Keys come from .env
inside this script and are never printed; only their last four characters
are compared with the board's mask.

    python tools/cloud/lan_config_test.py [--ip 172.16.0.136] [--switch-stt]
"""
import argparse
import http.client
import json
import re
import sys
import time

from lan_api_test import REPO, find_by_beacon, get, token

DI_URL = "https://api.deepinfra.com/v1/openai"


def env(name):
    for line in (REPO / ".env").read_text(encoding="utf-8").splitlines():
        if line.startswith(name + "="):
            return line.split("=", 1)[1].strip().strip('"')
    return ""


def post(ip, path, tok, body, timeout=40):
    c = http.client.HTTPConnection(ip, 80, timeout=timeout)
    t0 = time.time()
    data = json.dumps(body).encode()
    c.request("POST", path, body=data,
              headers={"X-Orion-Token": tok, "Content-Type": "application/json"})
    r = c.getresponse()
    out = r.read()
    c.close()
    return r.status, out, round((time.time() - t0) * 1000)


def masks_ok(cfg):
    """Every secret is null or "..." plus at most four characters."""
    vals = [cfg[s]["api_key"] for s in ("llm", "stt", "tts")] + [cfg["pc"]["token"]]
    return all(v is None or re.fullmatch(r"\.\.\.[^\"]{0,4}", v) for v in vals)


def last4(key):
    return "..." + key[-4:] if key else None


def check(label, cond, detail=""):
    print(f"{'PASS' if cond else 'FAIL'} {label} {detail}")
    return cond


def test(ip, tok, stage):
    st, body, ms = post(ip, "/api/config/test", tok, {"stage": stage})
    print(f"  test {stage} -> {st} in {ms} ms: {body.decode()[:120]}")
    return st, json.loads(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ip")
    ap.add_argument("--switch-stt", action="store_true", help="stt to DeepInfra Qwen3 ASR and back")
    a = ap.parse_args()
    tok = token()
    ip = a.ip or find_by_beacon(8)[0]
    if not ip:
        sys.exit("no board")
    ok = True

    st, body, ms = get(ip, "/api/info", tok)
    info = json.loads(body)
    ok &= check("info config_version 2", info.get("config_version") == 2, f"{ms} ms")
    ok &= check("info providers", info.get("providers", {}).get("tts") == ["fish", "openai_compatible"])

    st, body, ms = get(ip, "/api/config", tok)
    cfg = json.loads(body)
    ok &= check("GET /api/config", st == 200, f"{ms} ms, {len(body)} bytes")
    ok &= check("keys masked", masks_ok(cfg))
    ok &= check("tts key mask matches .env", cfg["tts"]["api_key"] == last4(env("FISH_API_KEY")))
    before = cfg

    st, body, ms = post(ip, "/api/config", tok, {"volume": 150, "llm": {"model": "x"}})
    ok &= check("volume 150 rejected", st == 400 and b"invalid_config" in body, body.decode()[:90])
    st, body, ms = post(ip, "/api/config", tok, {"stt": {"provider": "whisper"}})
    ok &= check("unknown provider rejected", st == 400, body.decode()[:90])
    st, body, _ = get(ip, "/api/config", tok)
    ok &= check("nothing stored after 400", json.loads(body) == before)

    ok &= check("llm test ok", test(ip, tok, "llm")[1].get("ok") is True)
    st, body, ms = post(ip, "/api/config", tok, {"llm": {"model": "orion/no-such-model"}})
    cfg = json.loads(body)
    ok &= check("llm model switched", st == 200 and cfg["llm"]["model"] == "orion/no-such-model",
                f"{ms} ms")
    ok &= check("llm key kept when omitted", cfg["llm"]["api_key"] == before["llm"]["api_key"])
    ok &= check("llm test fails on the bad model", test(ip, tok, "llm")[1].get("ok") is False)
    st, body, ms = post(ip, "/api/config", tok, {"llm": {"model": before["llm"]["model"]}})
    ok &= check("llm model restored", st == 200, f"{ms} ms")
    ok &= check("llm test ok again", test(ip, tok, "llm")[1].get("ok") is True)
    ok &= check("tts test ok", test(ip, tok, "tts")[1].get("ok") is True)
    st, j = test(ip, tok, "nope")
    ok &= check("bad stage 400", st == 400)

    # Version 1 fish block: same key and voice, so nothing really changes.
    st, body, ms = post(ip, "/api/config", tok, {"fish": {"api_key": env("FISH_API_KEY"),
                                                          "voice_id": before["tts"]["voice"]},
                                                 "llm": {"system_prompt": "ignored"}})
    ok &= check("v1 fish block accepted", st == 200, f"{ms} ms")

    if a.switch_stt:
        st, body, ms = post(ip, "/api/config", tok, {"stt": {
            "provider": "openai_compatible", "base_url": DI_URL,
            "api_key": env("DEEPINFRA_API_KEY"), "model": "Qwen/Qwen3-ASR-1.7B"}})
        cfg = json.loads(body)
        ok &= check("stt switched to DeepInfra", st == 200 and
                    cfg["stt"]["provider"] == "openai_compatible", f"{ms} ms")
        ok &= check("stt test on DeepInfra", test(ip, tok, "stt")[1].get("ok") is True)
        st, body, ms = post(ip, "/api/config", tok, {"stt": {
            "provider": "fish", "base_url": None, "api_key": env("FISH_API_KEY"),
            "model": before["stt"]["model"]}})
        ok &= check("stt back on fish", st == 200, f"{ms} ms")
        ok &= check("stt test on fish", test(ip, tok, "stt")[1].get("ok") is True)

    st, body, _ = get(ip, "/api/config", tok)
    ok &= check("config as before", json.loads(body) == before)
    print("ALL PASS" if ok else "SOME FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
