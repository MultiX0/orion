"""Checks that the generated positives really say the wake word.

A TTS voice asked for a single word sometimes reads it as something else, and
some public Fish Audio voices are sound effects rather than speakers. This
sends a random sample of the clips back through Fish Audio ASR and prints what
comes back, so a systematic problem shows up before training instead of after.

Usage:
    python scripts/asr_check.py --dir data/fish/orion --count 24
"""

import argparse
import json
import os
import random
import sys
import urllib.error
import urllib.request
import uuid

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(HERE)
ASR = "https://api.fish.audio/v1/asr"


def load_key():
    with open(os.path.join(REPO, ".env"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("FISH_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("FISH_API_KEY not found in .env")


def transcribe(key, path, language):
    boundary = uuid.uuid4().hex
    with open(path, "rb") as f:
        audio = f.read()
    parts = []
    parts.append(("--" + boundary).encode())
    parts.append(
        b'Content-Disposition: form-data; name="audio"; filename="clip.wav"'
    )
    parts.append(b"Content-Type: audio/wav")
    parts.append(b"")
    body = b"\r\n".join(parts) + b"\r\n" + audio + b"\r\n"
    if language:
        body += b"\r\n".join(
            [
                ("--" + boundary).encode(),
                b'Content-Disposition: form-data; name="language"',
                b"",
                language.encode(),
                b"",
            ]
        )
    body += ("--" + boundary + "--\r\n").encode()

    req = urllib.request.Request(
        ASR,
        data=body,
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "multipart/form-data; boundary=" + boundary,
            "model": "transcribe-1",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.loads(resp.read().decode("utf-8")).get("text", "")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", required=True)
    parser.add_argument("--count", type=int, default=24)
    parser.add_argument("--language", default=None)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()

    key = load_key()
    path = args.dir if os.path.isabs(args.dir) else os.path.join(HERE, args.dir)
    files = sorted(f for f in os.listdir(path) if f.endswith(".wav"))
    random.Random(args.seed).shuffle(files)
    files = files[: args.count]

    hits = 0
    for name in files:
        try:
            text = transcribe(key, os.path.join(path, name), args.language)
        except urllib.error.HTTPError as exc:
            print(name, "HTTP", exc.code, exc.read().decode()[:120])
            return
        cleaned = text.strip()
        good = any(
            token in cleaned.lower()
            for token in ("orion", "oryon", "ryon", "أوريون", "اوريون", "وريون")
        )
        hits += good
        print("%-28s %-5s %s" % (name, "ok" if good else "----", cleaned[:60]))
    print("%d of %d transcripts contain the wake word" % (hits, len(files)))


if __name__ == "__main__":
    main()
