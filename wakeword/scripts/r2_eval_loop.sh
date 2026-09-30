#!/usr/bin/env bash
# Runs eval_r2.py on every checkpoint the scout exports for a run.
#   bash scripts/r2_eval_loop.sh <train_name>
set -u
NAME=$1
WW=$(cd "$(dirname "$0")/.." && pwd)
export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=-1 TF_CPP_MIN_LOG_LEVEL=2
PY=~/orion_ww/.venv/bin/python
OUT=$WW/work/scout_$NAME
cd "$WW"
while true; do
  for f in $(ls "$OUT"/step*.done 2>/dev/null); do
    step=$(basename "$f" | sed 's/step\(.*\)\.done/\1/')
    t=$OUT/${NAME}_step$step.tflite
    [ -f "$t" ] && [ ! -f "$OUT/step$step.r2" ] && \
      $PY scripts/eval_r2.py --models "$t" --cutoffs 0.9 0.95 0.97 | grep -v "^model" && touch "$OUT/step$step.r2"
  done
  grep -q SCOUT_DONE ~/orion_ww/scout_$NAME.log 2>/dev/null && [ -z "$(ls $OUT/step*.done 2>/dev/null | sed 's/done$/r2/' | xargs -r ls 2>&1 | grep 'No such')" ] && { echo R2_DONE; exit 0; }
  sleep 30
done
