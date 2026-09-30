# Where does a voice turn spend its time on the cloud side? Times each stage
# from the PC over kept-alive sessions, the way the board calls them, several
# runs each, so board numbers can be split into "the server" and "the board".
#
#   python tools/cloud/latency_probe.py [--runs 6] [--only asr,llm,tts]
#
# Never prints a key.

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c  # noqa: E402

CLIPS = [c.REPO / "logs/test/ar_time.wav", c.REPO / "logs/test/en_france.wav"]
QUESTIONS = ["قديش الساعة بعمان هلأ؟", "What is the capital of France?"]
FIRST_PIECE = "أهلاً! الساعة الآن الثالثة عصراً في عمّان."
LOOK_TOOL = [{"type": "function", "function": {
    "name": "look",
    "description": "Take a picture with the camera and look at what is in front of the device. "
                   "Call this whenever the user asks about something you can see.",
    "parameters": {"type": "object", "properties": {}}}}]


def summary(label, xs):
    xs = sorted(xs)
    p90 = xs[min(len(xs) - 1, int(round(0.9 * (len(xs) - 1))))]
    print("%-44s median %6.0f ms  min %6.0f  p90 %6.0f  max %6.0f  (n=%d)"
          % (label, statistics.median(xs), xs[0], p90, xs[-1], len(xs)), flush=True)


def asr(sess, runs, model, chunked=False):
    auth = {"Authorization": "Bearer " + c.env("DEEPINFRA_API_KEY")}
    for clip in CLIPS:
        wav = clip.read_bytes()
        times = []
        text = ""
        for _ in range(runs):
            t0 = time.perf_counter()
            if chunked:
                # A generator body goes out with Transfer-Encoding: chunked, the
                # way the board would stream a recording while it is still coming.
                boundary = "----orionprobe"
                pre = ("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.wav\"\r\n"
                       "Content-Type: audio/wav\r\n\r\n" % boundary).encode()
                post = ("\r\n--%s\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n%s\r\n--%s--\r\n"
                        % (boundary, model, boundary)).encode()

                def body():
                    yield pre
                    for i in range(0, len(wav), 3200):
                        yield wav[i:i + 3200]
                    yield post
                r = sess.post(c.DEEPINFRA_STT_URL, data=body(), timeout=60,
                              headers={**auth, "Content-Type": "multipart/form-data; boundary=" + boundary})
            else:
                r = sess.post(c.DEEPINFRA_STT_URL, headers=auth, timeout=60,
                              files={"file": ("speech.wav", wav, "audio/wav")}, data={"model": model})
            times.append((time.perf_counter() - t0) * 1000)
            if r.status_code != 200:
                print("  %s http %d: %s" % (clip.name, r.status_code, r.text[:200]))
                break
            text = r.json().get("text", "")
        if times:
            summary("asr %s %s%s" % (model.split("/")[-1], clip.stem, " chunked" if chunked else ""), times)
            print("    heard: %s" % text[:80], flush=True)


def llm(sess, runs, tools, prompt, model=None):
    auth = {"Authorization": "Bearer " + c.env("DEEPINFRA_API_KEY"), "Content-Type": "application/json"}
    model = model or c.env("LLM_MODEL", "google/gemma-4-31B-it-turbo")
    first_byte, first_text, total, reasoning = [], [], [], 0
    for i in range(runs):
        body = {"model": model, "stream": True, "max_tokens": 200, "temperature": 0.6,
                "messages": [{"role": "system", "content": prompt},
                             {"role": "user", "content": QUESTIONS[i % 2]}]}
        if tools:
            body["tools"] = LOOK_TOOL
            body["tool_choice"] = "auto"
        t0 = time.perf_counter()
        r = sess.post(c.DEEPINFRA_URL, headers=auth, data=json.dumps(body), stream=True, timeout=60)
        fb = ft = None
        for line in r.iter_lines():
            if fb is None:
                fb = (time.perf_counter() - t0) * 1000
            if not line.startswith(b"data: ") or line == b"data: [DONE]":
                continue
            d = json.loads(line[6:])
            if not d.get("choices"):
                continue
            delta = d["choices"][0].get("delta", {})
            if delta.get("reasoning_content"):
                reasoning += 1
            if ft is None and delta.get("content"):
                ft = (time.perf_counter() - t0) * 1000
        total.append((time.perf_counter() - t0) * 1000)
        first_byte.append(fb or 0)
        first_text.append(ft or total[-1])
    tag = "llm %s prompt %d chars%s" % (model.split("/")[-1], len(prompt), " +tools" if tools else "")
    summary(tag + " first byte", first_byte)
    summary(tag + " first text", first_text)
    summary(tag + " total", total)
    if reasoning:
        print("    reasoning chunks seen: %d" % reasoning)


def tts(sess, runs, sample_rate):
    model = c.env("FISH_TTS_MODEL", c.TTS_MODEL)
    headers = {"Authorization": "Bearer " + c.env("FISH_API_KEY"), "model": model,
               "Content-Type": "application/json"}
    body = {"text": FIRST_PIECE, "format": "pcm", "sample_rate": sample_rate, "latency": "balanced",
            "reference_id": c.env("FISH_VOICE_ID")}
    first, total = [], []
    for _ in range(runs):
        t0 = time.perf_counter()
        r = sess.post(c.FISH_TTS_URL, headers=headers, data=json.dumps(body), stream=True, timeout=60)
        f = None
        for chunk in r.iter_content(2048):
            if f is None and chunk:
                f = (time.perf_counter() - t0) * 1000
        total.append((time.perf_counter() - t0) * 1000)
        first.append(f or total[-1])
        if r.status_code != 200:
            print("  tts http %d" % r.status_code)
            break
    summary("tts %s %d Hz first audio" % (model, sample_rate), first)
    summary("tts %s %d Hz total" % (model, sample_rate), total)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=6)
    ap.add_argument("--only", default="asr,llm,tts")
    ap.add_argument("--asr-models", default="Qwen/Qwen3-ASR-1.7B")
    ap.add_argument("--llm-models", default="", help="comma separated; empty means LLM_MODEL from .env")
    a = ap.parse_args()
    only = a.only.split(",")
    sess = requests.Session()
    prompt = c.system_prompt()
    if "asr" in only:
        for m in a.asr_models.split(","):
            sess.post(c.DEEPINFRA_STT_URL, timeout=30)  # warm the socket, the board prewarms too
            asr(sess, a.runs, m)
        asr(sess, 2, a.asr_models.split(",")[0], chunked=True)
    if "llm" in only:
        for m in a.llm_models.split(","):
            llm(sess, a.runs, True, prompt, m or None)
    if "tts" in only:
        tts(sess, a.runs, 16000)


if __name__ == "__main__":
    main()
