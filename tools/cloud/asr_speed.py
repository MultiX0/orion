# Which recognizer should the board call? Speed first, but not at the price of
# hearing the user wrong, and never at the price of translating them.
#
# On whisper-large-v3, ASR is the single biggest cost of a turn: 9 to 11 s for
# about 2 s of speech. This runs every speech model DeepInfra serves over the
# same clips, with no language hint, and reports latency, CER, and whether an
# English question came back as English.
#
# No language hint. With "ar", whisper translates an English question into
# Arabic ("What is the capital of France?" comes back as "ما هو مدينة فرنسا؟"),
# and asr_matrix.py shows the hint buys no accuracy.
#
#   python tools/cloud/asr_speed.py
#   python tools/cloud/asr_speed.py --runs 5 --models openai/whisper-large-v3-turbo

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

MODELS = [
    "openai/whisper-large-v3",
    "openai/whisper-large-v3-turbo",
    "Qwen/Qwen3-ASR-1.7B",
    "Qwen/Qwen3-ASR-0.6B",
    "mistralai/Voxtral-Mini-3B-2507",
    "nvidia/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b",
]

# Users speak Levantine, so the questions are spoken by two Levantine library
# voices standing in for a person, not by the Orion voice.
SPEAKERS = [
    ("urduni", "ec69015cc6f04316a1db3c83279cca0e"),
    ("shami", "2b33ccddba42413f98533dd01929da79"),
]

ARABIC = [
    "شو عاصمة الأردن؟",
    "قديش الساعة بعمّان هلأ؟",
    "بدي أروح عالبترا بكرا الصبح",
    "احكيلي نكتة قصيرة",
]
MIXED = [
    "افتحلي الـ Spotify",
    "شغّل الـ Wi-Fi على الـ PC",
]
ENGLISH = [
    "What is the capital of France?",
    "Tell me a short joke.",
]

# The integration test clips, question only, no wake word. Real board inputs.
CLIPS = [
    ("clip ar_time", "logs/test/ar_time.wav", "قديش الساعة بعمان هلأ؟"),
    ("clip en_france", "logs/test/en_france.wav", "What is the capital of France?"),
]

ARABIC_CH = re.compile(r"[؀-ۿ]")


def build_set(sess):
    """(label, kind, reference text, wav bytes). Generated once, reused per model."""
    items = []
    model = c.env("FISH_TTS_MODEL", c.TTS_MODEL)
    for name, vid in SPEAKERS:
        for kind, lines in (("arabic", ARABIC), ("mixed", MIXED)):
            for line in lines:
                pcm, _, _ = c.tts(line, voice_id=vid, sess=sess, model=model)
                items.append(("%s %s" % (name, kind), kind, line, c.pcm_to_wav(pcm)))
    # English from the model's default voice: the Levantine voices are not the
    # right stand in for someone asking in English.
    for line in ENGLISH:
        pcm, _, _ = c.tts(line, sess=sess, model=model)
        items.append(("default english", "english", line, c.pcm_to_wav(pcm)))
    for label, path, ref in CLIPS:
        p = c.REPO / path
        if p.exists():
            pcm, _ = c.load_wav(p)
            kind = "english" if not ARABIC_CH.search(ref) else "arabic"
            items.append((label, kind, ref, c.pcm_to_wav(pcm)))
    return items


def score(ref, heard, kind):
    if kind == "english":
        # Arabic letters in the answer to an English question is the translate
        # bug, and it is the failure that matters most here.
        translated = bool(ARABIC_CH.search(heard))
        return at.wer(ref.lower(), heard.lower()), translated
    return at.cer(ref, heard), False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--models", nargs="*", default=MODELS)
    ap.add_argument("--show", action="store_true", help="print every transcript")
    args = ap.parse_args()

    sess = c.session()
    print("building the test set...")
    items = build_set(sess)
    print("%d clips\n" % len(items))

    rows = []
    for model in args.models:
        lat, errs, translated, failures = [], {"arabic": [], "mixed": [], "english": []}, 0, 0
        for label, kind, ref, wav in items:
            best = None
            for _ in range(args.runs):
                try:
                    heard, ms = c.stt_deepinfra(wav, language=None, sess=sess, model=model)
                except RuntimeError as e:
                    failures += 1
                    if failures == 1:
                        print("  %s: %s" % (model, str(e)[:120]))
                    continue
                lat.append(ms)
                best = heard
            if best is None:
                continue
            err, tr = score(ref, best, kind)
            errs[kind].append(err)
            translated += int(tr)
            if args.show:
                print("  %-34s %-15s %.2f %s" % (model[-34:], label, err, best))
        if not lat:
            rows.append((model, None))
            continue
        lo, med, p95, hi = c.percentiles(lat)
        mean = lambda v: (sum(v) / len(v)) if v else float("nan")
        rows.append((model, (med, p95, mean(errs["arabic"]), mean(errs["mixed"]),
                             mean(errs["english"]), translated, len(errs["english"]),
                             failures)))

    print("\n| model | median ms | p95 ms | Arabic CER | mixed CER | English WER | English translated | errors |")
    print("|---|---|---|---|---|---|---|---|")
    for model, r in rows:
        if r is None:
            print("| %s | failed | | | | | | |" % model)
            continue
        med, p95, ar, mx, en, tr, n_en, fails = r
        print("| %s | %.0f | %.0f | %.3f | %.3f | %.3f | %d of %d | %d |" % (
            model, med, p95, ar, mx, en, tr, n_en, fails))


if __name__ == "__main__":
    main()
