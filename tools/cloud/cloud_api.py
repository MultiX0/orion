# Shared client for the three services the board talks to. Every script in
# tools/cloud imports this one so the PC and the firmware use the exact same
# endpoints, headers and field names.
#
# Checked against docs.fish.audio:
#   Fish ASR  POST /v1/asr   multipart field "audio", model in an HTTP header
#   Fish TTS  POST /v1/tts   JSON body, model in an HTTP header, raw PCM out
#   DeepInfra POST /v1/openai/chat/completions, OpenAI shape
#
# Keys are read from .env and never printed.

import json
import os
import re
import sys
import time
from pathlib import Path

import requests

from wav_util import (SAMPLE_RATE, load_wav, pcm_seconds, pcm_stats,
                      pcm_to_wav, save_wav, wav_header)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")

REPO = Path(__file__).resolve().parents[2]

FISH_HOST = "https://api.fish.audio"
FISH_TTS_URL = FISH_HOST + "/v1/tts"
FISH_ASR_URL = FISH_HOST + "/v1/asr"
FISH_MODEL_URL = FISH_HOST + "/model"
FISH_VOICE_DESIGN_URL = FISH_HOST + "/v1/voice-design"

DEEPINFRA_URL = "https://api.deepinfra.com/v1/openai/chat/completions"
DEEPINFRA_STT_URL = "https://api.deepinfra.com/v1/openai/audio/transcriptions"
DEEPINFRA_STT_MODEL = "openai/whisper-large-v3"

TTS_MODEL = "s2.1-pro"
ASR_MODEL = "transcribe-1"

PROMPT_FILE = REPO / "firmware" / "assets" / "system_prompt.txt"
NO_TAGS_LINE = ("\n\nNever write anything in square brackets: the voice you speak "
                "through reads everything aloud.")


def for_tts(text, fish=True):
    """The prompt as the board sends it (cloud_prompt_refresh in orion_cloud.c):
    with Fish the <fish> marker lines go and the voice tag rules stay; with any
    other text to speech the whole section goes and a no brackets line is added."""
    if fish:
        return re.sub(r"^</?fish>\r?\n", "", text, flags=re.M)
    return re.sub(r"<fish>\r?\n.*?</fish>\r?\n(\r?\n)?", "", text, flags=re.S) + NO_TAGS_LINE


def system_prompt(fish=True, path=None):
    return for_tts((path or PROMPT_FILE).read_text(encoding="utf-8"), fish).strip()


_env_cache = None


def env(key, default=""):
    """Read a key from .env at the repo root. Never prints the value."""
    global _env_cache
    if _env_cache is None:
        _env_cache = {}
        path = REPO / ".env"
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                _env_cache[k.strip()] = v.strip()
    return os.environ.get(key) or _env_cache.get(key, default)


def key_fingerprint(key):
    """Safe to print: length and last four characters only."""
    if not key:
        return "MISSING"
    return "len=%d tail=...%s" % (len(key), key[-4:])


def fish_headers(model=None):
    h = {"Authorization": "Bearer " + env("FISH_API_KEY")}
    if model:
        h["model"] = model
    return h


def session():
    """One session per host keeps the TLS connection alive between calls."""
    s = requests.Session()
    s.headers["User-Agent"] = "orion-firmware/0.1"
    return s


# ---------------------------------------------------------------------------
# WAV helpers. Fish returns raw headerless PCM, so we build the header here.
# The board does the same thing in C, see cloud_util.c.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Fish Audio
# ---------------------------------------------------------------------------

def tts(text, voice_id=None, sess=None, fmt="pcm", rate=SAMPLE_RATE,
        latency="balanced", model=TTS_MODEL, prosody=None, on_first_chunk=None,
        chunk_length=None, timeout=60):
    """Streams TTS. Returns (audio_bytes, ttfb_ms, total_ms).

    format "pcm" is raw 16-bit mono little endian at `rate`, no header.
    """
    body = {"text": text, "format": fmt, "latency": latency}
    if rate:
        body["sample_rate"] = rate
    if voice_id:
        body["reference_id"] = voice_id
    if prosody:
        body["prosody"] = prosody
    if chunk_length:
        body["chunk_length"] = chunk_length

    http = sess or requests
    headers = fish_headers(model)
    headers["Content-Type"] = "application/json"

    t0 = time.perf_counter()
    first = None
    out = bytearray()
    r = http.post(FISH_TTS_URL, headers=headers,
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                  stream=True, timeout=timeout)
    if r.status_code != 200:
        raise RuntimeError("fish tts %d: %s" % (r.status_code, r.text[:300]))
    for chunk in r.iter_content(chunk_size=4096):
        if not chunk:
            continue
        if first is None:
            first = (time.perf_counter() - t0) * 1000.0
            if on_first_chunk:
                on_first_chunk(first)
        out += chunk
    total = (time.perf_counter() - t0) * 1000.0
    return bytes(out), (first or total), total


def asr(wav_bytes, language=None, sess=None, model=ASR_MODEL, timeout=60):
    """Returns (text, duration_seconds, elapsed_ms)."""
    files = {"audio": ("speech.wav", wav_bytes, "audio/wav")}
    data = {}
    if language:
        data["language"] = language

    http = sess or requests
    t0 = time.perf_counter()
    r = http.post(FISH_ASR_URL, headers=fish_headers(model), files=files,
                  data=data, timeout=timeout)
    elapsed = (time.perf_counter() - t0) * 1000.0
    if r.status_code != 200:
        raise RuntimeError("fish asr %d: %s" % (r.status_code, r.text[:300]))
    j = r.json()
    return j.get("text", ""), j.get("duration", 0.0), elapsed


def voice_design(instruction, reference_text=None, n=2, language=None,
                 seed=None, sess=None, timeout=180):
    """POST /v1/voice-design. Returns the candidates list."""
    body = {"instruction": instruction, "n": n}
    if reference_text:
        body["reference_text"] = reference_text
    if language:
        body["language"] = language
    if seed is not None:
        body["seed"] = seed

    http = sess or requests
    headers = fish_headers("voice-design-1")
    headers["Content-Type"] = "application/json"
    r = http.post(FISH_VOICE_DESIGN_URL, headers=headers,
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                  timeout=timeout)
    if r.status_code != 200:
        raise RuntimeError("voice-design %d: %s" % (r.status_code, r.text[:300]))
    return r.json().get("candidates", [])


def list_voices(title=None, language=None, self_only=False, page_size=20,
                sort_by="score", sess=None, timeout=30):
    params = {"page_size": page_size, "sort_by": sort_by}
    if title:
        params["title"] = title
    if language:
        params["language"] = language
    if self_only:
        params["self"] = "true"
    http = sess or requests
    r = http.get(FISH_MODEL_URL, headers=fish_headers(), params=params,
                 timeout=timeout)
    if r.status_code != 200:
        raise RuntimeError("list models %d: %s" % (r.status_code, r.text[:300]))
    return r.json()


def create_voice(title, wav_files, texts=None, description=None, tags=None,
                 visibility="private", sess=None, timeout=180):
    """POST /model, multipart. wav_files is a list of (name, bytes)."""
    files = [("voices", (name, data, "audio/wav")) for name, data in wav_files]
    data = [("type", "tts"), ("title", title), ("train_mode", "fast"),
            ("visibility", visibility)]
    for t in (texts or []):
        data.append(("texts", t))
    for t in (tags or []):
        data.append(("tags", t))
    if description:
        data.append(("description", description))

    http = sess or requests
    r = http.post(FISH_MODEL_URL, headers=fish_headers(), files=files,
                  data=data, timeout=timeout)
    if r.status_code not in (200, 201):
        raise RuntimeError("create model %d: %s" % (r.status_code, r.text[:300]))
    return r.json()


# ---------------------------------------------------------------------------
# DeepInfra, OpenAI chat completions shape
# ---------------------------------------------------------------------------

def chat(messages, model=None, tools=None, sess=None, max_tokens=200,
         temperature=0.6, timeout=60):
    """Returns (message_dict, elapsed_ms). message_dict is the raw choice message."""
    body = {
        "model": model or env("LLM_MODEL", "google/gemma-4-31B-it-turbo"),
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    if tools:
        body["tools"] = tools
        body["tool_choice"] = "auto"

    http = sess or requests
    headers = {
        "Authorization": "Bearer " + env("DEEPINFRA_API_KEY"),
        "Content-Type": "application/json",
    }
    t0 = time.perf_counter()
    r = http.post(DEEPINFRA_URL, headers=headers,
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
                  timeout=timeout)
    elapsed = (time.perf_counter() - t0) * 1000.0
    if r.status_code != 200:
        raise RuntimeError("deepinfra %d: %s" % (r.status_code, r.text[:300]))
    return r.json()["choices"][0]["message"], elapsed


def stt_deepinfra(wav_bytes, language=None, sess=None,
                  model=DEEPINFRA_STT_MODEL, timeout=90):
    """Second transcriber, same multipart shape and same JSON `text` field.

        Two jobs. It is the independent ear that scores the voice auditions, and it
        is the board's standby ASR. Returns (text, elapsed_ms).
    """
    data = {"model": model}
    if language:
        data["language"] = language
    http = sess or requests

    # This one occasionally stalls past the timeout on a cold model. It is the
    # measuring instrument, not the product, so it retries rather than failing
    # a whole run.
    last = None
    for attempt in range(3):
        t0 = time.perf_counter()
        try:
            r = http.post(DEEPINFRA_STT_URL,
                          headers={"Authorization": "Bearer " + env("DEEPINFRA_API_KEY")},
                          files={"file": ("speech.wav", wav_bytes, "audio/wav")},
                          data=data, timeout=timeout)
        except requests.exceptions.RequestException as e:
            last = e
            continue
        elapsed = (time.perf_counter() - t0) * 1000.0
        if r.status_code == 200:
            return r.json().get("text", "").strip(), elapsed
        last = RuntimeError("deepinfra stt %d: %s" % (r.status_code, r.text[:300]))
        if r.status_code < 500:
            break
    raise RuntimeError("deepinfra stt failed after 3 tries: %s" % str(last)[:200])


def percentiles(values):
    """min, median, p95, max for a latency table."""
    if not values:
        return (0, 0, 0, 0)
    s = sorted(values)
    n = len(s)
    return (s[0], s[n // 2], s[min(n - 1, int(n * 0.95))], s[-1])
