# Fish Audio speech to text on the board's real clips: latency over a kept
# alive session, what it heard, and whether a chunked upload (the way the board
# could stream a recording while it is still being made) is accepted.
#
#   python tools/cloud/fish_asr_probe.py [--runs 5]
#
# Bills Fish API credit, about $0.0005 per clip. Never prints a key.

import argparse
import statistics
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c  # noqa: E402

CLIPS = ["ar_time", "en_france"]


def post(sess, wav, model, chunked):
    headers = {"Authorization": "Bearer " + c.env("FISH_API_KEY"), "model": model}
    t0 = time.perf_counter()
    if chunked:
        boundary = "----orionprobe"
        pre = ("--%s\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"speech.wav\"\r\n"
               "Content-Type: audio/wav\r\n\r\n" % boundary).encode()
        post_ = ("\r\n--%s--\r\n" % boundary).encode()

        def body():
            yield pre
            for i in range(0, len(wav), 3200):
                yield wav[i:i + 3200]
            yield post_
        headers["Content-Type"] = "multipart/form-data; boundary=" + boundary
        r = sess.post(c.FISH_ASR_URL, headers=headers, data=body(), timeout=60)
    else:
        r = sess.post(c.FISH_ASR_URL, headers=headers, timeout=60,
                      files={"audio": ("speech.wav", wav, "audio/wav")})
    ms = (time.perf_counter() - t0) * 1000
    return r, ms


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--model", default="transcribe-1")
    a = ap.parse_args()
    sess = requests.Session()
    sess.head(c.FISH_TTS_URL, timeout=30)
    for chunked in (False, True):
        for clip in CLIPS:
            wav = (c.REPO / "logs/test" / (clip + ".wav")).read_bytes()
            times, text = [], ""
            for _ in range(a.runs if not chunked else 2):
                r, ms = post(sess, wav, a.model, chunked)
                if r.status_code != 200:
                    print("%s%s http %d: %s" % (clip, " chunked" if chunked else "", r.status_code, r.text[:200]))
                    break
                times.append(ms)
                text = r.json().get("text", "")
            if times:
                print("fish %s %-9s%s median %5.0f ms  min %5.0f  max %5.0f  heard: %s"
                      % (a.model, clip, " chunked" if chunked else "", statistics.median(times),
                         min(times), max(times), text[:70]), flush=True)


if __name__ == "__main__":
    main()
