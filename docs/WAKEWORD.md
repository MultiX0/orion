# The "Orion" wake word

Orion wakes on its own name, said in Arabic (أوريون) or English (Orion), with a custom [microWakeWord](https://github.com/OHF-Voice/micro-wake-word) model running on the board all day. This page covers what the model is, how it was trained and what it learned the hard way, how it runs on the board, and how to retrain it. The command reference for every training script is in [`wakeword/README.md`](../wakeword/README.md).

## The model

| | |
|---|---|
| Framework | microWakeWord, streaming MixedNet, int8 TFLite |
| Input | 16 kHz mono; 40 mel features per 30 ms window, 10 ms step (the micro speech features frontend) |
| Output | one probability every 30 ms (input stride 3) |
| Size | about 26,000 parameters; the `.tflite` is about 61 KB |
| Arena | 34,816 bytes declared, about 23 KB used on the board |
| Shipped | `wakeword/models/orion.tflite` and `orion.json`, copied to `firmware/components/orion_wakeword/models/` |
| Cutoff | 0.96, sliding window 5 |
| Languages | Arabic and English |

The files are a standard microWakeWord v2 pair. ESPHome's `micro_wake_word` takes `orion.json` as it is; anything running TFLite Micro can load `orion.tflite` with the cutoff, window and arena from the manifest. The manifest's `evaluation` block (ignored by firmware) records where the model came from and every number it was measured on.

## How it was trained

### Data

Nobody recorded thousands of people saying "Orion", so the positives are synthetic, from two very different engines so the model cannot learn one voice or one vocoder:

| Source | Clips | Notes |
|---|---|---|
| Fish Audio TTS (`s2.1-pro-free`) | 1,100 "Orion" and 700 "hey Orion" | 90 library voices, 70 percent Arabic; speed 0.75 to 1.35, volume, temperature and top_p varied per clip |
| Piper (ONNX runtime) | 3,000 | 1,092 speakers across three voices: English LibriTTS-R and VCTK, and Jordanian Arabic |
| Fish, second round | 1,000 more | 400 voices not used before; the spellings اورايون and أورايون as well as أوريون and Orion; alone and after a lead word (يا، طيب، هاي، Hey, Okay, Um); whispered, fast, slow, excited, shouted |

Before training, a sample of the positives was transcribed back through Fish's recognizer to check the voices really say the word: 99.1 percent of Fish Arabic, 100 percent of Fish English, 96.7 and 95.8 percent of Piper Arabic and English. (A small recognizer model misread one Piper voice as French for half its clips; the larger model with a language hint got 29 of 30. Use the large model for a single repeated voice.)

Negatives:

- **Confusables**, generated with the same engines and voices: orange, origin, Oreo, Ryan, O'Brien, onion, "or on", "hey Siri", Alexa, "okay Google", and Arabic words near أوريون: أوريو، أوروبا، يا ريان، عيون، مليون، أوقيانوس and more.
- **1,500 ordinary Fish utterances**: everyday words, names and household phrases in both languages.
- **Real conversation**: the DiPCo and CHiME6 dinner party sets from the microWakeWord dataset.
- **Standard speech and non-speech**: prefixes of microWakeWord's `speech` and `no_speech` spectrogram sets (139 hours of `voices_lav_mid`, 35 of `voices_lav_far`, all of `fsd50k_speech` and `wham_train`), streamed straight out of the remote archives with HTTP range requests, so the 24 GB of zips never touched the disk.
- **Music**: a Free Music Archive subset.
- **Quiet sets**: 1,500 soft "Orion" clips at 3 to 12 dB over a microphone-like noise floor, and 4,500 soft speech clips and faint clicks, knocks, hums, beeps and breaths at low signal to noise. The frontend normalises level, so "quiet" means low SNR over the floor, not low gain.

Every clip is augmented the upstream way: MIT room impulse responses, background noise at -5 to 10 dB SNR, EQ, distortion, pitch shift, band stop and gain.

### Training

Upstream's recipe: 8,000 steps at learning rate 0.001 without SpecAugment, then 4,000 at 0.0002 with it, batch 128, negative class weight 20. On an RTX 3050 (6 GB) in WSL2, 0.3 to 0.4 s a step; on the CPU 0.65. The data pipeline runs in numpy on the CPU, so the step rate follows whatever CPU is spare, not the GPU.

### How it is measured

No single number says whether a wake word is good, so every candidate is measured several ways, side by side:

| Measure | What it is |
|---|---|
| Clean holdout | 204 held-out positives and 192 confusables. How the model does on the word against words that sound like it. |
| Ambient | 5.33 hours of real overlapped dinner party conversation: false accepts per hour on people talking. |
| Augmented | the trainer's noisy test positives: misses under loud background noise. |
| Unseen noise | 2.77 hours of everyday non-speech sounds (doors, dogs, engines) that no run trained on: false wakes per hour. |
| Silence and hum | ten minutes each of digital silence, white and pink noise at several levels, and a 50 Hz hum with harmonics. |
| Round two sets | held-out new voices, the alif spellings, English from new voices, quiet positives, quiet speech, faint sounds. |
| Over the air | clips played through PC speakers to the real board. |

The target was under 0.5 false accepts per hour on ambient speech at under 5 percent false rejection. No model reached both. Every checkpoint sits on a trade-off line, and the job has been choosing the right point on it for a real room.

### What the runs taught, model by model

| Model | What changed | Result |
|---|---|---|
| stock `okay_nabu` | ESPHome's released model, to prove the pipeline | 12 of 18 replayed positives (every miss was "Okay, Nabu" with a pause at the comma), 0 of 10 negatives; 0 false accepts on silence |
| `orion_v0` (step 4000) | the first full run | 4.9 percent clean misses, but 34 of 192 confusables fired, 19 an hour on ambient speech |
| `orion_ft` | the stage two schedule alone, from step 4000 | 22 confusables at the same recall. On the board it woke on silence and noise. |
| `orion_ft4` | plus the standard speech and no_speech negatives | ambient 0.38 an hour and unseen noise 16 an hour, but 21 percent clean misses |
| `orion_full2` step 9000 | from scratch with every set and positives weighted up | 15.2 percent clean misses, 2.8 an hour ambient, 18.8 an hour on noise |
| **`orion_r2b`** step 2250 | round two: new voices, alif spellings, quiet sets | shipped, see below |

The lessons, each found by measuring rather than guessing:

- **Stage one cannot reject confusables.** At the high learning rate without masking, the model learns the word before it learns what is not the word. No stage one checkpoint was shippable.
- **The model keyed on the voice, not the word.** Fish confusables fired 55 percent of the time against 13 percent for Piper ones. Alexa, hey Siri and a name like Ramon share nothing with Orion except being one short word in a Fish voice, and a Fish voice saying a short word was positive far more often than negative in what the model saw. More, broader Fish negatives fixed that; re-weighting a few hundred confusables only made the model doubt every short Fish utterance.
- **Silence never fired any model, but the microphone's own hum did.** A 50 Hz hum with harmonics at RMS 100 fired the early models with probability 1.000. The firmware's energy gate ends wakes on silence and hum regardless of the model.
- **Everyday noise needs the standard negatives.** Early models fired 87 to 213 times an hour on real non-speech sounds; only the standard `speech` and `no_speech` sets brought that down.
- **From scratch, extra negatives drown the word.** With the standard sets added, positives were 4.8 percent of each batch and recall collapsed; weighting positives from 2 to 4 put them back at 9 percent.
- **A lower cutoff buys little.** The missed positives sit at low probability, not just under the cutoff: lowering it bought 1 to 3 points of recall for two to five times the false wakes.
- **Synthetic holdouts overstate the room.** A real voice in a real room is the final test; over-the-air replays from PC speakers are a useful but different signal.

### The shipped model

`orion_r2b`: `orion_full2` step 9000 fine-tuned 2,250 more steps at learning rate 0.0001 with the round two sets. Cutoff 0.96, the lowest where both ambient and unseen noise wakes are under the model it replaced.

| | `orion_full2` at 0.95 | `orion_r2b` at 0.96 |
|---|---|---|
| quiet speech false wakes (of 534) | 74 | 23 |
| faint sound false wakes (of 600) | 29 | 3 |
| unseen noise wakes per hour | 18.8 | 11.9 |
| ambient false wakes per hour | 2.81 | 1.88 |
| confusable false wakes (of 192) | 12 | 11 |
| missed, alif spellings | 41.2% | 20.6% |
| missed, English from unseen voices | 44.8% | 27.1% |
| missed, all unseen Fish voices | 42.1% | 22.5% |
| missed, the original holdout | 15.2% | 18.6% |
| missed, quiet "Orion" | 32.2% | 36.9% |
| missed, "Orion" under loud noise | 27.9% | 43.4% |

The cost is the last three rows: it turns down more real "Orion"s said over loud noise or very softly. In practice: say it at a normal speaking volume, and in a loud room say it a little louder. `orion_full2` is kept for a one-command rollback.

## On the board

`firmware/components/orion_wakeword`, a port of ESPHome's micro_wake_word pipeline (same libraries, same streaming model logic): features every 10 ms, the model every 30 ms, the mean of the last 5 probabilities against the cutoff, then a cooldown. It runs on core 1 at about 12 percent of that core (0.47 ms of features per step, 2.2 ms per inference). It listens in idle and offline, and stops during a turn.

A detection must also pass the **energy gate**: the loudest 100 ms of the last 1.5 s must reach twice the noise floor and at least RMS 30. Silence on this microphone reads RMS 4 to 13 and speech 40 to 180. The gate was first set at 3x the floor and RMS 40, and it blocked a real "Orion" whose loudest 100 ms was RMS 50 against a floor that had drifted to 20; emulated on the quiet test sets, 3x cost three quarters of soft "Orion"s and 2x about half. It sits at 2x and 30.

On the console:

```
ww                    # stats: steps, inferences, detections, timing, arena, CPU load
ww cutoff 250         # tighter for a noisy room, until the next restart (the manifest's 0.96 loads as 244)
ww debug 1            # dump 2 s of audio around every detection over serial
ww clip               # dump the last 2 s now
```

A detection logs `DETECTED "Orion" #n avg <n> max <n>` with the averaged and peak probability out of 255. A detection the gate refused logs `gated: ...` with the numbers. With `ww debug 1`, `tools/serial_capture.py` saves every detection's audio to `logs/wake_clips/`, which is the way to see what woke the board.

### Replay testing

`wakeword/test_clips/` holds ten positive and ten negative clips held out from training, listed in `wakeword/models/TEST_CLIPS.md` (their expected scores were computed for an earlier model; re-score them with `scripts/evaluate.py` for the current one). With the board listening:

```
tools\replay_clips.ps1 -Path wakeword\test_clips
tools\replay_clips.ps1 -Path <folder of negatives> -Negative
```

It plays each clip through the PC speakers with one serial capture per clip, so every detection is attributed to the clip that was playing, and writes a summary to `logs\replay_<time>.txt`. Tell anyone in the room first; it plays sound.

## Retraining

The training environment is WSL2 Ubuntu with Python 3.11 (TensorFlow has no wheels for 3.14):

```
uv venv --python 3.11 ~/orion_ww/.venv
uv pip install --python ~/orion_ww/.venv/bin/python -r wakeword/requirements.txt
```

Then follow [`wakeword/README.md`](../wakeword/README.md): generate the Fish and Piper clips (a Fish key in `.env`; the free text to speech model is enough), fetch the negative sets, prepare features, write the config, train, export, evaluate. Things that will bite:

- **Keep the venv, features and checkpoints inside the WSL filesystem** (`~/orion_ww`). uv cannot keep its cache on `/mnt/c`: it renames files and DrvFs refuses.
- **Run long jobs in a detached tmux session.** WSL tears down every process a `wsl.exe` call started when that call returns, and `nohup` does not save them. A tmux server does.
- **Shell scripts must be LF.** `wakeword/.gitattributes` pins `*.sh` to LF; a CRLF script fails with "command not found" on every continuation line.
- **Resuming replays the whole schedule.** The trainer restarts at step 1 on a restore, putting stage one's high learning rate back on trained weights. Continue from a checkpoint with the fine-tune launcher (`scripts/finetune_start.sh`) instead.
- **On a 6 GB GPU** the trainer's validation batch of 1024 runs out of memory; `train.sh` lowers it to 256, and `TF_GPU_ALLOCATOR=cuda_malloc_async` stops fragmentation.
- **Never compare file times across the WSL and Windows boundary**, and never against a file that is being appended to; select checkpoints by name.
- **Rank checkpoints at fixed cutoffs** (`scripts/sweep_scores.py`), not by "the lowest cutoff with zero false accepts", which a single outlier decides on a 192 clip set.
- **Measure every candidate on all the yardsticks** (`scripts/eval_weights.sh`), and on silence and noise (`scripts/silence_test.py`), before it goes near the board.

### Shipping a new model

1. Copy the `.tflite` and `.json` into `firmware/components/orion_wakeword/models/` as `orion.*` (keep the old pair under another name), or point the build at them with `idf.py -D ORION_WAKE_MODEL=<path without extension> build`.
2. Build, then write only the model partition: `python -m esptool --chip esp32s3 write_flash 0x710000 build/wakeword_model.bin` (or `tools\flash.ps1 -Bin firmware\build\wakeword_model.bin -Address 0x710000`).
3. The boot log shows the manifest the board read: `ww_manifest: "Orion" v2: ... cutoff 0.96, ... window 5, arena ...`.
4. Say it, at a normal volume, from across the room. Then leave the board in a noisy room for an hour with `ww debug 1` and look at what woke it.

## Licensing

The negative and augmentation data carry mixed licenses (MIT impulse responses, Free Music Archive, DiPCo, CHiME6). Treat the trained model as for non-commercial personal use, as upstream does for its own notebook.
