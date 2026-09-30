# Tiebreak for the second audition: the two leading voices on lines shaped
# like what Orion actually says, heavier on English tech words, two takes each
# so take to take variance shows up as well as the mean.
#
#   python tools/cloud/voice_tiebreak_v2.py mutasil unthawi

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c
import voice_audition_v2 as v

OUT = c.REPO / "voice" / "auditions_v2" / "tiebreak"

LINES = [
    ("ar", "تمام، شغّلتُ لك الموسيقى على YouTube."),
    ("ar", "الـ Wi-Fi متصل الآن، والإشارة قوية."),
    ("ar", "أرسلتُ الـ email إلى سارة قبل دقيقتين."),
    ("ar", "لستُ متأكدة من ذلك، لكن يمكنني البحث عنه."),
    ("ar", "لا يوجد اتصال بالإنترنت حالياً."),
    ("ar", "أنا أُورْيُون، مساعدتك المنزلية. أعمل على لوحة صغيرة بشاشة وكاميرا."),
    ("en", "Sure, Bluetooth is on and your headphones are connected."),
    ("en", "I can't check the weather right now, but I can set a reminder."),
]


def main():
    names = sys.argv[1:] or ["mutasil", "unthawi"]
    ids = {n: vid for n, vid, _ in v.CANDIDATES}
    sess = c.session()
    summary = {}
    for name in names:
        rows = []
        for i, (lang, text) in enumerate(LINES, 1):
            for take in (1, 2):
                pcm, first, _ = c.tts(text, voice_id=ids[name], sess=sess, model=v.MODEL)
                c.save_wav(OUT / name / ("t%d_take%d.wav" % (i, take)), pcm)
                heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language=lang, sess=sess)
                st = c.pcm_stats(pcm)
                row = {"line": text, "lang": lang, "take": take, "ttfb_ms": round(first),
                       "seconds": round(c.pcm_seconds(pcm), 2),
                       "peak_dbfs": round(v.dbfs(st["peak"]), 1),
                       "rms_dbfs": round(v.dbfs(st["rms"]), 1), "clipped": st["clipped"]}
                row.update(v.score_line(text, heard, lang))
                rows.append(row)
                print("%-8s t%d/%d cer %.3f pk %5.1f rms %5.1f  %s" % (
                    name, i, take, row["cer"], row["peak_dbfs"], row["rms_dbfs"], heard[:60]))
        (OUT / name / "tiebreak.json").write_text(json.dumps(rows, ensure_ascii=False,
                                                             indent=2), encoding="utf-8")
        summary[name] = rows

    print("\n| voice | mean CER all | mean CER ar | mean CER en | English words kept | name ok"
          " | worst peak dBFS | mean rms dBFS | clipped |")
    print("|---|---|---|---|---|---|---|---|---|")
    for name, rows in summary.items():
        ar = [r["cer"] for r in rows if r["lang"] == "ar"]
        en = [r["cer"] for r in rows if r["lang"] == "en"]
        kept = [r["english_kept"] for r in rows if "english_kept" in r and r["lang"] == "ar"]
        kf = sum(int(k.split("/")[0]) for k in kept)
        ka = sum(int(k.split("/")[1]) for k in kept)
        nm = [r["name_ok"] for r in rows if "name_ok" in r]
        print("| %s | %.3f | %.3f | %.3f | %d/%d | %d/%d | %.1f | %.1f | %d |" % (
            name, sum(r["cer"] for r in rows) / len(rows), sum(ar) / len(ar),
            sum(en) / len(en), kf, ka, sum(nm), len(nm),
            max(r["peak_dbfs"] for r in rows),
            sum(r["rms_dbfs"] for r in rows) / len(rows), sum(r["clipped"] for r in rows)))


if __name__ == "__main__":
    main()
