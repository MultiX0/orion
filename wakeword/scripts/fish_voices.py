"""Lists Fish Audio voice models and saves a pool to use for wake word samples.

Reads FISH_API_KEY from .env at the repo root. The key is never printed.
Writes work/fish_voices.json with one entry per usable voice.

Usage:
    python scripts/fish_voices.py
"""

import json
import os
import sys
import urllib.parse
import urllib.request

API = "https://api.fish.audio/model"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(HERE)
OUT = os.path.join(HERE, "work", "fish_voices.json")

# How many voices we want per language bucket. Arabic is weighted heaviest
# because the audience speaks Arabic.
BUCKETS = [
    ("ar", 60),
    ("en", 30),
]


def load_key():
    path = os.path.join(REPO, ".env")
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("FISH_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("FISH_API_KEY not found in .env")


def get(url, key):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + key})
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def collect(key, language, wanted):
    found = {}
    page = 1
    while len(found) < wanted and page <= 8:
        q = urllib.parse.urlencode(
            {
                "language": language,
                "page_size": 50,
                "page_number": page,
                "sort_by": "task_count",
            }
        )
        data = get(API + "?" + q, key)
        items = data.get("items", [])
        if not items:
            break
        for item in items:
            if item.get("state") != "trained" or item.get("type") != "tts":
                continue
            if item.get("dmca_taken_down"):
                continue
            found[item["_id"]] = {
                "id": item["_id"],
                "title": item.get("title", ""),
                "languages": item.get("languages", []),
                "tags": item.get("tags", []),
                "task_count": item.get("task_count", 0),
                "bucket": language,
            }
            if len(found) >= wanted:
                break
        page += 1
    return list(found.values())


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    key = load_key()
    pool = {}
    for language, wanted in BUCKETS:
        voices = collect(key, language, wanted)
        print(language, "voices found:", len(voices))
        for v in voices:
            pool.setdefault(v["id"], v)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(list(pool.values()), f, ensure_ascii=False, indent=1)
    print("total unique voices:", len(pool))
    print("written:", OUT)


if __name__ == "__main__":
    main()
