# Picks the voice named Orion.
#
# Generates the five test lines with every candidate, saves them to
# voice/auditions/<candidate>/, and scores each one. Scoring is not a matter of
# taste here: every clip is transcribed back by a second, independent engine and
# compared to the line that was sent. A voice that mumbles Levantine, or reads
# "Spotify" as Arabic letters, shows up as a higher character error rate.
#
#   python tools/cloud/voice_audition.py            audition the library shortlist
#   python tools/cloud/voice_audition.py --design   try Fish Voice Design first

import argparse
import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

AUDITIONS = c.REPO / "voice" / "auditions"

# The five audition lines.
LINES = [
    "أهلين! أنا أوريون، شو بتحب أساعدك فيه اليوم؟",
    "تمام، لحظة خليني أشوف.",
    "الجو اليوم بعمّان حلو، حوالي خمسة وعشرين درجة.",
    "فتحتلك الـ Spotify على الـ PC.",
    "ما سمعتك منيح، ممكن تعيدها؟",
]

# Public Fish Audio voice library models, Levantine first. Picked from
# GET /model filtered to language ar. Every one is public and none of them is a
# named real person: cloning a real person's voice is out.
CANDIDATES = [
    ("shab-urduni", "ec69015cc6f04316a1db3c83279cca0e", "صوت شب اردني, young Jordanian man"),
    ("urduni-fakhm", "4cb8371162134edeb4915672ffc66de6", "اردني فخم, Jordanian, fuller register"),
    ("shami", "2b33ccddba42413f98533dd01929da79", "شامي, general Levantine"),
    ("shab-lubnani", "76a15132a1894875969d17e30037d0df", "شاب لبناني, young Lebanese man"),
    ("lubnani", "057fbf4e7a9744d2ae2316b30e504fb6", "لبناني, Lebanese"),
    ("falastini", "607beda668e84c729b162ac755a9186f", "فلسطيني, Palestinian"),
]

DESIGN_PROMPT = (
    "A warm, calm, clear young adult man speaking natural everyday Levantine "
    "Arabic with an Amman accent. Friendly and slightly playful, never robotic "
    "and never a radio announcer. Speaks at a relaxed conversational pace, like "
    "a helpful friend answering a question across a desk."
)


def try_voice_design(sess, n=4):
    """Fish Voice Design, the first choice. Returns [(name, wav_bytes)] or [] if unavailable."""
    print("trying Fish Voice Design, POST /v1/voice-design")
    try:
        cands = c.voice_design(DESIGN_PROMPT, reference_text=LINES[1],
                               language="ar", n=n, sess=sess)
    except RuntimeError as e:
        print("voice design unavailable: %s" % str(e)[:140])
        return []
    out = []
    for cand in cands:
        audio = base64.b64decode(cand["audio_base64"])
        name = "design-%d" % cand["index"]
        path = AUDITIONS / name / "design_preview.wav"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(audio)
        print("  %s %d Hz %d ms -> %s" % (name, cand["sample_rate"],
                                          cand["duration_ms"], path))
        out.append((name, audio))
    return out


def audition(name, voice_id, sess, judge=True):
    folder = AUDITIONS / name
    rows = []
    for i, line in enumerate(LINES, 1):
        pcm, first, total = c.tts(line, voice_id=voice_id, sess=sess,
                                  model=c.env("FISH_TTS_MODEL", c.TTS_MODEL))
        path = c.save_wav(folder / ("line%d.wav" % i), pcm)
        stats = c.pcm_stats(pcm)
        row = {"line": line, "file": path.name, "ttfb_ms": first,
               "total_ms": total, "seconds": c.pcm_seconds(pcm), "rms": stats["rms"],
               "peak": stats["peak"], "clipped": stats["clipped"],
               "silence_ratio": round(stats["silence_ratio"], 3)}
        if judge:
            heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language="ar", sess=sess)
            row["heard"] = heard
            row["cer"] = round(at.cer(line, heard), 3)
            found, want = at.kept_english(line, heard)
            row["english_kept"] = "%d/%d" % (found, want) if want else "-"
        rows.append(row)
        print("  line%d %5.0f ms ttfb  %4.1f s  rms %5d  cer %s  %s" % (
            i, first, row["seconds"], row["rms"],
            row.get("cer", "-"), row.get("heard", "")[:52]))
    (folder / "audition.json").write_text(
        json.dumps({"voice_id": voice_id, "lines": rows}, ensure_ascii=False,
                   indent=2), encoding="utf-8")
    return rows


def score(rows):
    """One number per candidate. Lower is better."""
    cers = [r["cer"] for r in rows if "cer" in r]
    return sum(cers) / len(cers) if cers else 1.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--design", action="store_true", help="try Voice Design first")
    ap.add_argument("--no-judge", action="store_true", help="skip the transcribe back")
    ap.add_argument("--only", default=None, help="one candidate name")
    args = ap.parse_args()

    print("fish key  %s" % c.key_fingerprint(c.env("FISH_API_KEY")))
    print("tts model %s" % c.env("FISH_TTS_MODEL", c.TTS_MODEL))
    sess = c.session()

    if args.design:
        try_voice_design(sess)

    results = {}
    speech_rate = {}
    for name, voice_id, desc in CANDIDATES:
        if args.only and args.only != name:
            continue
        print("\n%s  %s" % (name, desc))
        rows = audition(name, voice_id, sess, judge=not args.no_judge)
        results[name] = rows
        chars = sum(len(r["line"]) for r in rows)
        secs = sum(r["seconds"] for r in rows)
        speech_rate[name] = chars / secs if secs else 0

    print("\n| candidate | mean CER | English kept | speech rate ch/s | median ttfb | rms | clipped |")
    print("|---|---|---|---|---|---|---|")
    for name, rows in sorted(results.items(), key=lambda kv: score(kv[1])):
        eng = [r.get("english_kept", "-") for r in rows if r.get("english_kept", "-") != "-"]
        print("| %s | %.3f | %s | %.1f | %.0f | %d | %d |" % (
            name, score(rows), eng[0] if eng else "-", speech_rate[name],
            c.percentiles([r["ttfb_ms"] for r in rows])[1],
            sum(r["rms"] for r in rows) // len(rows),
            sum(r["clipped"] for r in rows)))
    print("\nWAVs are in %s, 16 kHz mono, one folder per candidate." % AUDITIONS)


if __name__ == "__main__":
    main()
