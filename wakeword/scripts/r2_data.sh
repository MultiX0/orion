#!/usr/bin/env bash
# Builds the quiet evaluation and training clips, then scores the shipped model.
set -u
cd ~/orion_ww/r2
sed -i 's/\r$//' scripts/*.py scripts/*.sh
PY=~/orion_ww/.venv/bin/python
export PYTHONPATH=~/orion_ww/r2/work/mww CUDA_VISIBLE_DEVICES=-1 TF_CPP_MIN_LOG_LEVEL=2
SRC="${ORION_WW_SRC:-/mnt/c/path/to/orion/wakeword}"  # the repo wakeword folder, seen from WSL
mkdir -p base
cp -n $SRC/work/scout_orion_full2/orion_full2_step9000.tflite $SRC/work/scout_orion_full2/orion_full2_step9000.json base/ 2>/dev/null
for d in holdout/negative holdout/negative_fish holdout/orion fish/negative fish/confusable fish/orion piper/negative piper/orion; do echo "$d $(ls data/$d | wc -l)"; done
# evaluation sets, from held-out audio only
$PY scripts/make_quiet.py --src data/holdout/orion --out data/quiet_eval/pos_old --snr 3 12 --lead 1.0 --tail 0.3 --seed 11
$PY scripts/make_quiet.py --src data/holdout/orion_r2 --out data/quiet_eval/pos_r2 --snr 3 12 --lead 1.0 --tail 0.3 --seed 12
$PY scripts/make_quiet.py --src data/holdout/negative data/holdout/negative_fish --out data/quiet_eval/neg_speech --snr -3 12 --lead 1.0 --tail 0.3 --copies 2 --seed 13
$PY scripts/make_quiet.py --synth 600 --out data/quiet_eval/neg_sounds --snr 0 20 --lead 1.0 --tail 0.3 --seed 14
# training sets, from training audio only
$PY scripts/make_quiet.py --src data/fish/negative data/fish/confusable data/piper/negative --out data/quiet/neg_speech --snr -3 15 --lead 0.3 --max 3000 --seed 21
$PY scripts/make_quiet.py --synth 1500 --out data/quiet/neg_sounds --snr 0 20 --lead 0.3 --seed 22
until grep -q FISH_R2_DONE ~/orion_ww/fish_r2.log; do sleep 10; done
$PY scripts/make_quiet.py --src data/fish/orion_r2 data/fish/orion --out data/quiet/pos --snr 3 15 --lead 0.3 --max 1500 --seed 23
echo DATA_DONE
$PY scripts/eval_r2.py --models base/orion_full2_step9000.tflite --cutoffs 0.9 0.95 0.97
echo BASE_EVAL_DONE
