"""Runs a trained model over real WAV files and reports what it does.

The training run already measures false rejection and false accepts per hour on
spectrogram sets. This is the second opinion: it takes the quantized streaming
model that ships, feeds it whole audio files the way the board will, applies the
same sliding window average the firmware applies, and prints the highest
probability each file reached.

Used for two things: checking the shipped cutoff against held out clips, and
picking the ten positive and ten negative clips committed for the firmware side
to replay.

Usage:
    python scripts/evaluate.py --model models/orion.tflite --cutoff 0.95 \
        --positive data/holdout/orion --negative data/holdout/negative
"""

import argparse
import json
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_clip(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != 16000:
            raise ValueError("not 16 kHz mono 16-bit: " + path)
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def score_dir(model, directory, window, limit=None):
    from numpy.lib.stride_tricks import sliding_window_view

    rows = []
    files = sorted(f for f in os.listdir(directory) if f.endswith(".wav"))
    if limit:
        files = files[:limit]
    for name in files:
        samples = read_clip(os.path.join(directory, name))
        probabilities = np.array(model.predict_clip(samples, step_ms=10))
        if probabilities.size < window:
            rows.append((name, 0.0, samples.size / 16000))
            continue
        averaged = sliding_window_view(probabilities, window).mean(axis=-1)
        rows.append((name, float(averaged.max()), samples.size / 16000))
    return rows


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--cutoff", type=float, default=0.95)
    parser.add_argument("--window", type=int, default=5)
    parser.add_argument("--stride", type=int, default=3)
    parser.add_argument("--positive", nargs="*", default=[])
    parser.add_argument("--negative", nargs="*", default=[])
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--save-scores", default=None)
    args = parser.parse_args()

    from microwakeword.inference import Model

    model_path = args.model if os.path.isabs(args.model) else os.path.join(HERE, args.model)
    model = Model(model_path, stride=args.stride)

    report = {"model": os.path.basename(model_path), "cutoff": args.cutoff}
    for label, dirs in (("positive", args.positive), ("negative", args.negative)):
        all_rows = []
        for directory in dirs:
            path = directory if os.path.isabs(directory) else os.path.join(HERE, directory)
            if not os.path.isdir(path):
                print("missing:", path)
                continue
            rows = score_dir(model, path, args.window, args.limit)
            all_rows.extend((os.path.relpath(path, HERE) + "/" + n, s, d) for n, s, d in rows)
        if not all_rows:
            continue
        scores = np.array([s for _, s, _ in all_rows])
        fired = scores > args.cutoff
        if label == "positive":
            rate = 1 - fired.mean()
            print(
                "positives: %d clips, false rejection %.2f%% at cutoff %.2f, "
                "score mean %.3f median %.3f p05 %.3f"
                % (
                    len(all_rows),
                    rate * 100,
                    args.cutoff,
                    scores.mean(),
                    np.median(scores),
                    np.percentile(scores, 5),
                )
            )
            report["positive_count"] = len(all_rows)
            report["false_rejection"] = float(rate)
        else:
            rate = fired.mean()
            print(
                "negatives: %d clips, false accepts %.2f%% at cutoff %.2f, "
                "score mean %.3f max %.3f p95 %.3f"
                % (
                    len(all_rows),
                    rate * 100,
                    args.cutoff,
                    scores.mean(),
                    scores.max(),
                    np.percentile(scores, 95),
                )
            )
            report["negative_count"] = len(all_rows)
            report["false_accept_rate"] = float(rate)
        report[label + "_scores"] = [
            {"file": n, "score": round(s, 4), "seconds": round(d, 2)}
            for n, s, d in all_rows
        ]

    if args.save_scores:
        with open(args.save_scores, "w") as f:
            json.dump(report, f, indent=1)
        print("scores written to", args.save_scores)


if __name__ == "__main__":
    main()
