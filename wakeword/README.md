# Orion wake word

A custom [microWakeWord](https://github.com/OHF-Voice/micro-wake-word) model for
the word Orion, trained for a board that listens all day on an ESP32-S3. The
model in `models/` is what the firmware flashes to the model partition.

Audio is 16 kHz mono. The frontend produces 40 features per 30 ms window with a
10 ms step. The network is a streaming MixedNet, quantized to int8, and it
reports one probability every 30 ms because the input stride is 3.

## What is here

```
scripts/     every step, each runnable on its own
models/      the shipped .tflite, its v2 .json manifest, TEST_CLIPS.md
test_clips/  ten positive and ten negative wav files for the firmware to replay
data/        generated audio, gitignored
work/        the upstream clone and scratch files, gitignored
```

The training venv, the feature files and the checkpoints live outside the repo
in `~/orion_ww` inside WSL. That is deliberate: uv cannot keep its cache on
`/mnt/c` (it renames files and DrvFs refuses), and this machine is short on
disk, so only the small artifacts come back to the Windows side.

## The data

Positives come from two engines so the model does not learn one voice or one
vocoder:

| source | clips | note |
|---|---|---|
| Fish Audio TTS | 1100 | 90 library voices, 70 percent Arabic |
| Piper ONNX | 3000 | 1092 speakers across three voices, one Arabic |

The project owner and their audience speak Arabic, so the Arabic side is weighted heavily
and the word is generated as أوريون as well as Orion. Speed, volume, sampling
temperature and speaker change on every clip.

Negatives are the standard DiPCo and CHiME6 dinner party spectrograms from the
microWakeWord dataset, a Free Music Archive subset standing in for the
no_speech set, and a generated adversarial set: words that sound close to the
wake word, in both languages, made with the same engines and the same voices.
The confusable list is in `scripts/fish_generate.py` and
`scripts/piper_generate.py`, and it covers orange, origin, Oreo, Ryan,
O'Brien, onion, "or on", "hey Siri", "Alexa", "okay Google", plus Arabic words
that land near أوريون: أوريو, أوروبا, يا ريان, عيون, مليون, أوقيانوس and more.

Every clip is augmented the way upstream does it: room impulse responses from
the MIT survey, background noise mixed in between -5 and 10 dB SNR, parametric
EQ, distortion, pitch shift, band stop filtering and gain.

## Running it end to end

From this folder, inside WSL:

```bash
python scripts/fish_voices.py                                   # build the voice pool
python scripts/fish_generate.py --phrase orion --count 1100     # Fish positives
python scripts/fish_generate.py --phrase confusable --count 400 # Fish negatives
python scripts/piper_generate.py --voices                       # fetch Piper voices
python scripts/piper_generate.py --phrase orion --count 3000
python scripts/piper_generate.py --phrase negative --count 3500
bash scripts/get_negative_data.sh                               # dinner party, RIRs, FMA
python scripts/prepare_fma.py --tracks 700 --seconds 10
bash scripts/prepare_all.sh                                     # trim, holdout, features
python scripts/make_config.py --phrase orion
bash scripts/train.sh orion
python scripts/export_model.py --phrase orion --name orion
python scripts/evaluate.py --model models/orion.tflite --cutoff <from the export>
```

Run the training inside a detached tmux session (`tmux new-session -d -s
train 'bash scripts/train.sh orion'`). WSL tears down a session's processes
when the `wsl.exe` call that started them returns, and nohup does not prevent
it; a tmux server does.

To ship a model before the run has finished, export any checkpoint the
trainer has saved and pick its cutoff from the holdout instead of the ROC:

```bash
python scripts/export_early.py --phrase orion --weights <a .weights.h5> --name orion_early
python scripts/evaluate.py --model models/orion_early.tflite --cutoff 0.9 \
    --positive data/holdout/orion --negative data/holdout/negative \
    --save-scores work/holdout_scores_orion_early.json
python scripts/pick_cutoff.py --scores work/holdout_scores_orion_early.json \
    --manifest models/orion_early.json
```

The early export stays on the CPU and reads a copy of the weights, so it can
run beside the live trainer. Its manifest carries an extra `evaluation` block,
which the firmware ignores, saying that the cutoff came from the holdout and
that false accepts per hour was not measured for it.

## Fine-tuning, scouting and the two measures

The trainer's resume replays the whole step schedule from step 1, so restoring
a checkpoint puts stage one's high learning rate back on trained weights. To
continue from a checkpoint with a different schedule, use the fine-tune
launcher, which starts the run and a checkpoint scout in tmux:

```bash
bash scripts/finetune_start.sh orion_ft orion ~/orion_ww/trained_models/orion/train/0_weights_4000.weights.h5 2500 0.0002
bash scripts/finetune_start.sh orion_ft3 orion <weights> 2000 0.0002 20 "fish_negative:4 fish_confusable:2"
bash scripts/train_start.sh hey_orion          # a full run from scratch, also with a scout
```

The scout (`scripts/scout.sh`) exports every saved checkpoint to a quantized
streaming model on the CPU and scores it on the holdout, one CSV line each in
`work/scout_<run>/scout.csv`. Compare checkpoints with
`python scripts/sweep_scores.py work/scout_<run>/*.scores.json`, which prints
false rejection and confusable false accepts at fixed cutoffs: the "lowest
cutoff with zero false accepts" figure in the CSV is decided by a single
outlier on a 192 clip set and swings too much to rank checkpoints by.

Two measures that disagree, and both are reported:

- the holdout (`data/holdout/`): clean generated clips, 204 positives and 192
  confusables such as Oreo, Ryan, أوريو and Alexa. It says how the model does
  on the word against words that sound like it.
- the ambient set (dinner_party_eval, 5.33 hours of real overlapped
  conversation): `python scripts/ambient_faph.py --config <yaml> --tflite <model>`
  prints false accepts per hour at every cutoff, plus false rejection on the
  trainer's augmented test positives. The trainer's own ROC file stops listing
  cutoffs once false accepts per hour pass 2.0, so it can look empty for a
  model that is noisy on speech.

Two more checks match what a board in a quiet room actually hears.
`scripts/silence_test.py` feeds each model ten minutes of digital silence,
white and pink noise at several levels and a mains hum, and counts every
detection; with `--mmap` it also runs spectrogram sets the model never
trained on (a prefix of fsd50k_no_speech fetched into
`negative_datasets/unseen/`) and reports detections per hour. The first
models fired on a 50 Hz hum with probability 1.000 and on everyday sounds
over a hundred times an hour; only the standard speech and no_speech
negatives fixed that. `scripts/auto_eval.sh <run> <phrase> <log>` follows a
run's scout and writes both measures for every checkpoint to
`work/scout_<run>/fulleval.csv`.

The standard negative sets are 24 GB unpacked, far more than the machine
has. `scripts/probe_zip.py` lists a remote archive with range requests, and
`scripts/fetch_negative_part.py` streams one mmap folder out of it, stopping
at `--max-gb` and cutting the index to the entries that fit, so the zip never
touches disk and a prefix is a valid set. `make_config.py --extra-set
speech:10` picks such a set up from `negative_datasets/` with random crops.

`scripts/ship_checkpoint.py` copies a scouted checkpoint into `models/` with
a cutoff chosen by hand and writes both sets of numbers into the manifest's
`evaluation` block, and `scripts/roc_eval.sh` runs the trainer's own ROC test
on any weights file.

## GPU

The trainer runs on the RTX 3050 when `tensorflow[and-cuda]` is installed
(about 4.2 GB on top of the CPU wheel). It is roughly twice the CPU pace, 0.3
to 0.4 s a step against 0.65, because the data pipeline is numpy on the CPU
and that is the real cost, not the 25k parameter model. Two things bit on a
6 GB card the desktop is also using: upstream validates with a fixed batch of
1024, which `train.sh` lowers to 256, and the allocator fragments, which
`TF_GPU_ALLOCATOR=cuda_malloc_async` fixes.

`FISH_API_KEY` comes from `.env` at the repo root and is never printed or
committed. The key on this machine has no API credit, so the scripts call the
free tier model `s2.1-pro-free`; the paid model names answer HTTP 402.

## The manifest

`models/orion.json` is a version 2 manifest, the format the ESPHome
micro_wake_word component and our firmware both read:

- `probability_cutoff` comes from the ROC the training run measures, picking
  the point that stays under the false accept target with the lowest false
  rejection
- `sliding_window_size` is 5, the window the ROC was measured with
- `feature_step_size` is 10, matching the frontend
- `tensor_arena_size` is estimated from the model's own activations and checked
  against the four released ESPHome models, where the estimate came out 3 to 22
  percent above the arena they declare. If the board still fails to allocate,
  raise it; that is normal and cheap.

## Round 2: the model that ships

`models/orion.tflite` with `models/orion.json` (cutoff 0.96, window 5) is
`orion_r2b`: `orion_full2` step 9000 fine-tuned for 2250 more steps at a
learning rate of 1e-4. It targets what the full model still did wrong in a real
room: waking on faint sounds and quiet talk, and missing the alif spellings
اورايون and أورايون and English "Orion" from voices it had not heard.

New data for it, made by `scripts/fish_round2.py` and `scripts/make_quiet.py`:

| set | what | size |
|---|---|---|
| Fish positives | 1000 clips, 400 voices not used before, أوريون, اورايون, أورايون and Orion, alone and after a lead word, whispered, fast, slow, excited | 43 MB |
| held-out voices | 91 of those voices (48 Arabic, 43 English) only ever speak the test set | 10 MB |
| quiet positives | 1500 soft "Orion" clips at 3 to 12 dB over a mic-like noise floor | in the next row |
| quiet negatives | 4500 clips of soft speech and faint clicks, knocks, hums, beeps and breaths at low SNR | 381 MB with the row above, test sets included |

Training ran in short runs without in-training validation (`scripts/quick_tune.sh`);
every checkpoint was measured afterwards with `scripts/eval_weights.sh` and
`scripts/eval_r2.py`. Same scripts, both models:

| | orion_full2 9000 at 0.95 | orion_r2b 2250 at 0.96 |
|---|---|---|
| quiet speech false wakes (of 534) | 74 | 23 |
| faint sound false wakes (of 600) | 29 | 3 |
| unseen noise wakes per hour (FSD50K) | 18.8 | 11.9 |
| ambient false wakes per hour | 2.81 | 1.88 |
| confusable false wakes (of 192) | 12 | 11 |
| missed, alif spellings | 41.2% | 20.6% |
| missed, English from unseen voices | 44.8% | 27.1% |
| missed, all unseen Fish voices (240) | 42.1% | 22.5% |
| missed, the original holdout (204) | 15.2% | 18.6% |
| missed, quiet "Orion" | 32.2% | 36.9% |
| missed, "Orion" under loud background noise | 27.9% | 43.4% |

The cost is the last three rows: it turns down more real "Orion"s said over
loud noise or very quietly. `models/orion_full2.*` is the previous model, kept
for rollback, and the firmware has the same files in
`firmware/components/orion_wakeword/models/`.

## Using the model in your own project

The files are a standard microWakeWord v2 pair: a streaming int8 TFLite model
and its JSON manifest. ESPHome's `micro_wake_word` takes them as they are
(point it at `orion.json`); anything running TFLite Micro can load
`orion.tflite` with the cutoff, window and arena size from the manifest. The
input is 40 mel channels every 10 ms from 16 kHz mono audio.

## Getting the data

Nothing large is in git. Every set can be rebuilt with the scripts here:

- Generated positives and confusables: `scripts/fish_generate.py`,
  `scripts/fish_round2.py` (needs your own Fish Audio key in `.env`; the free
  `s2.1-pro-free` TTS model is enough) and `scripts/piper_generate.py` (run it once
  with `--voices` to download the Piper voices from rhasspy/piper-voices).
- Quiet sets: `scripts/make_quiet.py`, from the negative data below.
- Negatives and augmentation: `scripts/get_negative_data.sh` downloads the
  microWakeWord spectrogram sets (kahrendt/microwakeword on Hugging Face), the
  MIT environmental impulse responses and a Free Music Archive subset. About
  9 GB.
- `scripts/prepare_all.sh` runs the whole chain in order.

Voice ids and texts vary per run by design, so a rebuild gives a comparable
set, not byte identical clips.

## Licensing

The augmentation and negative data carry mixed licenses (MIT RIR survey, Free
Music Archive, DiPCo, CHiME6). Treat the trained model as non commercial
personal use, the same note upstream puts on its own notebook.
