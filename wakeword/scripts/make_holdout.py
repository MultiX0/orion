"""Moves a slice of the generated clips aside before any feature is built.

microWakeWord splits its own training, validation and testing sets, but those
splits live inside the feature files. This keeps real WAV files the model has
never seen in any form, which is what evaluate.py scores and where the ten
committed test clips come from.

Usage:
    python scripts/make_holdout.py --source data/fish/orion --out data/holdout/orion --every 20
"""

import argparse
import os
import shutil
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--every", type=int, default=20)
    args = parser.parse_args()

    source = args.source if os.path.isabs(args.source) else os.path.join(HERE, args.source)
    out = args.out if os.path.isabs(args.out) else os.path.join(HERE, args.out)
    os.makedirs(out, exist_ok=True)

    prefix = os.path.basename(os.path.dirname(source)) + "_" + os.path.basename(source)
    files = sorted(f for f in os.listdir(source) if f.endswith(".wav"))
    moved = 0
    for index, name in enumerate(files):
        if index % args.every:
            continue
        shutil.move(os.path.join(source, name), os.path.join(out, prefix + "_" + name))
        moved += 1
    print("%s -> %s: moved %d of %d" % (args.source, args.out, moved, len(files)))


if __name__ == "__main__":
    main()
