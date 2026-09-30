#!/usr/bin/env bash
# Exports one weights file and runs every yardstick on it: the old holdout
# with pick_cutoff, eval_r2.py, ambient false accepts and unseen noise.
#   bash scripts/eval_weights.sh <weights.h5> <name>
set -u
W=$1; NAME=$2
WW=$(cd "$(dirname "$0")/.." && pwd)
export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=-1 TF_CPP_MIN_LOG_LEVEL=2
PY=~/orion_ww/.venv/bin/python
OUT=$WW/work/manual; mkdir -p $OUT; cd $WW
cp "$W" $OUT/$NAME.weights.h5
$PY scripts/export_early.py --phrase orion --weights $OUT/$NAME.weights.h5 --name $NAME --out-dir $OUT > $OUT/$NAME.export.log 2>&1 || { echo EXPORT_FAILED; tail -3 $OUT/$NAME.export.log; exit 1; }
$PY scripts/eval_r2.py --models $OUT/$NAME.tflite --cutoffs 0.9 0.95 0.97 | grep -v "^model"
$PY scripts/ambient_faph.py --config ~/orion_ww/training_parameters_orion.yaml --tflite $OUT/$NAME.tflite --cutoffs 0.9,0.95,0.97 > $OUT/$NAME.faph.log 2>&1
grep -E "^0\.[0-9]+ " $OUT/$NAME.faph.log | sed "s/^/ambient $NAME /"
$PY scripts/silence_test.py --minutes 1 --mmap-limit 2000 --mmap ~/orion_ww/negative_datasets/unseen/fsd50k_no_speech_mmap --models $OUT/$NAME.tflite > $OUT/$NAME.noise.log 2>&1
grep fsd50k $OUT/$NAME.noise.log | sed "s/^/noise $NAME /"
echo EVAL_DONE $NAME
