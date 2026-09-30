"""Builds and scores concatenated probes for the Fish Audio ASR spot check.

Why concatenate. The Fish ASR used here is the MCP speech_to_text tool, and
it takes one public URL per call. Sending a thousand
900 ms clips one at a time would be a thousand uploads. Instead this script
glues N clips into one file with a long silence between them, so one upload and
one transcription covers N clips. Flash is billed per minute, so the gaps cost
a little, but the call count drops by a factor of N.

Why it works. The clips are single words with nothing around them. Transcribed
back to back with a gap, the model returns one token per clip in order, and we
compare that list against the manifest.

Usage:
    python scripts/asr_probe.py build --spec fish_ar --files 3 --per-file 20
    python scripts/asr_probe.py score --spec fish_ar
"""

import argparse
import json
import os
import random
import re
import sys
import unicodedata
import wave

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROBE = os.path.join(HERE, "work", "asr_probe")

GAP_S = 0.8
LEAD_S = 0.3
TAIL_S = 0.5

# Arabic spellings the generators were asked to say. Anything else in the
# source text means the clip is not a bare Arabic "Orion".
FISH_AR_ORION = {"أوريون", "أوريون.", "أوريون؟", "أوريون!", "أُوريون", "اوريون"}
FISH_EN_ORION = {"Orion", "Orion!", "Orion.", "Orion?", "O-rion", "Oh-ryan"}


def load_fish(subdir):
    """Clips on disk in data/fish/<subdir>, joined to the generation log."""
    path = os.path.join(HERE, "data", "fish", subdir)
    on_disk = set(os.listdir(path))
    rows = []
    with open(os.path.join(HERE, "work", "fish_log.jsonl"), encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            if row.get("result") == "ok" and row["name"] in on_disk:
                row["path"] = os.path.join(path, row["name"])
                rows.append(row)
    return rows


def load_piper(subdir):
    """Clips on disk in data/piper/<subdir>, joined to the replayed manifest."""
    path = os.path.join(HERE, "data", "piper", subdir)
    on_disk = set(os.listdir(path))
    manifest = os.path.join(HERE, "work", "piper_%s.jsonl" % subdir)
    rows = []
    with open(manifest, encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            if row["name"] in on_disk:
                row["path"] = os.path.join(path, row["name"])
                rows.append(row)
    return rows


def spec_rows(spec, only_voices=None):
    if spec == "fish_ar_flagged":
        # The isolated word from named voices only. Used to tell a voice that
        # really under-articulates the name from a phrase-level elision.
        rows = [r for r in load_fish("orion")
                if r["text"] in FISH_AR_ORION and r["voice"] in (only_voices or ())]
        return rows, "voice"
    if spec == "fish_ar":
        rows = [r for r in load_fish("orion") if r["text"] in FISH_AR_ORION]
        key = "voice"
    elif spec == "fish_en":
        rows = [r for r in load_fish("orion") if r["text"] in FISH_EN_ORION]
        key = "voice"
    elif spec == "fish_hey_ar":
        rows = [r for r in load_fish("hey_orion") if r["lang"] == "ar"]
        key = "voice"
    elif spec == "piper_ar":
        rows = [r for r in load_piper("orion") if r["lang"] == "ar"]
        key = "speaker"
    elif spec == "piper_en":
        rows = [r for r in load_piper("orion") if r["lang"] == "en"]
        key = "speaker"
    else:
        raise SystemExit("unknown spec " + spec)
    return rows, key


def pick(rows, key, files, per_file, seed):
    """Spread the sample over as many distinct voices as the set has."""
    rng = random.Random(seed)
    by_key = {}
    for row in rows:
        by_key.setdefault(row.get(key), []).append(row)
    for bucket in by_key.values():
        rng.shuffle(bucket)
    keys = sorted(by_key, key=lambda k: str(k))
    rng.shuffle(keys)
    want = files * per_file
    chosen = []
    round_index = 0
    while len(chosen) < want:
        added = 0
        for k in keys:
            if len(chosen) >= want:
                break
            bucket = by_key[k]
            if round_index < len(bucket):
                chosen.append(bucket[round_index])
                added += 1
        if added == 0:
            break
        round_index += 1
    return [chosen[i::files] for i in range(files)]


def read_samples(path):
    with wave.open(path, "rb") as handle:
        return handle.readframes(handle.getnframes())


def build(spec, files, per_file, seed, only_voices=None):
    rows, key = spec_rows(spec, only_voices)
    groups = pick(rows, key, files, per_file, seed)
    os.makedirs(PROBE, exist_ok=True)
    gap = b"\x00\x00" * int(GAP_S * 16000)
    lead = b"\x00\x00" * int(LEAD_S * 16000)
    tail = b"\x00\x00" * int(TAIL_S * 16000)
    for index, group in enumerate(groups):
        if not group:
            continue
        body = lead + gap.join(read_samples(r["path"]) for r in group) + tail
        wav_path = os.path.join(PROBE, "%s_%02d.wav" % (spec, index))
        with wave.open(wav_path, "wb") as handle:
            handle.setnchannels(1)
            handle.setsampwidth(2)
            handle.setframerate(16000)
            handle.writeframes(body)
        manifest = [
            {"slot": i, "name": r["name"], "text": r["text"], "key": str(r.get(key))}
            for i, r in enumerate(group)
        ]
        with open(wav_path.replace(".wav", ".json"), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, ensure_ascii=False, indent=1)
        print("%s  %d clips  %.1f s" % (wav_path, len(group), len(body) / 2 / 16000))


# --- scoring ---------------------------------------------------------------

ARABIC_DIACRITICS = "".join(chr(c) for c in range(0x064B, 0x0653))


def normalise(token):
    token = unicodedata.normalize("NFKC", token)
    for ch in ARABIC_DIACRITICS + "ـ":
        token = token.replace(ch, "")
    for ch in ".,!?؟،؛:\"'()[]{}":
        token = token.replace(ch, "")
    return token.strip()


def classify_ar(token):
    """Does this transcript token carry the initial alef of أوريون."""
    t = normalise(token)
    t = t.replace("أ", "ا").replace("إ", "ا").replace("آ", "ا")
    if t.startswith("او") or t.startswith("اور"):
        return "full"
    if t.startswith("ور") or t.startswith("ري"):
        return "clipped"
    return "other"


def classify_en(token):
    t = normalise(token).lower()
    if t.startswith("ori") or t.startswith("orry") or t.startswith("oary") or t.startswith("orio"):
        return "full"
    if t.startswith("ryan") or t.startswith("rion") or t.startswith("rian"):
        return "clipped"
    return "other"


def classify(token):
    """A clip is scored against the script the transcript came back in. Fish
    ASR romanises some Arabic clips, so the spec alone does not decide it."""
    t = normalise(token)
    if any("؀" <= ch <= "ۿ" for ch in t):
        return classify_ar(t)
    return classify_en(t)


SPEAKER = re.compile(r"<\|speaker:\d+\|>")
TAG = re.compile(r"\[[^\]]*\]")


def slots_from_transcript(text):
    """One clip comes back as one word. Flash also inserts <|speaker:N|>
    markers and delivery tags like [loud]; both are stripped, then the rest is
    split on whitespace so each token is one clip."""
    text = SPEAKER.sub(" ", text)
    text = TAG.sub(" ", text)
    return [t for t in text.split() if normalise(t)]


def score(spec):
    names = sorted(
        f for f in os.listdir(PROBE) if f.startswith(spec + "_") and f.endswith(".txt")
    )
    totals = {"full": 0, "clipped": 0, "other": 0}
    per_key = {}
    misaligned = 0
    for name in names:
        base = os.path.join(PROBE, name[:-4])
        manifest = json.load(open(base + ".json", encoding="utf-8"))
        text = open(base + ".txt", encoding="utf-8").read()
        if "hey" in spec:
            # "Hey Orion" comes back as two or three words. The name is the
            # last word of each speaker segment.
            segments = [s.strip() for s in SPEAKER.split(text)[1:]]
            slots = []
            for segment in segments:
                words = [w for w in TAG.sub(" ", segment).split() if normalise(w)]
                if words:
                    slots.append(words[-1])
        else:
            slots = slots_from_transcript(text)
        aligned = len(slots) == len(manifest)
        if not aligned:
            misaligned += 1
        print("== %s  %d slots, %d transcribed%s"
              % (name, len(manifest), len(slots), "" if aligned else "  MISALIGNED"))
        for i, slot in enumerate(slots):
            verdict = classify(slot)
            totals[verdict] += 1
            if aligned:
                key = manifest[i]["key"]
                bucket = per_key.setdefault(key, {"full": 0, "clipped": 0, "other": 0})
                bucket[verdict] += 1
                if verdict != "full":
                    print("   slot %2d  key %s  src %-12s  heard %s"
                          % (i, key, manifest[i]["text"], slot))
    total = sum(totals.values()) or 1
    print("\nspec=%s files=%d misaligned=%d" % (spec, len(names), misaligned))
    print("full=%d (%.1f%%) clipped=%d (%.1f%%) other=%d (%.1f%%)" % (
        totals["full"], 100.0 * totals["full"] / total,
        totals["clipped"], 100.0 * totals["clipped"] / total,
        totals["other"], 100.0 * totals["other"] / total))
    bad = {k: v for k, v in per_key.items() if v["full"] == 0 and (v["clipped"] or v["other"])}
    if bad:
        print("keys with no clean slot:", json.dumps(bad, ensure_ascii=False))
    with open(os.path.join(PROBE, spec + "_score.json"), "w", encoding="utf-8") as handle:
        json.dump({"spec": spec, "totals": totals, "per_key": per_key},
                  handle, ensure_ascii=False, indent=1)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["build", "score"])
    parser.add_argument("--spec", required=True)
    parser.add_argument("--files", type=int, default=3)
    parser.add_argument("--per-file", type=int, default=20)
    parser.add_argument("--seed", type=int, default=11)
    parser.add_argument("--voices", nargs="*", default=None, help="restrict to these voice ids")
    args = parser.parse_args()
    if args.command == "build":
        build(args.spec, args.files, args.per_file, args.seed, args.voices)
    else:
        score(args.spec)


if __name__ == "__main__":
    main()
