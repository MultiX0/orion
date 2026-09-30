# Which DeepInfra models answer the OpenAI speech endpoint the board uses for a
# non Fish TTS, and do they give raw PCM, at what rate, how fast?
#
#   POST <base_url>/audio/speech  {model, input, voice, response_format: "pcm"}
#
# The contract says pcm is 24 kHz 16 bit mono. This checks it rather than
# trusting it: the byte count against the transcribed duration, and a WAV of
# each so it can be listened to later. Nothing is played.
#
#   python tools/cloud/openai_tts_probe.py

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

BASE = "https://api.deepinfra.com/v1/openai"
OUT = c.REPO / "logs" / "openai_tts"

# (model, voice to try). None means the model's default.
CANDIDATES = [
    ("hexgrad/Kokoro-82M", "af_bella"),
    ("Qwen/Qwen3-TTS", None),
    ("ResembleAI/chatterbox-multilingual", None),
    ("ResembleAI/chatterbox-turbo", None),
    ("inworld-ai/realtime-tts-1.5-mini", None),
    ("XiaomiMiMo/MiMo-V2.5-tts", None),
    ("sesame/csm-1b", None),
    ("Audio8/Audio8-TTS-Preview-0.6b", None),
]

LINES = [
    ("en", "The capital of France is Paris."),
    ("ar", "عاصمة فرنسا هي باريس."),
]


def speak(sess, model, voice, text):
    body = {"model": model, "input": text, "response_format": "pcm"}
    if voice:
        body["voice"] = voice
    t0 = time.perf_counter()
    r = sess.post(BASE + "/audio/speech", stream=True, timeout=60,
                  headers={"Authorization": "Bearer " + c.env("DEEPINFRA_API_KEY"),
                           "Content-Type": "application/json"},
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"))
    first = None
    data = bytearray()
    if r.status_code == 200:
        for chunk in r.iter_content(4096):
            if chunk and first is None:
                first = (time.perf_counter() - t0) * 1000
            data += chunk
    total = (time.perf_counter() - t0) * 1000
    return r.status_code, r.headers.get("content-type", ""), bytes(data), first, total, \
        (r.text[:160] if r.status_code != 200 else "")


def main():
    sess = c.session()
    OUT.mkdir(parents=True, exist_ok=True)
    print("| model | voice | line | status | type | bytes | s at 24 kHz | first ms | total ms | heard at 24 kHz |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for model, voice in CANDIDATES:
        for lang, text in LINES:
            status, ctype, pcm, first, total, err = speak(sess, model, voice, text)
            if status != 200:
                print("| %s | %s | %s | %d | | | | | %.0f | %s |" % (
                    model, voice or "-", lang, status, total, err.replace("|", "/")))
                continue
            wav_like = pcm[:4] == b"RIFF"
            if wav_like:
                pcm = pcm[44:]
            secs = len(pcm) / 2 / 24000
            name = "%s_%s.wav" % (model.split("/")[-1], lang)
            c.save_wav(OUT / name, pcm, rate=24000)
            heard = ""
            try:
                heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm, rate=24000), sess=sess,
                                           model="Qwen/Qwen3-ASR-1.7B")
            except RuntimeError as e:
                heard = "asr failed"
            print("| %s | %s | %s | 200 | %s%s | %d | %.2f | %s | %.0f | %s |" % (
                model, voice or "-", lang, ctype, " RIFF" if wav_like else "", len(pcm), secs,
                "%.0f" % first if first else "-", total, heard[:40]))


if __name__ == "__main__":
    main()
