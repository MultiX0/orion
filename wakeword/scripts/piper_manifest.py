"""Rebuilds the per clip manifest for the Piper sets.

piper_generate.py picks the voice, the speaker and the text from a seeded
random number generator and does not write a log. The same seed and count give
the same jobs back, so this script imports build_jobs and replays it. That is
how we find out which clips are Arabic and which are English after the fact.

Usage:
    python scripts/piper_manifest.py --phrase orion --count 3000 --seed 5
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "scripts"))

from piper_generate import build_jobs  # noqa: E402

AR_VOICE = "ar_JO-kareem-medium"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--phrase", required=True)
    parser.add_argument("--count", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()

    per_voice = build_jobs(args.phrase, args.count, args.seed)
    out = os.path.join(HERE, "work", "piper_%s.jsonl" % args.phrase)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rows = 0
    counts = {}
    with open(out, "w", encoding="utf-8") as handle:
        for voice_name, jobs in per_voice.items():
            for job in jobs:
                row = dict(job)
                row["voice"] = voice_name
                row["lang"] = "ar" if voice_name == AR_VOICE else "en"
                handle.write(json.dumps(row, ensure_ascii=False) + "\n")
                rows += 1
                counts[voice_name] = counts.get(voice_name, 0) + 1
    print("wrote", out, rows, "rows", counts)


if __name__ == "__main__":
    main()
