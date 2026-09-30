#!/usr/bin/env bash
# Starts a fine-tune from saved weights in a detached tmux session, with a
# scout beside it that scores every checkpoint on the holdout.
#
#   bash scripts/finetune_start.sh <train_name> <phrase> <weights.h5> <steps> <rate> [neg weight]
#   bash scripts/finetune_start.sh orion_ft orion ~/orion_ww/trained_models/orion/train/0_weights_4000.weights.h5 2500 0.0002
set -eu
TRAIN_NAME=$1; PHRASE=$2; WEIGHTS=$3; STEPS=$4; RATE=$5; NEGW=${6:-20}
# EVAL_INTERVAL=1000 halves the validation cost; CUDA_VISIBLE_DEVICES=-1 runs
# on the CPU when the GPU is holding another trainer.
EVAL_INTERVAL=${EVAL_INTERVAL:-500}
DEVICES=${CUDA_VISIBLE_DEVICES:-0}
# Optional seventh argument: extra negative feature sets as name:weight, space separated.
EXTRA=""
for e in ${7:-}; do EXTRA="$EXTRA --extra-set $e"; done
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
PY=$WORK/.venv/bin/python
export PYTHONPATH=$WW/work/mww
LOG=$WORK/train_$TRAIN_NAME.log
CONFIG=$WORK/training_parameters_$TRAIN_NAME.yaml

$PY "$WW/scripts/make_config.py" --phrase "$PHRASE" --train-name "$TRAIN_NAME" \
  --steps "$STEPS" --rates "$RATE" --negative-weight "$NEGW" --eval-interval "$EVAL_INTERVAL" --mask-all $EXTRA
rm -rf "$WORK/trained_models/$TRAIN_NAME" "$WW/work/scout_$TRAIN_NAME"
rm -f "$LOG"
# See train.sh: upstream validates with batch 1024, which does not fit this GPU.
sed -i 's/batch_size=1024,/batch_size=256,/' "$WW/work/mww/microwakeword/train.py"

tmux new-session -d -s "train_$TRAIN_NAME" \
  "export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=$DEVICES TF_FORCE_GPU_ALLOW_GROWTH=true TF_GPU_ALLOCATOR=cuda_malloc_async TF_CPP_MIN_LOG_LEVEL=1; cd $WORK; $PY $WW/scripts/fine_tune.py --config $CONFIG --weights $WEIGHTS > $LOG 2>&1; echo TRAIN_EXIT=\$? >> $LOG"
tmux new-session -d -s "scout_$TRAIN_NAME" \
  "bash $WW/scripts/scout.sh $TRAIN_NAME $PHRASE data/holdout/$PHRASE $LOG > $WORK/scout_$TRAIN_NAME.log 2>&1"
sleep 5
tmux ls
pgrep -af "fine_tune|scout.sh" || true
