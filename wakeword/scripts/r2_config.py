"""Writes the round two fine-tune config: the orion_full2 feature mix plus the
new positives (orion_r2_pos, truth) and the quiet negatives (quiet_neg).

Usage:
    python scripts/r2_config.py --name orion_r2a --steps 3000 --rate 0.0001 --eval 750
"""

import argparse
import os

import yaml

WORK = os.path.expanduser("~/orion_ww")


def entry(path, weight, truth):
    return {"features_dir": path, "penalty_weight": 1.0, "sampling_weight": weight,
            "truncation_strategy": "truncate_start", "truth": truth, "type": "mmap"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--steps", type=int, default=3000)
    p.add_argument("--rate", type=float, default=0.0001)
    p.add_argument("--eval", type=int, default=750)
    p.add_argument("--pos-r2", type=float, default=3.0)
    p.add_argument("--quiet-neg", type=float, default=6.0)
    args = p.parse_args()
    with open(os.path.join(WORK, "training_parameters_orion_full2.yaml")) as f:
        cfg = yaml.safe_load(f)
    cfg["features"].insert(1, entry(os.path.join(WORK, "features", "orion_r2_pos"), args.pos_r2, True))
    cfg["features"].insert(2, entry(os.path.join(WORK, "features", "quiet_neg"), args.quiet_neg, False))
    cfg["train_dir"] = os.path.join(WORK, "trained_models", args.name)
    cfg["training_steps"] = [args.steps]
    cfg["learning_rates"] = [args.rate]
    cfg["eval_step_interval"] = args.eval
    for k in ("positive_class_weight", "negative_class_weight", "time_mask_max_size",
              "time_mask_count", "freq_mask_max_size", "freq_mask_count"):
        cfg[k] = [cfg[k][-1]]
    out = os.path.join(WORK, "training_parameters_%s.yaml" % args.name)
    with open(out, "w") as f:
        yaml.dump(cfg, f)
    for e in cfg["features"]:
        print(os.path.basename(e["features_dir"]), e["sampling_weight"], e["truth"],
              "OK" if os.path.isdir(e["features_dir"]) else "MISSING")


if __name__ == "__main__":
    main()
