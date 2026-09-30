"""Round two of Fish Audio positives: new voices, the Arabic spellings the
shipped model misses (اورايون, أورايون), and delivery cues (whisper, fast,
slow, excited) through S2 [bracket] tags.

New voices are split by voice id: one in four never reaches training and
only speaks the held-out set, so the holdout measures unseen speakers.

Writes data/fish/orion_r2 (training) and data/holdout/orion_r2 (held out).
Every request is logged to work/fish_log.jsonl. The key is never printed;
ORION_ENV points at the .env file when it is not at the repo root.

Usage:
    python scripts/fish_round2.py --train 900 --holdout 200
"""

import argparse
import hashlib
import json
import os
import queue
import random
import sys
import threading
import time
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fish_generate as fg  # noqa: E402
import fish_voices as fv  # noqa: E402

AR_WORDS = ["اورايون", "أورايون", "أوريون", "اوريون", "أورايون؟", "اورايون!"]
AR_LEAD = ["يا ", "طيب ", "هاي ", "يلا يا ", "", "", ""]
EN_WORDS = ["Orion", "Orion?", "Orion!", "Orion.", "O-rye-on"]
EN_LEAD = ["Hey ", "Okay ", "Um, ", "So, ", "", "", ""]
# S2 reads [bracket] cues as delivery hints. Empty means a plain take.
CUES = ["", "", "", "[whisper] ", "[whispering softly] ", "[excited] ", "[calm] ",
        "[tired] ", "[speaking fast] ", "[slowly] ", "[shouting] ", "[questioning] "]


def load_key():
    path = os.environ.get("ORION_ENV") or os.path.join(fg.REPO, ".env")
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("FISH_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("FISH_API_KEY not found")


def new_voices(key, known):
    found = {}
    for lang in ("ar", "en"):
        for page in range(3, 7):
            q = urllib.parse.urlencode({"language": lang, "page_size": 50,
                                        "page_number": page, "sort_by": "task_count"})
            try:
                items = fv.get(fv.API + "?" + q, key).get("items", [])
            except Exception as exc:
                print("voice page failed", lang, page, type(exc).__name__)
                continue
            for it in items:
                if it.get("state") != "trained" or it.get("type") != "tts":
                    continue
                if it.get("dmca_taken_down") or it["_id"] in known:
                    continue
                found[it["_id"]] = {"id": it["_id"], "bucket": lang}
    return list(found.values())


def is_holdout(voice_id):
    return int(hashlib.md5(voice_id.encode()).hexdigest(), 16) % 4 == 0


def make_jobs(count, voices, rng, prefix):
    ar = [v for v in voices if v["bucket"] == "ar"]
    en = [v for v in voices if v["bucket"] == "en"]
    jobs = []
    for i in range(count):
        arabic = rng.random() < 0.6
        voice = rng.choice(ar if arabic else en)
        if arabic:
            text = rng.choice(AR_LEAD) + rng.choice(AR_WORDS)
        else:
            text = rng.choice(EN_LEAD) + rng.choice(EN_WORDS)
        text = rng.choice(CUES) + text
        jobs.append({
            "name": "%s%05d_%s.wav" % (prefix, i, voice["id"][:8]),
            "text": text, "voice": voice["id"], "lang": "ar" if arabic else "en",
            "speed": round(rng.uniform(0.7, 1.4), 2),
            "volume": rng.choice([0, 0, -4, -8, 4]),
            "temperature": round(rng.uniform(0.5, 0.95), 2),
            "top_p": round(rng.uniform(0.6, 0.95), 2),
        })
    return jobs


def run(jobs, key, out_dir, threads):
    os.makedirs(out_dir, exist_ok=True)
    q = queue.Queue()
    for j in jobs:
        q.put(j)
    stats = {"ok": 0, "fail": 0, "chars": 0, "bytes": 0}
    lock = threading.Lock()
    with open(os.path.join(fg.HERE, "work", "fish_log.jsonl"), "a", encoding="utf-8") as log:
        ts = [threading.Thread(target=fg.worker, args=(q, key, out_dir, lock, log, stats), daemon=True)
              for _ in range(threads)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
    return stats


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser()
    p.add_argument("--train", type=int, default=900)
    p.add_argument("--holdout", type=int, default=200)
    p.add_argument("--threads", type=int, default=8)
    args = p.parse_args()

    key = load_key()
    print("key length", len(key), "ends", key[-4:])
    pool = fg.load_voices()
    extra = new_voices(key, {v["id"] for v in pool})
    held = [v for v in extra if is_holdout(v["id"])]
    train_new = [v for v in extra if not is_holdout(v["id"])]
    print("new voices", len(extra), "held out", len(held),
          "ar/en held", sum(v["bucket"] == "ar" for v in held), sum(v["bucket"] == "en" for v in held),
          flush=True)
    with open(os.path.join(fg.HERE, "work", "fish_voices_r2.json"), "w", encoding="utf-8") as f:
        json.dump({"train_new": train_new, "holdout": held}, f, indent=1)

    rng = random.Random(23)
    started = time.time()
    s1 = run(make_jobs(args.holdout, held, rng, "h"), key,
             os.path.join(fg.HERE, "data", "holdout", "orion_r2"), args.threads)
    print("holdout ok=%d fail=%d chars=%d" % (s1["ok"], s1["fail"], s1["chars"]), flush=True)
    s2 = run(make_jobs(args.train, pool + train_new, rng, "t"), key,
             os.path.join(fg.HERE, "data", "fish", "orion_r2"), args.threads)
    print("train ok=%d fail=%d chars=%d" % (s2["ok"], s2["fail"], s2["chars"]))
    print("FISH_R2_DONE requests=%d chars=%d seconds=%.0f" % (
        s1["ok"] + s1["fail"] + s2["ok"] + s2["fail"], s1["chars"] + s2["chars"], time.time() - started))


if __name__ == "__main__":
    main()
