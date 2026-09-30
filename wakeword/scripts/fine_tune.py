"""Continues training from a saved weights file with its own schedule.

The upstream trainer only restores from the checkpoint in its own train_dir,
and a restore replays the whole step schedule from step 1, so stage one's high
learning rate lands on an already trained model. This builds the model the same
way train.sh does, loads any .weights.h5, and hands it to upstream's train loop
with the config given, so a stage two schedule can run on stage one weights.

Usage:
    python scripts/fine_tune.py --config ~/orion_ww/training_parameters_orion_ft.yaml \
        --weights ~/orion_ww/snapshots/orion_step4000.weights.h5
"""

import argparse
import os
import sys

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "1")

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

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
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--weights", required=True)
    args = parser.parse_args()

    from absl import logging
    from microwakeword import mixednet, train, utils
    from microwakeword import data as input_data
    from microwakeword.model_train_eval import load_config

    logging.set_verbosity(logging.INFO)

    model_parser = argparse.ArgumentParser()
    mixednet.model_parameters(model_parser)
    flags = model_parser.parse_args(MIXEDNET_ARGS)
    flags.training_config = args.config
    config = load_config(flags, mixednet)

    data_processor = input_data.FeatureHandler(config)
    model = mixednet.model(flags, config["training_input_shape"], config["batch_size"])
    model.load_weights(args.weights)
    print("loaded", args.weights, flush=True)

    os.makedirs(config["summaries_dir"], exist_ok=True)
    utils.save_model_summary(model, config["train_dir"])
    train.train(model, config, data_processor)
    print("FINE_TUNE_DONE", flush=True)


if __name__ == "__main__":
    main()
