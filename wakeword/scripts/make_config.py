"""Writes the training_parameters.yaml microWakeWord trains from.

The feature sets are:
  <phrase>_positive   the wake word itself, Fish Audio plus Piper
  adversarial         confusable words and everyday sentences, same voices
  dinner_party        DiPCo and CHiME6 conversation, the standard negative set
  music               a Free Music Archive subset, stands in for no_speech
  dinner_party_eval   ambient validation and testing, gives false accepts/hour

Usage:
    python scripts/make_config.py --phrase orion --steps 8000 4000
"""

import argparse
import os

import yaml

WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))
FEATURES = os.path.join(WORK, "features")
NEGATIVES = os.path.join(WORK, "negative_datasets")


def feature_entry(path, weight, penalty, truth, strategy):
    return {
        "features_dir": path,
        "sampling_weight": weight,
        "penalty_weight": penalty,
        "truth": truth,
        "truncation_strategy": strategy,
        "type": "mmap",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--phrase", required=True)
    parser.add_argument("--steps", type=int, nargs="+", default=[8000, 4000])
    parser.add_argument("--rates", type=float, nargs="+", default=[0.001, 0.0002])
    parser.add_argument("--batch-size", type=int, default=128)
    parser.add_argument("--clip-duration-ms", type=int, default=1500)
    parser.add_argument("--negative-weight", type=int, default=20)
    parser.add_argument("--positive-weight", type=float, default=2.0,
                        help="sampling weight of the positive set; with the standard negatives "
                             "added, 4 keeps positives near a tenth of each batch")
    parser.add_argument("--eval-interval", type=int, default=500,
                        help="steps between full validations, each costs about 2.5 minutes here")
    parser.add_argument("--positive-set", default=None, help="defaults to <phrase>_positive")
    parser.add_argument("--train-name", default=None, help="train_dir name, defaults to the phrase")
    parser.add_argument("--mask-all", action="store_true",
                        help="SpecAugment in every stage, for a fine-tune that has no stage one")
    parser.add_argument("--extra-set", action="append", default=[],
                        help="an extra negative feature set as name:weight, e.g. fish_confusable:3")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    positive_set = args.positive_set or (args.phrase + "_positive")
    train_name = args.train_name or args.phrase
    stages = len(args.steps)
    first_mask = 5 if args.mask_all else 0
    first_count = 2 if args.mask_all else 0
    config = {
        "window_step_ms": 10,
        "train_dir": os.path.join(WORK, "trained_models", train_name),
        "features": [
            feature_entry(
                os.path.join(FEATURES, positive_set),
                args.positive_weight, 1.0, True, "truncate_start",
            ),
            feature_entry(
                os.path.join(FEATURES, "adversarial"),
                4.0, 1.0, False, "truncate_start",
            ),
            feature_entry(
                os.path.join(NEGATIVES, "dinner_party"),
                10.0, 1.0, False, "random",
            ),
            feature_entry(
                os.path.join(FEATURES, "music"), 5.0, 1.0, False, "random"
            ),
            feature_entry(
                os.path.join(NEGATIVES, "dinner_party_eval"),
                0.0, 1.0, False, "split",
            ),
        ],
        "training_steps": args.steps,
    }
    for extra in args.extra_set:
        # name:weight[:strategy]. Generated sets live under features/ and are
        # short clips, so truncate_start; the standard negative sets live
        # under negative_datasets/ and are long tracks, so random crops.
        parts = extra.split(":")
        name, weight = parts[0], float(parts[1])
        path = os.path.join(FEATURES, name)
        strategy = "truncate_start"
        if not os.path.isdir(path) and os.path.isdir(os.path.join(NEGATIVES, name)):
            path = os.path.join(NEGATIVES, name)
            strategy = "random"
        if len(parts) > 2:
            strategy = parts[2]
        config["features"].insert(2, feature_entry(path, weight, 1.0, False, strategy))
    config.update({
        "positive_class_weight": [1] * stages,
        "negative_class_weight": [args.negative_weight] * stages,
        "learning_rates": args.rates,
        "batch_size": args.batch_size,
        # No SpecAugment in the first stage, mild masking in the later ones.
        "time_mask_max_size": [first_mask] + [5] * (stages - 1),
        "time_mask_count": [first_count] + [2] * (stages - 1),
        "freq_mask_max_size": [first_mask] + [5] * (stages - 1),
        "freq_mask_count": [first_count] + [2] * (stages - 1),
        "eval_step_interval": args.eval_interval,
        "clip_duration_ms": args.clip_duration_ms,
        "target_minimization": 0.9,
        "minimization_metric": None,
        "maximization_metric": "average_viable_recall",
    })

    out =args.out or os.path.join(WORK, "training_parameters_%s.yaml" % train_name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        yaml.dump(config, f)
    print("wrote", out)
    for entry in config["features"]:
        print(
            "  %-12s weight %4.1f truth %-5s %s"
            % (
                os.path.basename(entry["features_dir"]),
                entry["sampling_weight"],
                entry["truth"],
                "OK" if os.path.isdir(entry["features_dir"]) else "MISSING",
            )
        )


if __name__ == "__main__":
    main()
