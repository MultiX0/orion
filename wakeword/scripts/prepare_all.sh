#!/usr/bin/env bash
# Everything between "the clips exist" and "the trainer can start":
# trim and filter the clips, set a holdout aside, then build the feature sets.
set -eu
WW=$(cd "$(dirname "$0")/.." && pwd)
PY=${ORION_WW_PY:-$HOME/orion_ww/.venv/bin/python}
export TF_CPP_MIN_LOG_LEVEL=2
# See the note in train.sh: the editable install's recorded path is stale.
export PYTHONPATH=${PYTHONPATH:+$PYTHONPATH:}$WW/work/mww
cd "$WW"

echo "=== trim and filter ==="
$PY scripts/qc_clips.py --dirs \
  data/fish/orion data/fish/hey_orion data/fish/confusable \
  data/piper/orion data/piper/hey_orion data/piper/negative

echo "=== holdout, one clip in twenty ==="
for pair in "data/fish/orion:data/holdout/orion" \
            "data/piper/orion:data/holdout/orion" \
            "data/fish/hey_orion:data/holdout/hey_orion" \
            "data/piper/hey_orion:data/holdout/hey_orion" \
            "data/fish/confusable:data/holdout/negative" \
            "data/piper/negative:data/holdout/negative"; do
  $PY scripts/make_holdout.py --source "${pair%%:*}" --out "${pair##*:}" --every 20
done

echo "=== features ==="
$PY scripts/make_features.py --name orion_positive --truth \
  --dirs data/fish/orion data/piper/orion
$PY scripts/make_features.py --name adversarial --slide 5 \
  --dirs data/fish/confusable data/piper/negative
$PY scripts/make_features.py --name music --split-seconds 10 \
  --dirs "$HOME/orion_ww/fma_16k"

echo "=== sizes ==="
du -sh "$HOME"/orion_ww/features/*
df -h /mnt/c | tail -1
