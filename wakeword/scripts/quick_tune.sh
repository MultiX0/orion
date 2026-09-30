#!/usr/bin/env bash
# Short fine-tune without the in-training validation, which with the round
# two sets added ran past 10 minutes and filled RAM. The trainer saves
# last_weights just before it validates; this copies that file to <out> and
# stops the trainer there. Evaluate the copy with eval_weights.sh.
#   bash scripts/quick_tune.sh <name> <from.weights.h5> <steps> <rate> <out.weights.h5>
set -u
NAME=$1; FROM=$2; STEPS=$3; RATE=$4; OUT=$5
WW=$(cd "$(dirname "$0")/.." && pwd)
PY=~/orion_ww/.venv/bin/python
TD=~/orion_ww/trained_models/$NAME
$PY $WW/scripts/r2_config.py --name $NAME --steps $STEPS --rate $RATE --eval $STEPS ${EXTRA_ARGS:-}
rm -rf $TD; LOG=~/orion_ww/train_$NAME.log; rm -f $LOG
tmux new-session -d -s train_$NAME "export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=0 TF_FORCE_GPU_ALLOW_GROWTH=true TF_GPU_ALLOCATOR=cuda_malloc_async TF_CPP_MIN_LOG_LEVEL=1; cd ~/orion_ww; $PY $WW/scripts/fine_tune.py --config ~/orion_ww/training_parameters_$NAME.yaml --weights $FROM > $LOG 2>&1"
until [ -f $TD/last_weights.weights.h5 ]; do sleep 3; done
sleep 5
cp $TD/last_weights.weights.h5 $OUT
tmux kill-session -t train_$NAME
echo QUICK_DONE $NAME $OUT
