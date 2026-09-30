"""Chooses a probability cutoff from the holdout scores evaluate.py saved.

For a model exported before the trainer has measured its ROC, the only false
accept figure available is the holdout negatives. This sweeps the cutoff and
takes the lowest one that keeps every holdout negative silent, then reports the
false rejection rate that cutoff gives on the holdout positives. It writes the
cutoff into the manifest and adds an "evaluation" block beside "micro", which
the firmware does not read, saying where the numbers came from.

Usage:
    python scripts/pick_cutoff.py --scores work/holdout_scores_orion_early.json \
        --manifest models/orion_early.json
"""

import argparse
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--scores", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--max-frr", type=float, default=0.05)
    args = parser.parse_args()

    scores_path = args.scores if os.path.isabs(args.scores) else os.path.join(HERE, args.scores)
    with open(scores_path, encoding="utf-8") as f:
        report = json.load(f)
    positives = np.array([r["score"] for r in report["positive_scores"]])
    negatives = np.array([r["score"] for r in report["negative_scores"]])

    print("cutoff  frr      neg_fa   (holdout %d pos, %d neg)" % (len(positives), len(negatives)))
    chosen = None
    for cutoff in [round(c, 3) for c in np.arange(0.50, 1.0, 0.01)] + [0.995, 0.999]:
        frr = float((positives <= cutoff).mean())
        fa = int((negatives > cutoff).sum())
        marker = ""
        if chosen is None and fa == 0:
            chosen = (cutoff, frr, fa)
            marker = "  <- lowest cutoff with zero holdout false accepts"
        if cutoff in (0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.97, 0.99, 0.995, 0.999) or marker:
            print("%.3f   %6.2f%%  %3d%s" % (cutoff, frr * 100, fa, marker))
    if chosen is None:
        chosen = (0.999, float((positives <= 0.999).mean()), int((negatives > 0.999).sum()))
        print("no cutoff silences every holdout negative, using 0.999")
    cutoff, frr, fa = chosen
    meets = frr <= args.max_frr and fa == 0
    print("chosen cutoff %.2f: frr %.2f%%, holdout false accepts %d, meets target: %s"
          % (cutoff, frr * 100, fa, meets))

    manifest_path = args.manifest if os.path.isabs(args.manifest) else os.path.join(HERE, args.manifest)
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    manifest["micro"]["probability_cutoff"] = round(float(cutoff), 2)
    manifest["evaluation"] = {
        "cutoff_source": "holdout sweep, lowest cutoff with zero holdout false accepts",
        "holdout_positive_clips": int(len(positives)),
        "holdout_negative_clips": int(len(negatives)),
        "holdout_false_rejection_rate": round(frr, 4),
        "holdout_false_accepts": fa,
        "false_accepts_per_hour": "not measured, the training ROC does not exist yet",
    }
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("wrote", manifest_path)


if __name__ == "__main__":
    main()
