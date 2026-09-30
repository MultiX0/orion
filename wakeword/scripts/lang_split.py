"""FRR on the round two holdout split by language and by spelling, from the
.r2scores.json files eval_r2.py leaves next to each model.

Usage:
    python scripts/lang_split.py base/orion_full2_step9000.r2scores.json work/manual/x.r2scores.json
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
meta = {}
with open(os.path.join(HERE, "work", "fish_log.jsonl"), encoding="utf-8") as f:
    for line in f:
        r = json.loads(line)
        if r.get("name", "").startswith("h"):
            meta[r["name"]] = r
groups = {
    "en": lambda r: r["lang"] == "en",
    "ar": lambda r: r["lang"] == "ar",
    "ar_alif": lambda r: "ايون" in r["text"],
    "ar_wiyon": lambda r: r["lang"] == "ar" and "ايون" not in r["text"],
    "whisper": lambda r: "whisper" in r["text"],
}
for path in sys.argv[1:]:
    s = json.load(open(path))["r2"]
    for c in (0.95, 0.96, 0.97):
        parts = []
        for g, test in groups.items():
            vals = [v for n, v in s.items() if n in meta and test(meta[n])]
            parts.append("%s %.1f (%d)" % (g, 100.0 * sum(v <= c for v in vals) / max(1, len(vals)), len(vals)))
        print(os.path.basename(path), c, ", ".join(parts))
