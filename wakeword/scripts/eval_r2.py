"""Scores one or more models on the round two yardsticks and prints one row
per model and cutoff:

  frr_old     holdout/orion, the old held-out positives (clean)
  frr_r2      holdout/orion_r2, unseen Fish voices, new spellings and cues
  frr_alif    the part of frr_r2 that says اورايون or أورايون
  frr_quiet   both holdouts again at 3 to 12 dB over a mic noise floor
  fa_conf     holdout/negative, confusables and ordinary words (count)
  fa_qspeech  held-out words at -3 to 12 dB over the floor (count)
  fa_qsound   synthetic clicks, knocks, hums, beeps, breaths (count)

Usage:
    python scripts/eval_r2.py --models a.tflite b.tflite --cutoffs 0.9 0.95 0.97
"""

import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from evaluate import score_dir  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SETS = {
    "old": "data/holdout/orion",
    "r2": "data/holdout/orion_r2",
    "q_old": "data/quiet_eval/pos_old",
    "q_r2": "data/quiet_eval/pos_r2",
    "conf": "data/holdout/negative",
    "qspeech": "data/quiet_eval/neg_speech",
    "qsound": "data/quiet_eval/neg_sounds",
}


def alif_names():
    names = set()
    with open(os.path.join(HERE, "work", "fish_log.jsonl"), encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            if r.get("name", "").startswith("h") and ("ايون" in r["text"]):
                names.add(r["name"])
    return names


def gate_levels(directory):
    """Per clip: (floor rms of the first 0.5 s, loudest 100 ms rms), as the
    firmware energy gate sees them (it needs loudest >= max(mult * floor, 30))."""
    import wave
    out = {}
    for name in sorted(os.listdir(directory)):
        if not name.endswith(".wav"):
            continue
        with wave.open(os.path.join(directory, name), "rb") as w:
            x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
        frames = x[: x.size // 1600 * 1600].reshape(-1, 1600)
        loud = float(np.sqrt((frames ** 2).mean(axis=1)).max()) if frames.size else 0.0
        floor = float(np.sqrt((x[:8000] ** 2).mean())) if x.size else 0.0
        out[name] = (floor, loud)
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--models", nargs="+", required=True)
    p.add_argument("--cutoffs", type=float, nargs="+", default=[0.9, 0.95, 0.97])
    p.add_argument("--window", type=int, default=5)
    args = p.parse_args()
    from microwakeword.inference import Model

    alif = alif_names()
    levels = {k: gate_levels(os.path.join(HERE, SETS[k])) for k in ("q_old", "q_r2", "qspeech", "qsound")}

    def passes(key, name, mult):
        floor, loud = levels[key][name]
        return loud >= max(mult * floor, 30)

    print("model,cutoff,frr_old,frr_r2,frr_alif,frr_quiet,fa_conf,fa_qspeech,fa_qsound,n,"
          "gate2: frr_quiet fa_qspeech fa_qsound, gate3: same")
    for path in args.models:
        model = Model(path, stride=3)
        s = {}
        for key, d in SETS.items():
            rows = score_dir(model, os.path.join(HERE, d), args.window)
            s[key] = {n: v for n, v, _ in rows}
        with open(path.replace(".tflite", ".r2scores.json"), "w") as f:
            json.dump(s, f)
        for c in args.cutoffs:
            def frr(vals):
                vals = np.array(list(vals))
                return 100.0 * (vals <= c).mean() if vals.size else float("nan")

            def fa(vals):
                return int((np.array(list(vals)) > c).sum())

            quiet = list(s["q_old"].values()) + list(s["q_r2"].values())
            gated = []
            for mult in (2, 3):
                gq = [v if passes(k, n, mult) else 0.0 for k in ("q_old", "q_r2") for n, v in s[k].items()]
                gs = [v for n, v in s["qspeech"].items() if passes("qspeech", n, mult)]
                gn = [v for n, v in s["qsound"].items() if passes("qsound", n, mult)]
                gated.append("%.1f %d %d" % (frr(gq), fa(gs), fa(gn)))
            print("%s,%.2f,%.1f,%.1f,%.1f,%.1f,%d,%d,%d,%s,%s" % (
                os.path.basename(path), c, frr(s["old"].values()), frr(s["r2"].values()),
                frr(v for n, v in s["r2"].items() if n in alif), frr(quiet),
                fa(s["conf"].values()), fa(s["qspeech"].values()), fa(s["qsound"].values()),
                "/".join(str(len(s[k])) for k in SETS), ", ".join(gated)), flush=True)


if __name__ == "__main__":
    main()
