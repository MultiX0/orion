"""Exports a quantized streaming TFLite model from any saved weights file.

The trainer only converts to TFLite at the very end of its run. This does the
same conversion for a checkpoint taken mid run, so a usable model can go to the
board while the full schedule keeps training. It works in its own directory
under trained_models/<name>/ and never writes into the live training directory,
and it stays on the CPU so it cannot take GPU memory from a running trainer.

The cutoff in the manifest is a placeholder. pick_cutoff.py sets it from the
holdout sweep, because the ROC the trainer measures does not exist yet.

Usage:
    python scripts/export_early.py --phrase orion \
        --weights ~/orion_ww/snapshots/orion_best.weights.h5 --name orion_early
"""

import argparse
import json
import os
import shutil
import sys

# Must be set before tensorflow is imported. The trainer holds the GPU.
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import yaml  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))
sys.path.insert(0, os.path.join(HERE, "scripts"))

# The same architecture flags train.sh passes. They must match the weights.
MIXEDNET_ARGS = [
    "--pointwise_filters", "64,64,64,64",
    "--repeat_in_block", "1,1,1,1",
    "--mixconv_kernel_sizes", "[5],[7,11],[9,15],[23]",
    "--residual_connection", "0,0,0,0",
    "--first_conv_filters", "32",
    "--first_conv_kernel_size", "5",
    "--stride", "3",
]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--phrase", required=True)
    parser.add_argument("--weights", required=True, help="a .weights.h5 file")
    parser.add_argument("--name", required=True)
    parser.add_argument("--wake-word", default="Orion")
    parser.add_argument("--out-dir", default=None, help="defaults to wakeword/models")
    args = parser.parse_args()

    from microwakeword import mixednet, utils
    from microwakeword import data as input_data
    from microwakeword.layers import modes
    from microwakeword.model_train_eval import load_config
    import export_model

    out_root = os.path.join(WORK, "trained_models", args.name)
    os.makedirs(out_root, exist_ok=True)

    # Same training parameters, but every output path points at out_root.
    source_config = os.path.join(WORK, "training_parameters_%s.yaml" % args.phrase)
    with open(source_config) as f:
        params = yaml.safe_load(f)
    params["train_dir"] = out_root
    config_path = os.path.join(out_root, "training_parameters.yaml")
    with open(config_path, "w") as f:
        yaml.dump(params, f)

    model_parser = argparse.ArgumentParser()
    mixednet.model_parameters(model_parser)
    flags = model_parser.parse_args(MIXEDNET_ARGS)
    flags.training_config = config_path
    config = load_config(flags, mixednet)

    model = mixednet.model(flags, shape=config["training_input_shape"], batch_size=1)
    model.load_weights(args.weights)
    print("loaded", args.weights, flush=True)

    utils.convert_model_saved(
        model, config, folder="stream_state_internal",
        mode=modes.Modes.STREAM_INTERNAL_STATE_INFERENCE,
    )
    audio_processor = input_data.FeatureHandler(config)
    tflite_dir = os.path.join(out_root, "tflite_stream_state_internal_quant")
    utils.convert_saved_model_to_tflite(
        config, audio_processor,
        path_to_model=os.path.join(out_root, "stream_state_internal"),
        folder=tflite_dir,
        fname="stream_state_internal_quant.tflite",
        quantize=True,
    )
    tflite_src = os.path.join(tflite_dir, "stream_state_internal_quant.tflite")

    models_dir = args.out_dir or os.path.join(HERE, "models")
    if not os.path.isabs(models_dir):
        models_dir = os.path.join(HERE, models_dir)
    os.makedirs(models_dir, exist_ok=True)
    out_tflite = os.path.join(models_dir, args.name + ".tflite")
    shutil.copyfile(tflite_src, out_tflite)
    arena, detail = export_model.estimate_arena(out_tflite)

    manifest = {
        "type": "micro",
        "wake_word": args.wake_word,
        "author": "Orion project",
        "website": "https://github.com/MultiX0",
        "model": args.name + ".tflite",
        "trained_languages": ["ar", "en"],
        "version": 2,
        "micro": {
            "probability_cutoff": 0.99,
            "sliding_window_size": export_model.SLIDING_WINDOW,
            "feature_step_size": export_model.FEATURE_STEP_MS,
            "tensor_arena_size": arena,
            "minimum_esphome_version": "2024.7.0",
        },
    }
    out_json = os.path.join(models_dir, args.name + ".json")
    with open(out_json, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("model:", out_tflite, os.path.getsize(out_tflite), "bytes")
    print("manifest:", out_json, "arena", arena, detail)


if __name__ == "__main__":
    main()
