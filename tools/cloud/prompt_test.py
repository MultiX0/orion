# Does firmware/assets/system_prompt.txt actually produce the voice we
# want? Ten Arabic questions, five English ones, replies logged verbatim.
#
# The checks are the things that break speech, not things that are a matter of
# taste: digits the TTS would read as numerals, markdown it would read as
# asterisks, an answer that ran to six sentences, an English question answered
# in Arabic.
#
#   python tools/cloud/prompt_test.py
#   python tools/cloud/prompt_test.py --speak         also synthesize each reply
#   python tools/cloud/prompt_test.py --tts openai    the prompt a non-Fish voice gets

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

PROMPT_FILE = c.PROMPT_FILE
OUT = c.REPO / "logs" / "prompt_test"

ARABIC = [
    "شو عاصمة الأردن؟",
    "قديش الساعة هلأ بعمّان؟",
    "كيف الجو اليوم؟",
    "شو بتعرف عن البترا؟",
    "احكيلي نكتة قصيرة",
    "شغّللي أغنية على الـ Spotify",
    "شو أحسن طريقة أتعلم برمجة؟",
    "كم عدد سكان الأردن تقريباً؟",
    "نسيت شو كان اسمك؟",
    "بدي أطبخ مقلوبة، شو بلزمني؟",
]

ENGLISH = [
    "What is the capital of Jordan?",
    "How do I restart a stuck ESP32?",
    "Tell me a very short joke",
    "What time zone is Amman in?",
    "Explain what PSRAM is in one line",
]

EMOJI = re.compile("[\U0001F000-\U0001FAFF☀-➿️]")
MARKDOWN = re.compile(r"[*#`_]|^\s*[-•]\s", re.M)

# Fish S2 cues are free natural language and may sit anywhere in a sentence,
# so there is no allowlist. What still breaks: two cues side by side, a cue
# not in English (the voice may read it), and any cue at all when the voice is
# not Fish.
TAG = re.compile(r"\[[^\]]{1,40}\]")
STACKED = re.compile(r"\]\s*\[")
NON_ENGLISH_TAG = re.compile(r"\[[^\]]*[^\x20-\x7e\]][^\]]*\]")
# Standalone numbers only: part names like ESP32-S3, OV2640 or S2.1 are read fine.
DIGITS = re.compile(r"(?<![A-Za-z0-9.-])\d+(?![A-Za-z])")
ARABIC_CH = re.compile(r"[؀-ۿ]")


def sentences(text):
    parts = [p for p in re.split(r"[.!?؟۔\n]+", text) if p.strip()]
    return len(parts)


def tags_in(reply):
    return TAG.findall(reply)


def check(question, reply, fish=True):
    """Returns a list of short problem strings. Empty means the reply is clean."""
    bad = []
    tags = tags_in(reply)
    if tags and not fish:
        bad.append("tag with a non-Fish voice")
    if STACKED.search(reply):
        bad.append("cues side by side")
    for tag in NON_ENGLISH_TAG.findall(reply):
        bad.append("cue not in English %s" % tag)
    # Everything after this point judges the words, not the tag.
    reply = TAG.sub("", reply).strip()
    want_arabic = bool(ARABIC_CH.search(question))
    got_arabic = bool(ARABIC_CH.search(reply))
    if want_arabic and not got_arabic:
        bad.append("answered English to an Arabic question")
    if not want_arabic and got_arabic:
        bad.append("answered Arabic to an English question")
    if EMOJI.search(reply):
        bad.append("emoji")
    if MARKDOWN.search(reply):
        bad.append("markdown")
    if DIGITS.search(reply):
        bad.append("digits, TTS wants words")
    n = sentences(reply)
    if n > 3:
        bad.append("%d sentences" % n)
    if len(reply) > 260:
        bad.append("%d chars" % len(reply))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speak", action="store_true", help="synthesize every reply too")
    ap.add_argument("--em-dash-check", action="store_true", default=True)
    ap.add_argument("--tts", choices=("fish", "openai"), default="fish",
                    help="which voice the prompt is cut for, as the board does")
    args = ap.parse_args()
    fish = args.tts == "fish"

    prompt = c.system_prompt(fish=fish)
    print("system prompt: %s for %s, %d chars" % (PROMPT_FILE.name, args.tts, len(prompt)))
    print("llm          : %s" % c.env("LLM_MODEL"))
    print("voice        : %s" % (c.env("FISH_VOICE_ID")[:8] or "none"))

    sess = c.session()
    rows = []
    for q in ARABIC + ENGLISH:
        msg, ms = c.chat([{"role": "system", "content": prompt},
                          {"role": "user", "content": q}], sess=sess)
        reply = (msg.get("content") or "").strip()
        problems = check(q, reply, fish)
        row = {"q": q, "reply": reply, "ms": ms, "problems": problems}
        if args.speak:
            pcm, first, total = c.tts(reply, voice_id=c.env("FISH_VOICE_ID") or None,
                                      sess=sess, model=c.env("FISH_TTS_MODEL", c.TTS_MODEL))
            name = "reply_%02d.wav" % (len(rows) + 1)
            c.save_wav(OUT / name, pcm)
            row["speak_s"] = c.pcm_seconds(pcm)
            row["ttfb"] = first
        rows.append(row)
        print("\nQ: %s" % q)
        print("A: %s" % reply)
        print("   %.0f ms%s  tag %s%s" % (
            ms,
            ("  speak %.1f s" % row["speak_s"]) if "speak_s" in row else "",
            ", ".join(tags_in(reply)) or "none",
            ("  PROBLEM: " + ", ".join(problems)) if problems else "  clean"))

    tagged = [r for r in rows if tags_in(r["reply"])]
    print("\n%d of %d replies used a tone tag" % (len(tagged), len(rows)))
    for r in tagged:
        print("  %-34s %s" % (r["q"][:34], ", ".join(tags_in(r["reply"]))))

    clean = sum(1 for r in rows if not r["problems"])
    print("\n%d of %d replies clean" % (clean, len(rows)))
    lat = [r["ms"] for r in rows]
    lo, med, p95, hi = c.percentiles(lat)
    print("llm latency min %.0f median %.0f p95 %.0f max %.0f ms" % (lo, med, p95, hi))
    lens = [len(r["reply"]) for r in rows]
    print("reply length median %d chars" % c.percentiles(lens)[1])
    if args.speak:
        spk = [r["speak_s"] for r in rows if "speak_s" in r]
        print("spoken length median %.1f s, max %.1f s" % (
            c.percentiles(spk)[1], max(spk)))
    for r in rows:
        if r["problems"]:
            print("  still wrong: %s -> %s" % (r["q"][:34], ", ".join(r["problems"])))


if __name__ == "__main__":
    main()
