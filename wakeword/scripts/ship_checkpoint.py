"""Ships a scouted checkpoint: copies its TFLite model into models/ and writes
the v2 manifest with a cutoff chosen by hand from the holdout sweep.

The manifest has the same fields export_model.py writes, plus an "evaluation"
block the firmware ignores: the holdout false rejection and confusable false
accepts at that cutoff, and the trainer's ROC numbers at the nearest cutoff
when roc_eval.sh has been run for the same weights.

Usage:
    python scripts/ship_checkpoint.py --tflite work/scout_orion_ft2/orion_ft2_step2000.tflite \
        --scores work/scout_orion_ft2/orion_ft2_step2000.scores.json --cutoff 0.90 --name orion \
        [--roc ~/orion_ww/trained_models/orion_ft2/tflite_stream_state_internal_quant/tflite_streaming_roc.txt]
"""

import argparse
import json
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(HERE, "scripts"))


def absolute(path):
    return path if os.path.isabs(path) else os.path.join(HERE, path)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--tflite", required=True)
    parser.add_argument("--scores", required=True)
    parser.add_argument("--cutoff", type=float, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--wake-word", default="Orion")
    parser.add_argument("--source", default="", help="which run and step the weights came from")
    parser.add_argument("--roc", default=None)
    parser.add_argument("--ambient-faph", type=float, default=None,
                        help="false accepts per hour at this cutoff from scripts/ambient_faph.py")
    parser.add_argument("--noise-faph", type=float, default=None,
                        help="detections per hour on unseen no-speech sounds from scripts/silence_test.py")
    args = parser.parse_args()

    import export_model

    with open(absolute(args.scores), encoding="utf-8") as f:
        report = json.load(f)
    pos = np.array([r["score"] for r in report["positive_scores"]])
    neg = np.array([r["score"] for r in report["negative_scores"]])
    frr = float((pos <= args.cutoff).mean())
    fa = int((neg > args.cutoff).sum())

    models_dir = os.path.join(HERE, "models")
    os.makedirs(models_dir, exist_ok=True)
    out_tflite = os.path.join(models_dir, args.name + ".tflite")
    shutil.copyfile(absolute(args.tflite), out_tflite)
    arena, detail = export_model.estimate_arena(out_tflite)

    evaluation = {
        "source": args.source,
        "cutoff_source": "holdout sweep at a fixed cutoff, see models/TEST_CLIPS.md",
        "holdout_positive_clips": int(len(pos)),
        "holdout_negative_clips": int(len(neg)),
        "holdout_false_rejection_rate": round(frr, 4),
        "holdout_false_accepts": fa,
    }
    if args.roc:
        points = export_model.parse_roc(os.path.expanduser(args.roc))
        near = [p for p in points if abs(p["cutoff"] - args.cutoff) < 0.011]
        if near:
            p = min(near, key=lambda p: abs(p["cutoff"] - args.cutoff))
            evaluation["roc_cutoff"] = p["cutoff"]
            evaluation["roc_false_rejection_rate"] = p["frr"]
            evaluation["roc_false_accepts_per_hour"] = p["faph"]
        evaluation["roc_points"] = points
    elif args.ambient_faph is not None:
        evaluation["ambient_false_accepts_per_hour"] = args.ambient_faph
        evaluation["ambient_source"] = "dinner_party_eval testing_ambient, 5.33 h, scripts/ambient_faph.py"
    else:
        evaluation["false_accepts_per_hour"] = "not measured for this checkpoint"
    if args.noise_faph is not None:
        evaluation["unseen_noise_detections_per_hour"] = args.noise_faph
        evaluation["noise_source"] = "fsd50k_no_speech prefix never trained on, 2.77 h, scripts/silence_test.py"

    manifest = {
        "type": "micro",
        "wake_word": args.wake_word,
        "author": "Orion project",
        "website": "https://github.com/MultiX0",
        "model": args.name + ".tflite",
        "trained_languages": ["ar", "en"],
        "version": 2,
        "micro": {
            "probability_cutoff": round(args.cutoff, 2),
            "sliding_window_size": export_model.SLIDING_WINDOW,
            "feature_step_size": export_model.FEATURE_STEP_MS,
            "tensor_arena_size": arena,
            "minimum_esphome_version": "2024.7.0",
        },
        "evaluation": evaluation,
    }
    out_json = os.path.join(models_dir, args.name + ".json")
    with open(out_json, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("model:", out_tflite, os.path.getsize(out_tflite), "bytes, arena", arena)
    print("manifest:", out_json)
    print("cutoff %.2f: holdout frr %.2f%%, confusable false accepts %d of %d"
          % (args.cutoff, frr * 100, fa, len(neg)))


if __name__ == "__main__":
    main()
