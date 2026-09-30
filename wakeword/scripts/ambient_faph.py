"""False accepts per hour on the ambient test set, at every cutoff, for any
quantized streaming TFLite model.

The trainer's own ROC only lists cutoffs until false accepts per hour reach
2.0, so a model that is noisy on ambient speech shows two lines and nothing
at the cutoff the manifest uses. This runs the same measurement (upstream's
compute_false_accepts_per_hour over dinner_party_eval's testing_ambient, with
the 5 window sliding average and the 25 slice cooldown) and prints the whole
table, plus false rejection on the trainer's augmented test positives.

Usage:
    python scripts/ambient_faph.py --config ~/orion_ww/training_parameters_orion.yaml \
        --tflite work/scout_orion_ft/orion_ft_step500.tflite [--no-positives]
"""

import argparse
import os
import sys

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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
    parser.add_argument("--config", required=True)
    parser.add_argument("--tflite", required=True)
    parser.add_argument("--no-positives", action="store_true")
    parser.add_argument("--cutoffs", default="0.80,0.85,0.88,0.90,0.92,0.95,0.97,0.98,0.99")
    args = parser.parse_args()

    from numpy.lib.stride_tricks import sliding_window_view
    from microwakeword import mixednet
    from microwakeword import data as input_data
    from microwakeword.inference import Model
    from microwakeword.model_train_eval import load_config
    from microwakeword.test import compute_false_accepts_per_hour

    model_parser = argparse.ArgumentParser()
    mixednet.model_parameters(model_parser)
    flags = model_parser.parse_args(MIXEDNET_ARGS)
    flags.training_config = os.path.expanduser(args.config)
    config = load_config(flags, mixednet)
    processor = input_data.FeatureHandler(config)

    tflite = args.tflite if os.path.isabs(args.tflite) else os.path.join(HERE, args.tflite)
    model = Model(tflite, stride=config["stride"])
    window = 5
    cooldown = 25

    ambient, _, _ = processor.get_data(
        "testing_ambient", batch_size=config["batch_size"],
        features_length=config["spectrogram_length"], truncation_strategy="none",
    )
    tracks = []
    seconds = 0.0
    for track in ambient:
        probabilities = model.predict_spectrogram(track)
        tracks.append(sliding_window_view(probabilities, window).mean(axis=-1))
        seconds += len(probabilities) * config["stride"] * config["window_step_ms"] / 1000
    cutoffs = np.array([float(c) for c in args.cutoffs.split(",")])
    faph = compute_false_accepts_per_hour(
        tracks, cutoffs, cooldown, stride=config["stride"],
        step_s=config["window_step_ms"] / 1000,
    )
    print("ambient: %d tracks, %.2f hours" % (len(tracks), seconds / 3600))

    frr = None
    if not args.no_positives:
        fingerprints, truth, _ = processor.get_data(
            "testing", batch_size=config["batch_size"],
            features_length=config["spectrogram_length"], truncation_strategy="none",
        )
        peaks = []
        for spectrogram, is_positive in zip(fingerprints, truth):
            if not is_positive:
                continue
            probabilities = model.predict_spectrogram(spectrogram)
            peaks.append(sliding_window_view(probabilities[cooldown:], window).mean(axis=-1).max())
        peaks = np.array(peaks)
        frr = [(peaks <= c).mean() for c in cutoffs]
        print("augmented test positives: %d" % len(peaks))

    print("cutoff  faph    " + ("frr_augmented" if frr else ""))
    for i, c in enumerate(cutoffs):
        print("%.2f    %6.3f  %s" % (c, faph[i], ("%.4f" % frr[i]) if frr else ""))


if __name__ == "__main__":
    main()
