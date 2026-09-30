# Runs the exact voice loop the board runs, from the PC, with the exact formats.
#
#   16 kHz mono WAV -> Fish ASR -> DeepInfra chat -> Fish TTS as raw PCM -> WAV
#
# This exists so every API detail is proved before any of it is written in C.
#
#   python tools/cloud/loop_test.py --runs 10
#   python tools/cloud/loop_test.py --text "شو عاصمة الأردن؟"   skip ASR, type the turn
#   python tools/cloud/loop_test.py --wav logs/me.wav           use a real recording
#   python tools/cloud/loop_test.py --latency-modes             compare low/normal/balanced

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c
import prompt_bench

OUT = c.REPO / "logs" / "loop_test"
SYSTEM_PROMPT_FILE = c.REPO / "firmware" / "assets" / "system_prompt.txt"

# Used to make the input audio when no WAV is given. Deliberately not the Orion
# voice, so ASR is never transcribing the voice that produced it.
ASKER_VOICE = "2b33ccddba42413f98533dd01929da79"

DEFAULT_QUESTION = "أوريون، شو عاصمة الأردن؟"


def system_prompt():
    if SYSTEM_PROMPT_FILE.exists():
        return c.system_prompt()
    return "You are Orion. Reply in spoken Levantine Arabic, one to three short sentences."


def tts_model():
    return c.env("FISH_TTS_MODEL", c.TTS_MODEL)


def voice_id():
    return c.env("FISH_VOICE_ID") or None


def make_input_wav(text, sess):
    """Synthesize the question once so every run transcribes identical bytes."""
    pcm, _, _ = c.tts(text, voice_id=ASKER_VOICE, sess=sess, model=tts_model())
    return c.pcm_to_wav(pcm)


def one_turn(wav, sess, history, typed_text=None, asr_language=None, tools=None):
    """One full turn. Returns a dict of stage timings and the texts."""
    row = {"asr_ms": None, "llm_ms": None, "tts_first_ms": None,
           "tts_total_ms": None, "heard": typed_text or "", "reply": "",
           "asr_error": None}

    t_start = time.perf_counter()

    if typed_text is None:
        try:
            heard, _, asr_ms = c.asr(wav, language=asr_language, sess=sess)
            row["heard"] = heard
            row["asr_ms"] = asr_ms
        except RuntimeError as e:
            row["asr_error"] = str(e)[:120]
            return row

    messages = [{"role": "system", "content": system_prompt()}]
    messages += history
    messages.append({"role": "user", "content": row["heard"]})

    msg, llm_ms = c.chat(messages, sess=sess, tools=tools)
    row["reply"] = (msg.get("content") or "").strip()
    row["llm_ms"] = llm_ms
    if msg.get("tool_calls"):
        row["tool_call"] = msg["tool_calls"][0]["function"]["name"]
        return row

    pcm, first, total = c.tts(row["reply"], voice_id=voice_id(), sess=sess,
                              model=tts_model())
    row["tts_first_ms"] = first
    row["tts_total_ms"] = total
    row["pcm"] = pcm
    row["total_ms"] = (time.perf_counter() - t_start) * 1000.0
    row["speak_s"] = c.pcm_seconds(pcm)
    return row


def table(rows, keys):
    print()
    print("| stage | min | median | p95 | max |")
    print("|---|---|---|---|---|")
    for key, label in keys:
        vals = [r[key] for r in rows if r.get(key) is not None]
        if not vals:
            print("| %s | blocked | blocked | blocked | blocked |" % label)
            continue
        lo, med, p95, hi = c.percentiles(vals)
        print("| %s | %.0f | %.0f | %.0f | %.0f |" % (label, lo, med, p95, hi))


def latency_modes(sess):
    """Which latency mode actually gives the lowest time to first audio."""
    text = "الجو اليوم بعمّان حلو، حوالي خمسة وعشرين درجة."
    print("\nTTS latency modes, 3 runs each, time to first PCM byte")
    print("| mode | run1 | run2 | run3 | median | audio s |")
    print("|---|---|---|---|---|---|")
    for mode in ("low", "balanced", "normal"):
        firsts, secs = [], 0
        for _ in range(3):
            pcm, first, _ = c.tts(text, voice_id=voice_id(), sess=sess,
                                  model=tts_model(), latency=mode)
            firsts.append(first)
            secs = c.pcm_seconds(pcm)
        print("| %s | %.0f | %.0f | %.0f | %.0f | %.2f |" % (
            mode, firsts[0], firsts[1], firsts[2],
            c.percentiles(firsts)[1], secs))


def dbfs(value):
    """Full scale is 32767. Returns -inf as a printable floor."""
    if value <= 0:
        return -99.0
    import math
    return 20.0 * math.log10(min(value, 32767) / 32767.0)


# The speaker has to be as loud as the hardware safely allows, and PCM that
# arrives hotter needs less gain on the device and limits more cleanly. This
# finds the most gain the encoder will give us before it starts hard clipping.
GAIN_LINES = [
    "أهلين! أنا أوريون، شو بتحب أساعدك فيه اليوم؟",
    "الجو اليوم بعمّان حلو، حوالي خمسة وعشرين درجة.",
    "صار في مشكلة عندي، جرّب كمان مرة.",
]


def gain_sweep(sess, steps=(0, 2, 4, 6, 8, 10)):
    print("\nprosody.volume sweep, %d Arabic lines per step, "
          "normalize_loudness true" % len(GAIN_LINES))
    print("| volume dB | peak dBFS | rms dBFS | clipped samples | median ttfb ms |")
    print("|---|---|---|---|---|")

    clean = []
    ttfb_by_step = {}
    for db in steps:
        peaks, rmss, clips, firsts = [], [], [], []
        for line in GAIN_LINES:
            pcm, first, _ = c.tts(
                line, voice_id=voice_id(), sess=sess, model=tts_model(),
                prosody={"volume": db, "normalize_loudness": True})
            st = c.pcm_stats(pcm)
            peaks.append(st["peak"])
            rmss.append(st["rms"])
            clips.append(st["clipped"])
            firsts.append(first)
        total_clipped = sum(clips)
        ttfb_by_step[db] = c.percentiles(firsts)[1]
        print("| %+d | %.1f | %.1f | %d | %.0f |" % (
            db, dbfs(max(peaks)),
            dbfs(sum(rmss) / len(rmss)), total_clipped, ttfb_by_step[db]))
        if total_clipped == 0:
            clean.append(db)

    if not clean:
        print("\nEverything clipped, including 0 dB. Do not raise the source.")
        return

    highest = max(clean)
    chosen = max(0, highest - 1)
    print("\nhighest clean setting %+d dB, one dB back for margin -> "
          "**%+d dB**" % (highest, chosen))
    print("time to first audio, 0 dB %.0f ms against %+d dB %.0f ms" % (
        ttfb_by_step[0], highest, ttfb_by_step[highest]))


def connection_reuse(sess):
    """Measures what keeping the TLS connection open is worth, the board does this."""
    text = "تمام."
    fresh = []
    for _ in range(3):
        s = c.session()
        _, first, _ = c.tts(text, voice_id=voice_id(), sess=s, model=tts_model())
        fresh.append(first)
        s.close()
    warm = []
    c.tts(text, voice_id=voice_id(), sess=sess, model=tts_model())
    for _ in range(3):
        _, first, _ = c.tts(text, voice_id=voice_id(), sess=sess, model=tts_model())
        warm.append(first)
    print("\nTLS connection reuse, time to first PCM byte")
    print("| connection | median ms |")
    print("|---|---|")
    print("| new TLS handshake per call | %.0f |" % c.percentiles(fresh)[1])
    print("| kept alive between calls | %.0f |" % c.percentiles(warm)[1])
    print("| saving | %.0f |" % (c.percentiles(fresh)[1] - c.percentiles(warm)[1]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--text", default=None, help="skip ASR, use this as the transcript")
    ap.add_argument("--wav", default=None, help="16 kHz mono WAV to transcribe")
    ap.add_argument("--question", default=DEFAULT_QUESTION)
    ap.add_argument("--language", default=None, help="ASR language hint")
    ap.add_argument("--latency-modes", action="store_true")
    ap.add_argument("--reuse", action="store_true")
    ap.add_argument("--gain-sweep", action="store_true")
    ap.add_argument("--save", action="store_true", help="write every reply WAV")
    ap.add_argument("--prompt-bench", nargs="+", default=None,
                    help="system prompt files, LLM time to first token compared")
    ap.add_argument("--questions", action="store_true",
                    help="the 10 Arabic and 5 English question set, replies verbatim")
    args = ap.parse_args()

    print("fish key  %s" % c.key_fingerprint(c.env("FISH_API_KEY")))
    print("di key    %s" % c.key_fingerprint(c.env("DEEPINFRA_API_KEY")))
    print("tts model %s" % tts_model())
    print("voice id  %s" % (voice_id() or "NOT SET, model default voice"))
    print("llm       %s" % c.env("LLM_MODEL", "google/gemma-4-31B-it-turbo"))

    sess = c.session()

    if args.latency_modes:
        latency_modes(sess)
        return
    if args.reuse:
        connection_reuse(sess)
        return
    if args.gain_sweep:
        gain_sweep(sess)
        return
    if args.prompt_bench:
        prompt_bench.bench(args.prompt_bench, sess, runs=args.runs)
        return
    if args.questions:
        prompt_bench.questions(sess, one_turn, OUT / "questions")
        return

    wav = None
    typed = args.text
    if typed is None:
        if args.wav:
            pcm, rate = c.load_wav(args.wav)
            if rate != c.SAMPLE_RATE:
                raise SystemExit("%s is %d Hz, the board records 16000" % (args.wav, rate))
            wav = c.pcm_to_wav(pcm)
        else:
            print("\nmaking the input WAV with a library voice, 16 kHz mono")
            wav = make_input_wav(args.question, sess)
            c.save_wav(OUT / "input.wav", wav[44:])
            print("wrote %s, %.2f s" % (OUT / "input.wav", c.pcm_seconds(wav[44:])))

    rows = []
    for i in range(args.runs):
        row = one_turn(wav, sess, [], typed_text=typed, asr_language=args.language)
        if row["asr_error"]:
            print("\nrun %d ASR FAILED: %s" % (i + 1, row["asr_error"]))
            print("falling back to the typed transcript so the rest of the loop is measured")
            typed = args.question
            row = one_turn(wav, sess, [], typed_text=typed)
        rows.append(row)
        if args.save and row.get("pcm"):
            c.save_wav(OUT / ("reply_%02d.wav" % (i + 1)), row["pcm"])
        print("run %2d  asr %s  llm %5.0f  ttfb %5.0f  tts %5.0f  total %5.0f  speak %.1fs" % (
            i + 1,
            ("%5.0f" % row["asr_ms"]) if row["asr_ms"] else "   --",
            row["llm_ms"], row["tts_first_ms"], row["tts_total_ms"],
            row["total_ms"], row["speak_s"]))
        print("        heard: %s" % row["heard"])
        print("        reply: %s" % row["reply"])

    table(rows, [("asr_ms", "Fish ASR"), ("llm_ms", "DeepInfra chat"),
                 ("tts_first_ms", "Fish TTS first byte"),
                 ("tts_total_ms", "Fish TTS complete"),
                 ("total_ms", "turn total")])
    spoken = [r["speak_s"] for r in rows if r.get("speak_s")]
    if spoken:
        print("\nreply audio: median %.2f s, %d runs" % (
            c.percentiles(spoken)[1], len(spoken)))


if __name__ == "__main__":
    main()
