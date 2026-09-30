#!/usr/bin/env bash
# Trains one microWakeWord model and converts it to a quantized streaming
# TFLite model. Takes the phrase name, which must match the config written by
# make_config.py.
#
#   bash scripts/train.sh orion
#
# The architecture is the one from the upstream notebook: MixedNet with four
# 64 filter blocks and a stride of 3, the same shape as the released okay_nabu
# and hey_jarvis models, so the tensor arena on the board stays small.
set -eu
PHRASE=${1:-orion}
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
PY=$WORK/.venv/bin/python
CONFIG=$WORK/training_parameters_$PHRASE.yaml
RESTORE=${RESTORE:-0}

export TF_CPP_MIN_LOG_LEVEL=1
# microwakeword was pip installed with -e, and an editable install records the
# absolute path of the checkout. Once the tree moves, that recorded path is
# gone and the import fails from any other directory. Pointing PYTHONPATH at
# the checkout fixes it without touching the venv.
export PYTHONPATH=${PYTHONPATH:+$PYTHONPATH:}$WW/work/mww
# Upstream validates with a fixed batch of 1024. On this GPU, which the desktop
# already takes 2 GB of, that ran out of memory at the first evaluation. 256 is
# plenty and costs nothing in accuracy. The sed is a no-op once applied.
sed -i 's/batch_size=1024,/batch_size=256,/' "$WW/work/mww/microwakeword/train.py"
# Reuse freed GPU blocks instead of fragmenting the small arena we get.
export TF_GPU_ALLOCATOR=${TF_GPU_ALLOCATOR:-cuda_malloc_async}
cd "$WORK"

$PY -m microwakeword.model_train_eval \
  --training_config="$CONFIG" \
  --train 1 \
  --restore_checkpoint "$RESTORE" \
  --test_tf_nonstreaming 0 \
  --test_tflite_nonstreaming 0 \
  --test_tflite_nonstreaming_quantized 0 \
  --test_tflite_streaming 0 \
  --test_tflite_streaming_quantized 1 \
  --use_weights "best_weights" \
  mixednet \
  --pointwise_filters "64,64,64,64" \
  --repeat_in_block "1,1,1,1" \
  --mixconv_kernel_sizes '[5],[7,11],[9,15],[23]' \
  --residual_connection "0,0,0,0" \
  --first_conv_filters 32 \
  --first_conv_kernel_size 5 \
  --stride 3

echo "=== results ==="
ls -la "$WORK/trained_models/$PHRASE/tflite_stream_state_internal_quant/"
cat "$WORK/trained_models/$PHRASE/tflite_stream_state_internal_quant/tflite_streaming_roc.txt"
