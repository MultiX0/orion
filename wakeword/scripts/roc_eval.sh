#!/usr/bin/env bash
# Runs the trainer's own test on any weights file: converts to the quantized
# streaming TFLite model and measures false rejection on the augmented test
# positives and false accepts per hour on the ambient test set, the two
# numbers the wake word target is written in. Writes into
# trained_models/<train_name>/tflite_stream_state_internal_quant/.
#
#   bash scripts/roc_eval.sh <train_name> <weights.h5>
#   bash scripts/roc_eval.sh orion_ft2 ~/orion_ww/trained_models/orion_ft2/train/0_weights_2000.weights.h5
set -eu
TRAIN_NAME=$1; WEIGHTS=$2
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
PY=$WORK/.venv/bin/python
CONFIG=$WORK/training_parameters_$TRAIN_NAME.yaml
TRAIN_DIR=$WORK/trained_models/$TRAIN_NAME
export PYTHONPATH=${PYTHONPATH:+$PYTHONPATH:}$WW/work/mww
export TF_CPP_MIN_LOG_LEVEL=1
# Stays on the CPU so a trainer on the GPU is not disturbed.
export CUDA_VISIBLE_DEVICES=-1
cp "$WEIGHTS" "$TRAIN_DIR/roc_weights.weights.h5"
cd "$WORK"
$PY -m microwakeword.model_train_eval \
  --training_config="$CONFIG" \
  --train 0 \
  --restore_checkpoint 1 \
  --test_tf_nonstreaming 0 \
  --test_tflite_nonstreaming 0 \
  --test_tflite_nonstreaming_quantized 0 \
  --test_tflite_streaming 0 \
  --test_tflite_streaming_quantized 1 \
  --use_weights "roc_weights" \
  mixednet \
  --pointwise_filters "64,64,64,64" \
  --repeat_in_block "1,1,1,1" \
  --mixconv_kernel_sizes '[5],[7,11],[9,15],[23]' \
  --residual_connection "0,0,0,0" \
  --first_conv_filters 32 \
  --first_conv_kernel_size 5 \
  --stride 3
echo "=== roc for $WEIGHTS"
cat "$TRAIN_DIR/tflite_stream_state_internal_quant/tflite_streaming_roc.txt"
