#!/usr/bin/env bash
# Starts a full training run in a detached tmux session so it outlives the
# wsl.exe call that launched it, with a scout beside it scoring every
# checkpoint on the holdout. Stop a run with `tmux kill-session -t train_<phrase>`
# and append TRAIN_EXIT to its log so the scout finishes; pkill on the python
# command line also kills the wrapper shell that writes that marker.
#
#   bash scripts/train_start.sh <phrase> [restore 0|1]
set -eu
PHRASE=$1
RESTORE=${2:-0}
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
LOG=$WORK/train_$PHRASE.log
if [ -f "$LOG" ]; then
  n=1; while [ -f "$WORK/train_${PHRASE}_run${n}.log" ]; do n=$((n+1)); done
  mv "$LOG" "$WORK/train_${PHRASE}_run${n}.log"
fi
rm -rf "$WW/work/scout_$PHRASE"
tmux new-session -d -s "train_$PHRASE" \
  "export RESTORE=$RESTORE TF_FORCE_GPU_ALLOW_GROWTH=true; bash $WW/scripts/train.sh $PHRASE > $LOG 2>&1; echo TRAIN_EXIT=\$? >> $LOG"
tmux new-session -d -s "scout_$PHRASE" \
  "bash $WW/scripts/scout.sh $PHRASE $PHRASE data/holdout/$PHRASE $LOG > $WORK/scout_$PHRASE.log 2>&1"
sleep 3
tmux ls
pgrep -af model_train_eval || true
