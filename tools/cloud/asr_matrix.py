# How well does ASR hear Levantine Arabic, and does a language hint help?
#
# Every sentence is spoken by three different Arabic voices, Orion plus two
# others, so a bad score is a property of the recognizer and not of one voice.
# Mixed Arabic and English sentences are in the set on purpose: that is how
# people here actually talk, and it is the case that breaks recognizers.
#
#   python tools/cloud/asr_matrix.py                       both providers
#   python tools/cloud/asr_matrix.py --provider fish       Fish ASR only
#   python tools/cloud/asr_matrix.py --provider deepinfra  standby engine only

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

OUT = c.REPO / "logs" / "asr_matrix"

LEVANTINE = [
    "أوريون، قديش الساعة بعمّان هلأ؟",
    "شو عاصمة الأردن؟",
    "ما سمعتك منيح، ممكن تعيدها؟",
    "بدي أروح عالبترا بكرا الصبح",
]

MIXED = [
    "أوريون، افتحلي الـ Spotify",
    "في error بالـ code، شو أعمل؟",
    "شغّل الـ Wi-Fi على الـ PC",
]

VOICES = [
    ("orion", None),  # filled from FISH_VOICE_ID
    ("shami", "2b33ccddba42413f98533dd01929da79"),
    ("falastini", "607beda668e84c729b162ac755a9186f"),
]


def transcribe(provider, wav, language, sess):
    if provider == "fish":
        text, _, ms = c.asr(wav, language=language, sess=sess)
        return text, ms
    return c.stt_deepinfra(wav, language=language, sess=sess)


def run(provider, sess, save=False):
    voices = [(n, v or c.env("FISH_VOICE_ID")) for n, v in VOICES]
    cases = [("levantine", s) for s in LEVANTINE] + [("mixed", s) for s in MIXED]
    results = {}
    blocked = None

    for voice_name, voice_id in voices:
        for kind, sentence in cases:
            pcm, _, _ = c.tts(sentence, voice_id=voice_id, sess=sess,
                              model=c.env("FISH_TTS_MODEL", c.TTS_MODEL))
            wav = c.pcm_to_wav(pcm)
            if save:
                c.save_wav(OUT / voice_name / ("%s_%d.wav" % (kind, cases.index((kind, sentence)))), pcm)
            for hint_name, hint in (("no hint", None), ("language ar", "ar")):
                try:
                    heard, ms = transcribe(provider, wav, hint, sess)
                except RuntimeError as e:
                    blocked = str(e)[:150]
                    return None, blocked
                key = (kind, hint_name)
                row = results.setdefault(key, {"cer": [], "wer": [], "ms": [],
                                               "eng_ok": 0, "eng_total": 0,
                                               "samples": []})
                row["cer"].append(at.cer(sentence, heard))
                row["wer"].append(at.wer(sentence, heard))
                row["ms"].append(ms)
                found, want = at.kept_english(sentence, heard)
                row["eng_ok"] += found
                row["eng_total"] += want
                row["samples"].append((voice_name, sentence, heard))
    return results, None


def report(provider, results):
    print("\n### %s" % provider)
    print("| sentences | hint | mean CER | mean WER | English words kept | median ms |")
    print("|---|---|---|---|---|---|")
    for kind in ("levantine", "mixed"):
        for hint in ("no hint", "language ar"):
            row = results.get((kind, hint))
            if not row:
                continue
            eng = ("%d/%d" % (row["eng_ok"], row["eng_total"])) if row["eng_total"] else "-"
            print("| %s | %s | %.3f | %.3f | %s | %.0f |" % (
                kind, hint,
                sum(row["cer"]) / len(row["cer"]),
                sum(row["wer"]) / len(row["wer"]),
                eng, c.percentiles(row["ms"])[1]))
    print("\nTranscripts, language ar:")
    for kind in ("levantine", "mixed"):
        row = results.get((kind, "language ar"))
        if not row:
            continue
        for voice, said, heard in row["samples"]:
            print("  %-10s %-38s -> %s" % (voice, said[:38], heard))


def score_file(path):
    """Scores transcripts captured elsewhere, so the Fish numbers are auditable.

        The board talks to REST /v1/asr, which needs developer API credit and 402s
        without it. Fish's own recognizer can also be reached through the Fish Audio
        MCP server, which bills package credits. MCP is a PC-side tool, not a path
        the ESP32 can ever take, so those transcripts are recorded here rather than
        produced by this script.
    """
    import json

    data = json.loads(Path(path).read_text(encoding="utf-8"))
    buckets = {}
    for row in data["rows"]:
        key = (row["kind"], row["hint"])
        b = buckets.setdefault(key, {"cer": [], "wer": [], "eng_ok": 0,
                                     "eng_total": 0, "rows": []})
        b["cer"].append(at.cer(row["said"], row["heard"]))
        b["wer"].append(at.wer(row["said"], row["heard"]))
        found, want = at.kept_english(row["said"], row["heard"])
        b["eng_ok"] += found
        b["eng_total"] += want
        b["rows"].append(row)

    print("\n### %s" % data["engine"])
    print("| sentences | hint | mean CER | mean WER | English words kept | n |")
    print("|---|---|---|---|---|---|")
    for kind in ("levantine", "mixed"):
        for hint in ("no hint", "language ar"):
            b = buckets.get((kind, hint))
            if not b:
                continue
            eng = ("%d/%d" % (b["eng_ok"], b["eng_total"])) if b["eng_total"] else "-"
            print("| %s | %s | %.3f | %.3f | %s | %d |" % (
                kind, hint, sum(b["cer"]) / len(b["cer"]),
                sum(b["wer"]) / len(b["wer"]), eng, len(b["cer"])))

    print("\nPer sentence, language ar:")
    for kind in ("levantine", "mixed"):
        b = buckets.get((kind, "language ar"))
        if not b:
            continue
        for row in b["rows"]:
            print("  %-10s %.3f  %-32s -> %s" % (
                row["voice"], at.cer(row["said"], row["heard"]),
                row["said"][:32], row["heard"]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--provider", default="both",
                    choices=["fish", "deepinfra", "both"])
    ap.add_argument("--score-file", default=None,
                    help="score transcripts captured through the Fish MCP server")
    ap.add_argument("--save", action="store_true", help="keep the generated WAVs")
    args = ap.parse_args()

    if args.score_file:
        score_file(args.score_file)
        return

    print("tts model %s, voice %s" % (c.env("FISH_TTS_MODEL", c.TTS_MODEL),
                                      (c.env("FISH_VOICE_ID") or "none")[:8]))
    sess = c.session()
    providers = ["fish", "deepinfra"] if args.provider == "both" else [args.provider]
    for provider in providers:
        results, blocked = run(provider, sess, save=args.save)
        if blocked:
            print("\n### %s\nBLOCKED: %s" % (provider, blocked))
            continue
        report(provider, results)


if __name__ == "__main__":
    main()
