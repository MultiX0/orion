"""Copies a trained model into wakeword/models and writes its v2 manifest.

The manifest fields come from the evaluation, not from guesswork:
  probability_cutoff   the cutoff on the ROC curve that meets the false
                       accepts per hour target with the lowest false rejection
  sliding_window_size  5, the window length the ROC was measured with
  feature_step_size    10, the frontend step the features were built with
  tensor_arena_size    estimated from the model's own tensors, then checked
                       against the published okay_nabu model, which uses the
                       same architecture and declares 26080

Usage:
    python scripts/export_model.py --phrase orion --name orion
    python scripts/export_model.py --calibrate path/to/okay_nabu.tflite
"""

import argparse
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))
SLIDING_WINDOW = 5
FEATURE_STEP_MS = 10


def parse_roc(path):
    points = []
    with open(path) as f:
        for line in f:
            m = re.match(
                r"Cutoff ([0-9.]+): frr=([0-9.]+); faph=([0-9.]+)", line.strip()
            )
            if m:
                points.append(
                    {
                        "cutoff": float(m.group(1)),
                        "frr": float(m.group(2)),
                        "faph": float(m.group(3)),
                    }
                )
    return points


def choose_cutoff(points, max_faph, max_frr):
    viable = [p for p in points if p["faph"] <= max_faph and p["cutoff"] > 0]
    if not viable:
        # Nothing meets the target, take the lowest false accept rate we have.
        best = min(points, key=lambda p: (p["faph"], p["frr"]))
        return best, False
    best = min(viable, key=lambda p: (p["frr"], -p["cutoff"]))
    return best, best["frr"] <= max_frr


# Fitted on the four released ESPHome v2 models, whose manifests state the
# arena they really need: okay_nabu 26080, hey_jarvis 22860, alexa 22348,
# hey_mycroft 23628.
ARENA_FACTOR = float(os.environ.get("ORION_ARENA_FACTOR", "1.0"))
ARENA_HEADROOM = 4096


def estimate_arena(model_path):
    """Rough tensor arena size for TFLite Micro.

    TFLM keeps every activation the graph produces in one arena, plus the
    streaming model's state variables. This sums the activations an op writes
    (constants live in flash, not the arena), applies a factor fitted on the
    released models, and adds headroom. Too small stops the model loading on
    the board, a few kB too big costs nothing we cannot afford.
    """
    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    details = {t["index"]: t for t in interpreter.get_tensor_details()}

    produced = set()
    for op in interpreter._get_ops_details():
        produced.update(int(i) for i in op["outputs"] if int(i) >= 0)
    for i in interpreter.get_input_details():
        produced.add(int(i["index"]))

    def nbytes(tensor):
        count = 1
        for dim in tensor["shape"]:
            count *= max(int(dim), 1)
        name = tensor["dtype"].__name__
        width = {"int8": 1, "uint8": 1, "bool": 1, "int16": 2, "float16": 2}.get(name, 4)
        return count * width

    activation_bytes = sum(nbytes(details[i]) for i in produced if i in details)
    overhead = 128 * len(details)
    total = activation_bytes + overhead
    size = int(total * ARENA_FACTOR + ARENA_HEADROOM)
    size = (size + 1023) // 1024 * 1024
    return size, {
        "tensors": len(details),
        "activations": len(produced),
        "activation_bytes": activation_bytes,
        "raw_total": total,
    }


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--calibrate", help="print the arena estimate for a model and exit")
    parser.add_argument("--phrase")
    parser.add_argument("--name")
    parser.add_argument("--wake-word", default="Orion")
    parser.add_argument("--max-faph", type=float, default=0.5)
    parser.add_argument("--max-frr", type=float, default=0.05)
    parser.add_argument("--arena", type=int, default=None, help="override the estimate")
    args = parser.parse_args()

    if args.calibrate:
        size, detail = estimate_arena(args.calibrate)
        print(args.calibrate, "->", size, detail)
        return

    trained = os.path.join(
        WORK, "trained_models", args.phrase, "tflite_stream_state_internal_quant"
    )
    tflite_src = os.path.join(trained, "stream_state_internal_quant.tflite")
    roc_path = os.path.join(trained, "tflite_streaming_roc.txt")

    points = parse_roc(roc_path)
    best, meets = choose_cutoff(points, args.max_faph, args.max_frr)
    arena, detail = estimate_arena(tflite_src)
    if args.arena:
        arena = args.arena

    models_dir = os.path.join(HERE, "models")
    os.makedirs(models_dir, exist_ok=True)
    out_tflite = os.path.join(models_dir, args.name + ".tflite")
    shutil.copyfile(tflite_src, out_tflite)

    manifest = {
        "type": "micro",
        "wake_word": args.wake_word,
        "author": "Orion project",
        "website": "https://github.com/MultiX0",
        "model": args.name + ".tflite",
        "trained_languages": ["ar", "en"],
        "version": 2,
        "micro": {
            "probability_cutoff": round(best["cutoff"], 2),
            "sliding_window_size": SLIDING_WINDOW,
            "feature_step_size": FEATURE_STEP_MS,
            "tensor_arena_size": arena,
            "minimum_esphome_version": "2024.7.0",
        },
    }
    out_json = os.path.join(models_dir, args.name + ".json")
    with open(out_json, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print("model:", out_tflite, os.path.getsize(out_tflite), "bytes")
    print("manifest:", out_json)
    print("cutoff %.2f frr %.4f faph %.3f meets target: %s"
          % (best["cutoff"], best["frr"], best["faph"], meets))
    print("arena estimate", arena, detail)


if __name__ == "__main__":
    main()
