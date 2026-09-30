# Test clips

Twenty 16 kHz mono 16-bit WAV files in `wakeword/test_clips/`, held out
from training: no clip here ever became a feature the model saw.

Replay them through the PC speakers with `tools/replay_clips.ps1` while the
board listens. The ten `pos_` clips should each fire the wake word once.
The ten `neg_` clips are the hardest negatives the model still rejects, the
ones that scored closest to the cutoff from below, and none of them should fire.

Score is the highest sliding window probability the shipped model gave the
file, measured on the PC with `scripts/evaluate.py`. The manifest cutoff is
0.88, so a positive is detected when its score is above that.

On the whole holdout at this cutoff the model misses 10 of 204 positives and
fires on 22 of 192 confusable negatives. Only clips the PC result agrees with
are listed here, so the replay checks the board against the PC, not the
model against the target.

| file | says | language | engine | seconds | score | expected |
|---|---|---|---|---|---|---|
| pos_01_ar_fish.wav | اوريون | ar | Fish Audio | 1.52 | 0.900 | fires |
| pos_02_ar_piper.wav | أوريون | ar | Piper | 0.42 | 0.997 | fires |
| pos_03_ar_fish.wav | أوريون! | ar | Fish Audio | 1.82 | 1.000 | fires |
| pos_04_ar_fish.wav | أُوريون | ar | Fish Audio | 0.76 | 1.000 | fires |
| pos_05_en_piper.wav | Ohryon | en | Piper | 0.60 | 1.000 | fires |
| pos_06_ar_piper.wav | أوريون. | ar | Piper | 0.42 | 1.000 | fires |
| pos_07_ar_piper.wav | أُوريون | ar | Piper | 0.45 | 1.000 | fires |
| pos_08_en_piper.wav | Ohryon | en | Piper | 0.56 | 1.000 | fires |
| pos_09_en_piper.wav | Or-yon | en | Piper | 0.50 | 1.000 | fires |
| pos_10_ar_piper.wav | أُوريون | ar | Piper | 0.45 | 1.000 | fires |
| neg_01_ar_piper.wav | كيفك اليوم | ar | Piper | 0.94 | 0.846 | silent |
| neg_02_ar_piper.wav | الاجتماع الساعة خمسة | ar | Piper | 2.06 | 0.833 | silent |
| neg_03_en_piper.wav | or on | en | Piper | 0.70 | 0.833 | silent |
| neg_04_ar_fish.wav | بصليون | ar | Fish Audio | 0.76 | 0.828 | silent |
| neg_05_ar_fish.wav | يا ريان | ar | Fish Audio | 0.78 | 0.816 | silent |
| neg_06_en_piper.wav | open the window | en | Piper | 1.02 | 0.816 | silent |
| neg_07_en_piper.wav | arrive on | en | Piper | 0.84 | 0.815 | silent |
| neg_08_ar_piper.wav | رح ارجع بعدين | ar | Piper | 1.76 | 0.812 | silent |
| neg_09_en_piper.wav | origin | en | Piper | 0.56 | 0.802 | silent |
| neg_10_ar_piper.wav | هاي سيري | ar | Piper | 1.08 | 0.784 | silent |
