# Second voice audition: a female voice speaking fluent Modern Standard Arabic
# in the conversational register of a phone assistant, not a dialect and not a
# newsreader. English tech words stay English; English questions get English.
#
# Generation uses REST /v1/tts on s2.1-pro-free (free, uncapped). Every clip is
# scored by whisper here; Fish ASR scores a per-candidate concatenation through
# the MCP server, and those transcripts are merged in with --fish-file.
#
#   python tools/cloud/voice_audition_v2.py --screen          3 lines, all candidates
#   python tools/cloud/voice_audition_v2.py --only a,b,c       full audition
#   python tools/cloud/voice_audition_v2.py --table --fish-file voice/auditions_v2/fish_asr.json

import argparse
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

OUT = c.REPO / "voice" / "auditions_v2"
SCREEN = c.REPO / "logs" / "voice_screen"
MODEL = "s2.1-pro-free"
NAME = "أوريون"
NAME_VOWELLED = "أُورْيُون"   # what cloud_tts.c substitutes before every request

# (key, text, language). line1v is line1 exactly as the firmware sends it.
LINES = [
    ("line1", "مرحباً، أنا أوريون. كيف يمكنني مساعدتك اليوم؟", "ar"),
    ("line1v", "مرحباً، أنا أُورْيُون. كيف يمكنني مساعدتك اليوم؟", "ar"),
    ("line2", "لحظة من فضلك، دعني أتحقق من ذلك.", "ar"),
    ("line3", "الطقس في عمّان اليوم معتدل، حوالي خمس وعشرين درجة.", "ar"),
    ("line4", "فتحتُ لك Spotify على الكمبيوتر.", "ar"),
    ("line5", "عذراً، لم أسمعك جيداً. هل يمكنك الإعادة؟", "ar"),
    ("line6", "Hi, I'm Orion. I opened Spotify on your PC and the Wi-Fi is back.", "en"),
]
SCREEN_LINES = ("line1", "line4", "line6")

# Female voices from the public library, chosen by search_voices and get_voice.
# Titles named after real people were left out on purpose.
CANDIDATES = [
    ("hanan", "05bf47f4aad948e1a7167a56e1d21c22", "حنان, young, clear, smooth ad voice, Gulf demo text"),
    ("qatheed", "564ff4b232d6427f91513321de5fb651", "قثيض, crisp professional ad voice, Gulf demo text"),
    ("anf", "93edb401ddf94e9a836a74f141be5258", "جهاز تشكيل الأنف, soft friendly ad voice"),
    ("musaida", "48ed36090a1e4ec3b9d15942e9b2d4cd", "مساعدة صوتية عربية, MSA voice assistant, IVR"),
    ("mutasil", "5a5beb26062f47f39f22fa7bc0fc896d", "مساعد المتصل الآلي, MSA IVR, neutral tone"),
    ("young-female", "44e838fce9994911b881c18d9eede34c", "Young Arabic Female, ar+en, Homs demo text"),
    ("unthawi-arabi", "f2acd2bec2db4cf1827172299c2900ef", "صوت أنثوي عربي, young conversational MSA"),
    ("unthawi", "81c63e6a5ff141d38367fcb009c570d6", "صوت أنثوي, warm friendly educational MSA"),
    ("arabic-narr", "cbdbcd3cb1684b8bbf2a2f7951b282a9", "arabic, calm clear MSA narration"),
    ("emily", "b1c153a84b41474783311c485d5025c6", "ايميلي, calm warm MSA narration"),
    ("qamboul", "29d41d1f68414669baecac1bd4868b39", "قامبول, calm smooth MSA narration"),
    ("ikhbariya", "1693db0d470c45e98b5531c1730db85e", "مذيعة إخبارية, newsreader, the register to avoid"),
    ("wadood", "5b7d9bb80a3f4c3c9b7e561fe584fe97", "صوت أنثوي ودود, warm friendly conversational"),
    ("hadi", "fc49993f553046aa868183fc66c24868", "صوت أنثوي هادئ, soft calm neutral tone"),
]

# Transcribers write numerals for spelled numbers. That is not a pronunciation
# fault, so the numeral is spelled back before scoring.
NUMERALS = {"25": "خمس وعشرين", "٢٥": "خمس وعشرين", "خمسة وعشرين": "خمس وعشرين"}


def dbfs(v):
    return 20.0 * math.log10(v / 32767.0) if v > 0 else -99.0


def fold_numbers(text):
    for k, v in NUMERALS.items():
        text = text.replace(k, v)
    return text


def name_ok(heard, lang):
    """Did the name come back whole? Arabic wants the leading alef too."""
    if lang == "en":
        return "orion" in heard.lower()
    norm = at.normalize(heard)
    return "اوريون" in norm.replace(" ", "")


def score_line(ref, heard, lang):
    heard = fold_numbers(heard)
    ref_plain = ref.replace(NAME_VOWELLED, NAME)
    row = {"heard": heard, "cer": round(at.cer(ref_plain, heard) if lang == "ar"
                                        else en_cer(ref_plain, heard), 3)}
    found, want = at.kept_english(ref_plain, heard)
    if want:
        row["english_kept"] = "%d/%d" % (found, want)
    if "Orion" in ref or NAME in ref_plain:
        row["name_ok"] = name_ok(heard, lang)
    return row


def en_cer(ref, hyp):
    a = "".join(ch for ch in ref.lower() if ch.isalnum())
    b = "".join(ch for ch in hyp.lower() if ch.isalnum())
    return at.edit_distance(a, b) / float(len(a) or 1)


def audition(name, voice_id, sess, keys, folder):
    rows = []
    for key, text, lang in LINES:
        if key not in keys:
            continue
        pcm, first, _ = c.tts(text, voice_id=voice_id, sess=sess, model=MODEL)
        c.save_wav(folder / name / (key + ".wav"), pcm)
        st = c.pcm_stats(pcm)
        heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language=lang, sess=sess)
        row = {"key": key, "line": text, "lang": lang, "ttfb_ms": round(first),
               "seconds": round(c.pcm_seconds(pcm), 2),
               "peak_dbfs": round(dbfs(st["peak"]), 1),
               "rms_dbfs": round(dbfs(st["rms"]), 1), "clipped": st["clipped"]}
        row.update(score_line(text, heard, lang))
        rows.append(row)
        print("  %-6s %4d ms  %4.1f s  pk %5.1f  rms %5.1f  cer %.3f  %s" % (
            key, row["ttfb_ms"], row["seconds"], row["peak_dbfs"], row["rms_dbfs"],
            row["cer"], heard[:60]))
    (folder / name / "audition.json").write_text(json.dumps(
        {"voice_id": voice_id, "model": MODEL, "lines": rows}, ensure_ascii=False,
        indent=2), encoding="utf-8")
    return rows


def concat(folder, name, keys, gap_s=0.8):
    """One WAV per candidate for the Fish ASR pass, lines split by silence."""
    gap = b"\x00\x00" * int(c.SAMPLE_RATE * gap_s)
    pcm = b""
    for key in keys:
        p = folder / name / (key + ".wav")
        if p.exists():
            pcm += c.load_wav(p)[0] + gap
    return c.save_wav(folder / name / "all_lines.wav", pcm)


def summarize(folder, fish=None):
    fish = fish or {}
    print("\n| candidate | whisper CER ar | fish CER ar | name ar whisper | name ar fish"
          " | name en | English kept | ch/s | peak dBFS | rms dBFS | clipped | ttfb ms |")
    print("|---|---|---|---|---|---|---|---|---|---|---|---|")
    out = []
    for name, _vid, _d in CANDIDATES:
        p = folder / name / "audition.json"
        if not p.exists():
            continue
        rows = json.loads(p.read_text(encoding="utf-8"))["lines"]
        for r in rows:   # rescored from the stored transcript, so fixes apply
            r.update(score_line(r["line"], r["heard"], r["lang"]))
        ar =[r for r in rows if r["lang"] == "ar"]
        cer_ar = sum(r["cer"] for r in ar) / len(ar)
        names_ar = [r["name_ok"] for r in ar if "name_ok" in r]
        names_en = [r["name_ok"] for r in rows if r["lang"] == "en" and "name_ok" in r]
        kept = [r["english_kept"] for r in rows if "english_kept" in r]
        k_found = sum(int(k.split("/")[0]) for k in kept)
        k_all = sum(int(k.split("/")[1]) for k in kept)
        chars = sum(len(r["line"]) for r in ar)
        secs = sum(r["seconds"] for r in ar)
        fish_cer = fish.get(name, {}).get("cer")
        ttfb = sorted(r["ttfb_ms"] for r in rows)[len(rows) // 2]
        out.append((cer_ar, name))
        fish_names = fish.get(name, {}).get("names")
        print("| %s | %.3f | %s | %d/%d | %s | %d/%d | %d/%d | %.1f | %.1f | %.1f | %d | %d |" % (
            name, cer_ar, ("%.3f" % fish_cer) if fish_cer is not None else "-",
            sum(names_ar), len(names_ar),
            ("%d/2" % fish_names) if fish_names is not None else "-",
            sum(names_en), len(names_en), k_found, k_all,
            chars / secs if secs else 0, max(r["peak_dbfs"] for r in rows),
            sum(r["rms_dbfs"] for r in rows) / len(rows),
            sum(r["clipped"] for r in rows), ttfb))
    return sorted(out)


def fish_scores(path):
    """Fish transcripts of all_lines.wav, scored against the joined script."""
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    res = {}
    ref = " ".join(t.replace(NAME_VOWELLED, NAME) for k, t, lang in LINES if lang == "ar")
    for name, heard in data.items():
        if name.startswith("_"):
            continue
        # Drop the English sentence from the transcript tail before scoring.
        cut = heard.find("Hi")
        ar_part = heard[:cut] if cut > 0 else heard
        # Fish never writes Latin inside Arabic, so the correct transliteration
        # counts as right; a different one (سباتيفاي) still counts as wrong.
        ar_part = fold_numbers(ar_part).replace("سبوتيفاي", "Spotify")
        names = at.normalize(ar_part).split().count("اوريون")
        res[name] = {"cer": at.cer(ref, ar_part), "names": names, "heard": heard}
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", action="store_true")
    ap.add_argument("--only", default=None, help="comma separated candidate names")
    ap.add_argument("--table", action="store_true", help="print the table only")
    ap.add_argument("--fish-file", default=None)
    args = ap.parse_args()

    folder = SCREEN if args.screen else OUT
    keys = SCREEN_LINES if args.screen else tuple(k for k, _, _ in LINES)
    fish = fish_scores(args.fish_file) if args.fish_file else None
    if args.table:
        summarize(folder, fish)
        return

    only = set(args.only.split(",")) if args.only else None
    sess = c.session()
    for name, vid, desc in CANDIDATES:
        if only and name not in only:
            continue
        print("\n%s  %s" % (name, desc))
        try:
            audition(name, vid, sess, keys, folder)
        except RuntimeError as e:
            print("  FAILED %s" % str(e)[:160])
            continue
        if not args.screen:
            concat(folder, name, keys)
    summarize(folder, fish)


if __name__ == "__main__":
    main()
