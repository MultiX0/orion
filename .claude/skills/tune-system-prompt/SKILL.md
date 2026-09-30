---
name: tune-system-prompt
description: Change Orion's system prompt (firmware/assets/system_prompt.txt) and measure the effect before and after, first against the real model and voice from the PC, then on the board and through the PC brain. Use when changing how Orion talks, what it knows about itself, its languages, its emotion tags or its honesty rules.
---

# Change the system prompt and evaluate it

## Where the prompt lives and who reads it

- `firmware/assets/system_prompt.txt` is packed into the board's assets partition and read once at boot. If it is missing, the board falls back to a one line prompt compiled into `components/orion_cloud/orion_cloud.c`.
- The board sends it as the system message of every turn, to its own model and to a PC or phone brain. The PC brain adds its own context after it (this PC, the local date and time, memory, and rules for speaking tool results) in `PcBrain._withContext` in `lib/features/harness/data/pc_brain.dart`; change that code for rules that only make sense when a PC is answering.
- The voice tag rules sit between a `<fish>` line and a `</fish>` line. With Fish the board sends them without the marker lines; with any other TTS it cuts the section out and appends a line forbidding square brackets, since other voices would read tags aloud. `cloud_api.system_prompt(fish=...)` does the same cut for the PC scripts, and `tools/cloud/prompt_cut_test.py` checks both.
- `tools/cloud/prompt_test.py`, `tool/pc_brain_probe.dart` and `tool/brain_eval.dart` read the same file, so they always test what ships.

## Rules the prompt must keep

Each of these came from a reply that failed out loud:

- Everything is spoken. No markdown, no emoji, no lists, numbers and times written as words, one or two short sentences (about twenty words).
- Answer in the user's language. Arabic is fluent Modern Standard Arabic in a friendly phone assistant register, feminine for Orion herself, plain forms for the user; English tech and brand names stay in Latin letters. English stays English, technical questions included.
- Voice tags follow Fish's S2 docs: free natural language cues in English, placed where the sound or feeling happens, anywhere in the sentence, and used wherever a person would really sound that way. The guards: one cue at a time, never two side by side, and none before a plain fact, number, time or name (without that one, a draft put `[pause]` before every number). `prompt_test.py` fails stacked cues, a cue not in English, and any cue with `--tts openai`. Keep a joke's example as a shape (`...؟ [pause] ...! [laugh]`): a real joke in the prompt is told word for word.
- Honesty: it never claims to have done something it cannot reach, and never names the language model's vendor (users switch models).
- Size: the file is about 4.7 KB. A prompt twice as long measured about 100 ms slower to first token and much noisier at p95, and it rides on every request. Keep it as short as the rules allow.

## 1. Baseline

Keep the old prompt to compare against, outside the repo or in `logs/` (gitignored):

```
mkdir -p logs
cp firmware/assets/system_prompt.txt logs/prompt_before.txt
```

The scripts need `DEEPINFRA_API_KEY` (and `FISH_API_KEY` for speech) in `.env`; `LLM_MODEL` picks the model, default `google/gemma-4-31B-it-turbo`. On Windows set `PYTHONIOENCODING=utf-8`.

```
python tools/cloud/prompt_test.py > logs/prompt_before_run.txt
```

It asks ten Arabic and five English questions through the real model and marks each reply clean or lists the problems: wrong language, digits, markdown, emoji, too many sentences, too long, two cues side by side, a cue not in English, a cue for a non-Fish voice. It lists every cue used, so read those too: a cue in the wrong place is not caught.

## 2. Edit and measure

Edit `firmware/assets/system_prompt.txt`, then:

```
python tools/cloud/prompt_test.py                   # the fifteen questions, checked
python tools/cloud/prompt_test.py --tts openai      # the same, with the prompt a non-Fish voice gets
python tools/cloud/prompt_cut_test.py               # the <fish> cut for both, offline
python tools/cloud/prompt_test.py --speak           # also synthesize each reply in Orion's voice (logs/prompt_test/)
python tools/cloud/loop_test.py --questions         # the same set with the camera tool offered, as the board sends it
python tools/cloud/loop_test.py --prompt-bench logs/prompt_before.txt firmware/assets/system_prompt.txt
```

The prompt bench interleaves the two files over the same questions and prints time to first token (min, median, p95) and prompt tokens for each. Run everything twice: the service's own noise moves medians by hundreds of milliseconds between runs.

For the PC brain:

```
dart run tool/pc_brain_probe.dart "What time is it?" "كم الساعة الآن؟" "Open Spotify"
```

`dart run tool/brain_eval.dart <model> --thinking=<model>` runs the task set against real apps on this PC; ask before running it.

Read the Arabic replies yourself, or better, have a native speaker read them. The checks catch form, not a translated-sounding sentence.

## 3. Try it on the board

With the user's go-ahead, build and write only the assets partition (see `flash-firmware`), then check the capture says `system prompt loaded, <n> bytes` with the new size. Test with typed turns at volume 0; `state` prints the last transcript and reply. Arabic goes through the console as hex:

```
python -c "print('ask hex:' + 'كم الساعة الآن؟'.encode().hex())"
python tools/cloud/console_session.py --out logs/prompt_board.txt "vol 0" "ask What are you, exactly?" "state"
```

Keep typed hex lines short: the console drops bytes from long lines.

## 4. Commit

Commit the prompt with the numbers in the body: clean replies before and after, median reply length and spoken seconds, and time to first token if the size changed. Example: `feat(cloud): answer times in words` with "15 of 15 clean (was 13), median reply 74 chars (was 94)."
