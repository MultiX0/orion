#!/usr/bin/env bash
# Follows a run's scout and, for every checkpoint it has scored, measures the
# two numbers the holdout cannot give: ambient false accepts per hour on
# dinner_party_eval and detections per hour on unseen no-speech sounds.
# Appends one block per checkpoint to work/scout_<run>/fulleval.log and one
# summary line to work/scout_<run>/fulleval.csv.
#
#   bash scripts/auto_eval.sh <train_name> <config phrase> <train log>
#   bash scripts/auto_eval.sh orion_ft5 orion ~/orion_ww/train_orion_ft5.log
set -u
TRAIN_NAME=$1; PHRASE=$2; LOG=$3
WW=$(cd "$(dirname "$0")/.." && pwd)
WORK=${ORION_WW_WORK:-$HOME/orion_ww}
export PYTHONPATH=$WW/work/mww CUDA_VISIBLE_DEVICES=-1 TF_CPP_MIN_LOG_LEVEL=2
PY=$WORK/.venv/bin/python
OUT=$WW/work/scout_$TRAIN_NAME
UNSEEN=$WORK/negative_datasets/unseen/fsd50k_no_speech_mmap
CSV=$OUT/fulleval.csv
cd "$WW"
mkdir -p "$OUT"
[ -f "$CSV" ] || echo "step,faph_0.88,frr_aug_0.88,faph_0.95,frr_aug_0.95,faph_0.98,frr_aug_0.98,noise_0.88,noise_0.95,noise_0.98" > "$CSV"

eval_one() {
  local step=$1 name=${TRAIN_NAME}_step$1
  [ -f "$OUT/$name.tflite" ] || return
  [ -f "$OUT/step$step.fulleval" ] && return
  echo "=== $(date +%T) $name" >> "$OUT/fulleval.log"
  $PY scripts/ambient_faph.py --config "$WORK/training_parameters_$PHRASE.yaml" \
    --tflite "$OUT/$name.tflite" --cutoffs 0.88,0.95,0.98 > "$OUT/$name.faph.log" 2>&1
  $PY scripts/silence_test.py --minutes 1 --mmap-limit 2000 --mmap "$UNSEEN" \
    --models "$OUT/$name.tflite" > "$OUT/$name.noise.log" 2>&1
  grep -E "^0\.[0-9]+ " "$OUT/$name.faph.log" >> "$OUT/fulleval.log"
  grep fsd50k "$OUT/$name.noise.log" >> "$OUT/fulleval.log"
  local faph noise
  faph=$(grep -E "^0\.[0-9]+ " "$OUT/$name.faph.log" | awk '{printf "%s,%s,", $2, $3}')
  noise=$(grep fsd50k "$OUT/$name.noise.log" | awk '{printf "%s,%s,%s", $3, $4, $5}')
  echo "$step,$faph$noise" >> "$CSV"
  echo "FULLEVAL $TRAIN_NAME step=$step $faph$noise"
  touch "$OUT/step$step.fulleval"
}

while true; do
  for f in $(ls "$OUT"/step*.done 2>/dev/null); do
    step=$(basename "$f" | sed 's/step\(.*\)\.done/\1/')
    eval_one "$step"
  done
  if grep -q SCOUT_DONE "$WORK/scout_$TRAIN_NAME.log" 2>/dev/null; then
    for f in $(ls "$OUT"/step*.done 2>/dev/null); do
      step=$(basename "$f" | sed 's/step\(.*\)\.done/\1/')
      eval_one "$step"
    done
    echo FULLEVAL_DONE; exit 0
  fi
  sleep 30
done
