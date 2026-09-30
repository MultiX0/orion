# Does S2.1 Pro perform an inline emotion tag in Arabic, or read it out loud?
#
# The docs say tags work in 83 languages and are performed, never spoken. That
# is a claim about English in most examples, so it is tested here in Arabic.
#
# The test is not "does it sound different". It is two measurements:
#   1. leakage. Transcribe the audio and look for the bracket text. If the tag
#      were spoken, words like "laughing" or "sighing" would appear.
#   2. change. Compare duration, rms and silence against the untagged take of
#      the identical sentence. A tag that is performed changes the delivery; a
#      tag that is ignored produces a near identical clip.
#
#   python tools/cloud/emotion_test.py
#   python tools/cloud/emotion_test.py --cost   how much latency a tag adds

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

OUT = c.REPO / "logs" / "emotion_test"

LINE = "ما سمعتك منيح، ممكن تعيدها؟"
LINE2 = "تمام، لقيت الجواب."

# Words that would show up in the transcript if a tag were read aloud rather
# than performed, in either script.
LEAK_WORDS = ["laugh", "sigh", "excited", "tired", "panting", "apolog", "warm",
              "whisper", "clears", "throat", "emphasis", "calm", "curious",
              "ضحك", "تنهد", "متحمس", "تعبان", "همس", "دافئ", "اعتذار"]

CASES = [
    ("plain", LINE, ""),
    ("apologetic", LINE, "[apologetic]"),
    ("sighing-tired", LINE, "[sighing][tired]"),
    ("whisper", LINE, "[whispering]"),
    ("open-domain", LINE,
     "[the calm, measured tone of someone who has done this a thousand times]"),
    ("plain2", LINE2, ""),
    ("laughing", LINE2, "[laughing][excited]"),
    ("warm", LINE2, "[warm]"),
    ("mid-sentence", "تمام، [laughing] لقيت الجواب.", "inline"),
]


def leaked(heard):
    low = heard.lower()
    hits = [w for w in LEAK_WORDS if w in low]
    if "[" in heard or "]" in heard:
        hits.append("brackets")
    return hits


def run_case(name, line, tag, sess):
    text = line if tag in ("", "inline") else tag + line
    pcm, first, total = c.tts(text, voice_id=c.env("FISH_VOICE_ID") or None,
                              sess=sess, model=c.env("FISH_TTS_MODEL", c.TTS_MODEL))
    c.save_wav(OUT / ("%s.wav" % name), pcm)
    heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language="ar", sess=sess)
    stats = c.pcm_stats(pcm)
    return {
        "name": name, "tag": tag if tag != "inline" else "(inline)",
        "sent_chars": len(text), "seconds": c.pcm_seconds(pcm),
        "ttfb": first, "total_ms": total, "rms": stats["rms"],
        "silence": stats["silence_ratio"], "heard": heard,
        "leak": leaked(heard), "cer": at.cer(line, heard),
    }


def cost(sess):
    """A tag is characters. Do those characters cost time to first audio?"""
    print("\nWhat a tag costs, 4 runs each, time to first PCM byte")
    print("| text | chars | run1 | run2 | run3 | run4 | median |")
    print("|---|---|---|---|---|---|---|")
    for label, text in (("no tag", LINE),
                        ("[apologetic]", "[apologetic]" + LINE),
                        ("two tags", "[sighing][tired]" + LINE),
                        ("open domain", "[the calm, measured tone of someone "
                                        "who has done this a thousand times]" + LINE)):
        runs = []
        for _ in range(4):
            _, first, _ = c.tts(text, voice_id=c.env("FISH_VOICE_ID") or None,
                                sess=sess, model=c.env("FISH_TTS_MODEL", c.TTS_MODEL))
            runs.append(first)
        print("| %s | %d | %.0f | %.0f | %.0f | %.0f | %.0f |" % (
            label, len(text), runs[0], runs[1], runs[2], runs[3],
            c.percentiles(runs)[1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cost", action="store_true")
    args = ap.parse_args()

    print("voice %s, model %s" % ((c.env("FISH_VOICE_ID") or "none")[:8],
                                  c.env("FISH_TTS_MODEL", c.TTS_MODEL)))
    sess = c.session()

    if args.cost:
        cost(sess)
        return

    rows = [run_case(n, l, t, sess) for n, l, t in CASES]

    print("\n| case | tag | sent chars | audio s | rms | silence | leaked | CER vs line |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %s | %d | %.2f | %d | %.2f | %s | %.3f |" % (
            r["name"], r["tag"] or "-", r["sent_chars"], r["seconds"], r["rms"],
            r["silence"], ",".join(r["leak"]) if r["leak"] else "no", r["cer"]))

    print("\nTranscripts, to show the bracket text is not in the audio:")
    for r in rows:
        print("  %-14s %s" % (r["name"], r["heard"]))

    base = {r["name"]: r for r in rows}
    print("\nChange against the untagged take of the same sentence:")
    for name, ref in (("apologetic", "plain"), ("sighing-tired", "plain"),
                      ("whisper", "plain"), ("open-domain", "plain"),
                      ("laughing", "plain2"), ("warm", "plain2")):
        a, b = base[name], base[ref]
        print("  %-14s duration %+.0f%%  rms %+.0f%%  silence %+.2f" % (
            name,
            100.0 * (a["seconds"] - b["seconds"]) / b["seconds"],
            100.0 * (a["rms"] - b["rms"]) / max(b["rms"], 1),
            a["silence"] - b["silence"]))

    any_leak = [r["name"] for r in rows if r["leak"]]
    print("\ntags read aloud: %s" % (", ".join(any_leak) if any_leak else "none"))


if __name__ == "__main__":
    main()
