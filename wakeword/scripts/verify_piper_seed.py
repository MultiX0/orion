"""Proves which seed piper_generate.py was run with.

piper_manifest.py replays the generator's random choices to recover which clip
said what. That is only true if the seed matches the one the real run used, and
the run did not record it. This re-renders a few clips from a candidate seed's
job list and compares the audio to what is on disk. Piper is deterministic, so
the right seed reproduces the file sample for sample. The clips were trimmed in
place afterwards, so the freshly rendered audio is trimmed the same way before
comparing.

Usage:
    python scripts/verify_piper_seed.py --phrase orion --count 3000 --seeds 5 101
"""

import argparse
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "scripts"))

import piper_generate  # noqa: E402
import qc_clips  # noqa: E402


def read(path):
    with wave.open(path, "rb") as handle:
        return np.frombuffer(handle.readframes(handle.getnframes()), dtype=np.int16)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--phrase", default="orion")
    parser.add_argument("--count", type=int, default=3000)
    parser.add_argument("--seeds", type=int, nargs="+", default=[5])
    parser.add_argument("--samples", type=int, default=6)
    args = parser.parse_args()

    out_dir = os.path.join(HERE, "data", "piper", args.phrase)
    on_disk = sorted(f for f in os.listdir(out_dir) if f.endswith(".wav"))
    probe = on_disk[:: max(1, len(on_disk) // args.samples)][: args.samples]

    scratch = os.path.join(HERE, "work", "seed_check")
    os.makedirs(scratch, exist_ok=True)

    for seed in args.seeds:
        per_voice = piper_generate.build_jobs(args.phrase, args.count, seed)
        index = {}
        for voice_name, jobs in per_voice.items():
            for job in jobs:
                index[job["name"]] = (voice_name, job)
        matches = 0
        for name in probe:
            if name not in index:
                continue
            voice_name, job = index[name]
            piper_generate.render((voice_name, [job], scratch))
            fresh = read(os.path.join(scratch, name))
            trimmed = qc_clips.trim(fresh)
            stored = read(os.path.join(out_dir, name))
            same = trimmed is not None and trimmed.size == stored.size and np.array_equal(trimmed, stored)
            matches += bool(same)
            print("  seed %d  %s  %-28s %s" % (seed, name, job["text"], "match" if same else "differs"))
        print("seed %d: %d of %d clips reproduced" % (seed, matches, len(probe)))


if __name__ == "__main__":
    main()
