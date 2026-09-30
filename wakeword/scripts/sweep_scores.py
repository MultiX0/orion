"""Prints holdout false rejection and confusable false accepts at fixed cutoffs.

pick_cutoff.py reports the lowest cutoff that silences every holdout negative,
which on a 192 clip set is decided by one outlier. This shows the whole
trade-off line instead, one row per scores file, so checkpoints can be
compared fairly.

Usage:
    python scripts/sweep_scores.py work/scout_orion_ft/*.scores.json
"""

import json
import re
import sys

import numpy as np

CUTOFFS = (0.80, 0.90, 0.95, 0.98)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    files = sys.argv[1:]

    def step_of(path):
        m = re.search(r"step(\d+)", path)
        return int(m.group(1)) if m else 0

    print("file | " + " | ".join("frr@%.2f fa@%.2f" % (c, c) for c in CUTOFFS)
          + " | cutoff for frr<=5%, fa there")
    for path in sorted(files, key=step_of):
        with open(path, encoding="utf-8") as f:
            r = json.load(f)
        pos = np.array([x["score"] for x in r["positive_scores"]])
        neg = np.array([x["score"] for x in r["negative_scores"]])
        cells = []
        for c in CUTOFFS:
            cells.append("%5.1f %3d" % (100 * (pos <= c).mean(), int((neg > c).sum())))
        best = None
        for c in np.arange(0.50, 1.0, 0.005):
            if (pos <= c).mean() <= 0.05:
                best = (c, int((neg > c).sum()))
        tail = "%.3f %d" % best if best else "none"
        name = path.replace("\\", "/").split("/")[-1].replace(".scores.json", "")
        print("%s | %s | %s" % (name, " | ".join(cells), tail))


if __name__ == "__main__":
    main()
