"""Picks the test clips the firmware side replays, and writes TEST_CLIPS.md.

Takes the scores evaluate.py saved for the holdout, chooses ten positives
spread across the score range (so the list is not all easy ones) and the ten
hardest negatives, copies them into test_clips/ with readable names, and writes
the table that says what each one contains and what should happen.

Usage:
    python scripts/make_test_clips.py --scores work/holdout_scores.json --cutoff 0.95
"""

import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def fish_texts():
    """filename -> text, from the generation log."""
    path = os.path.join(HERE, "work", "fish_log.jsonl")
    out = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as f:
        for line in f:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if record.get("result") != "ok":
                continue
            out[record["name"]] = (record["text"], record["lang"], record["voice"][:8])
    return out


def piper_texts():
    """filename -> text, rebuilt from the same seeds the generator used."""
    sys.path.insert(0, os.path.join(HERE, "scripts"))
    import piper_generate

    out = {}
    for kind, count, seed in (
        ("orion", 3000, 101),
        ("hey_orion", 2000, 202),
        ("negative", 3500, 303),
    ):
        per_voice = piper_generate.build_jobs(kind, count, seed)
        for voice_name, jobs in per_voice.items():
            for job in jobs:
                out[(kind, job["name"])] = (
                    job["text"],
                    "ar" if voice_name.startswith("ar") else "en",
                    voice_name,
                )
    return out


def describe(relpath, fish, piper):
    name = os.path.basename(relpath)
    if name.startswith("fish_"):
        rest = name[len("fish_") :]
        phrase, _, filename = rest.partition("_")
        if phrase == "hey":
            phrase = "hey_orion"
            filename = filename[len("orion_") :]
        info = fish.get(filename)
        if info:
            return "Fish Audio", info[1], info[0], info[2]
        return "Fish Audio", "?", "?", "?"
    if name.startswith("piper_"):
        rest = name[len("piper_") :]
        phrase, _, filename = rest.partition("_")
        if phrase == "hey":
            phrase = "hey_orion"
            filename = filename[len("orion_") :]
        info = piper.get((phrase, filename))
        if info:
            return "Piper", info[1], info[0], info[2]
        return "Piper", "?", "?", "?"
    return "?", "?", "?", "?"


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--scores", required=True)
    parser.add_argument("--cutoff", type=float, required=True)
    parser.add_argument("--count", type=int, default=10)
    parser.add_argument("--model", default="orion.tflite")
    args = parser.parse_args()

    with open(args.scores, encoding="utf-8") as f:
        report = json.load(f)

    fish = fish_texts()
    piper = piper_texts()

    all_pos = report["positive_scores"]
    all_neg = report["negative_scores"]
    # Only clips the PC result agrees with, so "expected" is what a replay
    # through the board should reproduce. The counts the model gets wrong on
    # the whole holdout are stated in the text instead.
    positives = sorted((r for r in all_pos if r["score"] > args.cutoff), key=lambda r: r["score"])
    negatives = sorted((r for r in all_neg if r["score"] <= args.cutoff), key=lambda r: -r["score"])
    missed = len(all_pos) - len(positives)
    accepted = len(all_neg) - len(negatives)

    # Positives: spread over the range so the list has easy and hard clips.
    step = max(1, len(positives) // args.count)
    chosen_pos = positives[::step][: args.count]
    # Negatives: the ones that scored highest while staying silent, the near misses.
    chosen_neg = negatives[: args.count]

    out_dir = os.path.join(HERE, "test_clips")
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old.endswith(".wav"):
            os.remove(os.path.join(out_dir, old))

    rows = []
    for label, chosen in (("pos", chosen_pos), ("neg", chosen_neg)):
        for index, record in enumerate(chosen, start=1):
            source, language, text, voice = describe(record["file"], fish, piper)
            engine = "fish" if source == "Fish Audio" else "piper"
            name = "%s_%02d_%s_%s.wav" % (label, index, language, engine)
            shutil.copyfile(os.path.join(HERE, record["file"]), os.path.join(out_dir, name))
            rows.append(
                {
                    "name": name,
                    "kind": label,
                    "source": source,
                    "language": language,
                    "text": text,
                    "voice": voice,
                    "score": record["score"],
                    "seconds": record["seconds"],
                }
            )

    lines = [
        "# Test clips",
        "",
        "Twenty 16 kHz mono 16-bit WAV files in `wakeword/test_clips/`, held out",
        "from training: no clip here ever became a feature the model saw.",
        "",
        "Replay them through the PC speakers with `tools/replay_clips.ps1` while the",
        "board listens. The ten `pos_` clips should each fire the wake word once.",
        "The ten `neg_` clips are the hardest negatives the model still rejects, the",
        "ones that scored closest to the cutoff from below, and none of them should fire.",
        "",
        "Score is the highest sliding window probability the shipped model gave the",
        "file, measured on the PC with `scripts/evaluate.py`. The manifest cutoff is",
        "%.2f, so a positive is detected when its score is above that." % args.cutoff,
        "",
        "On the whole holdout at this cutoff the model misses %d of %d positives and"
        % (missed, len(all_pos)),
        "fires on %d of %d confusable negatives. Only clips the PC result agrees with"
        % (accepted, len(all_neg)),
        "are listed here, so the replay checks the board against the PC, not the",
        "model against the target.",
        "",
        "| file | says | language | engine | seconds | score | expected |",
        "|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        expected = "fires" if row["kind"] == "pos" else "silent"
        lines.append(
            "| %s | %s | %s | %s | %.2f | %.3f | %s |"
            % (
                row["name"],
                row["text"],
                row["language"],
                row["source"],
                row["seconds"],
                row["score"],
                expected,
            )
        )
    lines.append("")

    models_dir = os.path.join(HERE, "models")
    os.makedirs(models_dir, exist_ok=True)
    with open(os.path.join(models_dir, "TEST_CLIPS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print("wrote", os.path.join(models_dir, "TEST_CLIPS.md"), "and", len(rows), "clips")


if __name__ == "__main__":
    main()
