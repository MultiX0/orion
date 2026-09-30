#!/usr/bin/env bash
# Exports and scores every checkpoint a training run saves, on the CPU while
# the GPU keeps training, and appends one line per checkpoint to a CSV.
# Selects checkpoints by name, never by mtime: timestamps on /mnt/c drift
# between WSL and Windows and the train log is appended every step.
#
#   bash scripts/scout.sh <train_name> <phrase> <positive holdout dir> <train log>
#   bash scripts/scout.sh orion_ft orion data/holdout/orion ~/orion_ww/train_orion_ft.log
set -u
TRAIN_NAME=$1; PHRASE=$2; POS=$3; LOG=$4
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=-1 TF_CPP_MIN_LOG_LEVEL=2
PY=$WORK/.venv/bin/python
TRAIN=$WORK/trained_models/$TRAIN_NAME/train
SNAP=$WORK/snapshots
OUT=$WW/work/scout_$TRAIN_NAME
mkdir -p "$SNAP" "$OUT"
CSV=$OUT/scout.csv
[ -f "$CSV" ] || echo "step,cutoff,frr_pct,holdout_fa,meets,tflite_bytes,arena" > "$CSV"
cd "$WW"

score_one() {
  local f=$1 step=$2 name=${TRAIN_NAME}_step$2
  [ -f "$OUT/step$step.done" ] && return
  sleep 5
  cp "$f" "$SNAP/$name.weights.h5"
  echo "=== $(date +%T) export $name"
  $PY scripts/export_early.py --phrase "$PHRASE" --weights "$SNAP/$name.weights.h5" \
    --name "$name" --out-dir "$OUT" > "$OUT/$name.export.log" 2>&1 \
    || { echo "EXPORT_FAILED $step"; tail -5 "$OUT/$name.export.log"; touch "$OUT/step$step.done"; return; }
  $PY scripts/evaluate.py --model "$OUT/$name.tflite" --cutoff 0.9 --positive "$POS" \
    --negative data/holdout/negative --save-scores "$OUT/$name.scores.json" > "$OUT/$name.eval.log" 2>&1
  $PY scripts/pick_cutoff.py --scores "$OUT/$name.scores.json" --manifest "$OUT/$name.json" > "$OUT/$name.cutoff.log" 2>&1
  local line cutoff frr fa meets bytes arena
  line=$(grep "^chosen" "$OUT/$name.cutoff.log")
  cutoff=$(echo "$line" | sed 's/chosen cutoff \([0-9.]*\):.*/\1/')
  frr=$(echo "$line" | sed 's/.*frr \([0-9.]*\)%.*/\1/')
  fa=$(echo "$line" | sed 's/.*false accepts \([0-9]*\),.*/\1/')
  meets=$(echo "$line" | sed 's/.*meets target: \(.*\)/\1/')
  bytes=$(stat -c %s "$OUT/$name.tflite")
  arena=$($PY -c "import json;print(json.load(open('$OUT/$name.json'))['micro']['tensor_arena_size'])")
  echo "$step,$cutoff,$frr,$fa,$meets,$bytes,$arena" >> "$CSV"
  echo "SCOUT $TRAIN_NAME step=$step cutoff=$cutoff frr=$frr% fa=$fa meets=$meets"
  touch "$OUT/step$step.done"
}

while true; do
  for f in $(ls "$TRAIN"/*_weights_*.weights.h5 2>/dev/null); do
    step=$(basename "$f" | sed 's/.*_weights_\([0-9]*\)\.weights\.h5/\1/')
    score_one "$f" "$step"
  done
  if grep -q "TRAIN_EXIT" "$LOG" 2>/dev/null; then
    # One last pass for the checkpoints written at the very end.
    for f in $(ls "$TRAIN"/*_weights_*.weights.h5 2>/dev/null); do
      step=$(basename "$f" | sed 's/.*_weights_\([0-9]*\)\.weights\.h5/\1/')
      score_one "$f" "$step"
    done
    [ -f "$WORK/trained_models/$TRAIN_NAME/best_weights.weights.h5" ] && \
      score_one "$WORK/trained_models/$TRAIN_NAME/best_weights.weights.h5" best
    echo SCOUT_DONE; exit 0
  fi
  sleep 20
done
