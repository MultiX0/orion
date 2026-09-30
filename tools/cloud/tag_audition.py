# Which Fish S2 bracket tags does the Orion voice actually perform, in Arabic
# and in English? A tag is kept only if it never leaks into the audio and it
# moves the delivery beyond take to take noise: a Welch t of 3 or more against
# the plain takes on at least one measured feature.
#
# Delivery is measured, not judged by ear: duration, loudness, pause ratio,
# median pitch and pitch range. Leaks are found by transcribing every take.
#
#   python tools/cloud/tag_audition.py
#   python tools/cloud/tag_audition.py --only "[calm],[happy]" --label focus

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

OUT = c.REPO / "logs" / "tag_audition"
MODEL = "s2.1-pro-free"

SENT = {
    "ar": "وجدتُ لك ثلاث وصفات سهلة، أولها جاهزة في عشرين دقيقة.",
    "en": "I found three easy recipes, and the first one is ready in twenty minutes.",
}
# Tags that act on a word go mid sentence, as the docs place them.
MID = {"ar": ("وجدتُ لك ", "ثلاث وصفات سهلة، أولها جاهزة في عشرين دقيقة."),
       "en": ("I found ", "three easy recipes, and the first one is ready in twenty minutes.")}

# From the Emotion Control page: basic and advanced emotions, tone markers,
# audio effects, intensity modifiers, pairs. Plus the four v1 tags.
TAGS = [
    "[happy]", "[excited]", "[calm]", "[confident]", "[empathetic]", "[curious]",
    "[satisfied]", "[delighted]", "[grateful]", "[sympathetic]", "[regretful]",
    "[surprised]", "[relieved]", "[encouraging]", "[friendly]",
    "[warm]", "[playful]", "[apologetic]", "[thoughtful]",
    "[soft tone]", "[whispering]", "[in a hurry tone]",
    "[chuckling]", "[laughing]", "[sighing]",
    "[slightly sad]", "[very excited]",
    "[happy][chuckling]", "[empathetic][soft tone]",
    "mid:[emphasis]", "mid:[break]",
]

TAG_WORDS = ("happy", "excited", "calm", "confident", "empathetic", "curious", "satisfied",
             "delighted", "grateful", "sympathetic", "regretful", "surprised", "relieved",
             "encouraging", "friendly", "warm", "playful", "apologetic", "thoughtful", "soft",
             "tone", "whisper", "hurry", "chuckl", "laugh", "sigh", "slightly", "emphasis",
             "break", "sad")


def text_for(tag, lang):
    if tag.startswith("mid:"):
        a, b = MID[lang]
        return a + tag[4:] + " " + b
    return tag + " " + SENT[lang] if tag else SENT[lang]


def pitch_track(pcm, rate=c.SAMPLE_RATE):
    """Frame autocorrelation F0 in Hz for voiced frames, 40 ms hop 20 ms."""
    x = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
    n, hop = int(0.04 * rate), int(0.02 * rate)
    lo, hi = int(rate / 400), int(rate / 90)
    f0 = []
    for s in range(0, len(x) - n, hop):
        fr = x[s:s + n] - x[s:s + n].mean()
        if np.sqrt((fr * fr).mean()) < 0.02:
            continue
        ac = np.correlate(fr, fr, "full")[n - 1:]
        if ac[0] <= 0:
            continue
        lag = lo + int(np.argmax(ac[lo:hi]))
        if ac[lag] / ac[0] > 0.45:
            f0.append(rate / lag)
    return np.array(f0)


def features(pcm):
    st = c.pcm_stats(pcm)
    f0 = pitch_track(pcm)
    semis = 12 * np.log2(f0 / 100.0) if len(f0) else np.array([0.0])
    return {"seconds": round(c.pcm_seconds(pcm), 2),
            "rms_db": round(20 * np.log10(max(st["rms"], 1) / 32767.0), 1),
            "silence": round(st["silence_ratio"], 3),
            "f0_st": round(float(np.median(semis)), 2),
            "f0_range_st": round(float(np.percentile(semis, 90) - np.percentile(semis, 10)), 2)}


def leaked(heard, lang, bare):
    low = heard.lower()
    if "[" in heard or "]" in heard:
        return "bracket"
    for w in TAG_WORDS:
        if w in low and w not in bare.lower():
            return w
    return ""


def take(text, lang, sess, label):
    pcm, _, _ = c.tts(text, voice_id=c.env("FISH_VOICE_ID"), sess=sess, model=MODEL)
    c.save_wav(OUT / lang / (label + ".wav"), pcm)
    heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language=lang, sess=sess)
    f = features(pcm)
    f["heard"] = heard
    f["cer"] = round(at.cer(SENT[lang], heard) if lang == "ar" else
                     at.edit_distance(SENT[lang].lower(), heard.lower().strip()) / len(SENT[lang]), 3)
    f["leak"] = leaked(heard, lang, SENT[lang])
    return f


FEATS = ("seconds", "rms_db", "silence", "f0_st", "f0_range_st")
T_MIN = 3.0   # Welch t this far from the plain takes counts as a real change


def welch_t(a, b):
    a, b = np.array(a, float), np.array(b, float)
    va = a.var(ddof=1) / len(a) if len(a) > 1 else 0.0
    vb = b.var(ddof=1) / len(b) if len(b) > 1 else 0.0
    se = np.sqrt(va + vb) or 1e-9
    return float((a.mean() - b.mean()) / se)


def moved(tagged, plains):
    """Features where the tagged takes differ from the plain takes beyond noise."""
    out = []
    for k in FEATS:
        t = welch_t([x[k] for x in tagged], [p[k] for p in plains])
        if abs(t) >= T_MIN:
            out.append("%s%s(t=%.1f)" % (k, "+" if t > 0 else "-", t))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--label", default="run")
    ap.add_argument("--takes", type=int, default=4)
    ap.add_argument("--plain", type=int, default=6)
    args = ap.parse_args()
    tags = args.only.split(",") if args.only else TAGS
    sess = c.session()
    result = {}
    for lang in ("ar", "en"):
        plains = [take(text_for("", lang), lang, sess, "plain_%d" % i)
                  for i in range(1, args.plain + 1)]
        print("\n%s plain: %s" % (lang, [(p["seconds"], p["rms_db"], p["f0_st"],
                                            p["f0_range_st"]) for p in plains]))
        result[lang] = {"plain": plains, "tags": {}}
        for tag in tags:
            name = tag.replace("mid:", "mid_").strip("[]").replace("][", "+").replace(" ", "_")
            tk = [take(text_for(tag, lang), lang, sess, "%s_%d" % (name, i + 1))
                  for i in range(args.takes)]
            mv = moved(tk, plains)
            leak = [t["leak"] for t in tk if t["leak"]]
            verdict = "DROP leak" if leak else ("KEEP" if mv else "DROP no change")
            # Much harder to transcribe than plain: flagged for a look, not dropped,
            # since a laugh transcribed as ههه is a performance, not a leak.
            if min(t["cer"] for t in tk) > max(p["cer"] for p in plains) + 0.12:
                verdict += " garbled?"
            result[lang]["tags"][tag] = {"takes": tk, "moved": mv, "leak": leak,
                                         "verdict": verdict}
            print("%-26s %-15s moved %-40s cer %s  %s" % (
                tag, verdict, ",".join(mv) or "-", [t["cer"] for t in tk], tk[0]["heard"][:50]))
    out = OUT / ("tag_audition_%s.json" % args.label)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
