# Does a voice perform bracket tags at all? Same Arabic sentence, three plain
# takes and two takes per tag, for several voices. Only strong, unambiguous
# tags are used, each with the change it must cause:
#   [whispering]  quieter and less voiced     [laughing]  longer, a laugh added
#   [sighing]     longer                      [excited]   higher, wider pitch
#   [sad]         lower pitch, slower
#
#   python tools/cloud/tag_response.py unthawi mutasil v1

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c
import tag_audition as ta
import voice_audition_v2 as v

OUT = c.REPO / "logs" / "tag_response"
SENT = ta.SENT["ar"]
TAGS = ["[whispering]", "[laughing]", "[sighing]", "[excited]", "[sad]"]
V1 = "ec69015cc6f04316a1db3c83279cca0e"


def voiced_ratio(pcm, rate=c.SAMPLE_RATE):
    """Share of loud frames that are periodic. Whispering drives it down."""
    x = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
    n, hop = int(0.04 * rate), int(0.02 * rate)
    loud = voiced = 0
    for s in range(0, len(x) - n, hop):
        fr = x[s:s + n] - x[s:s + n].mean()
        if np.sqrt((fr * fr).mean()) < 0.01:
            continue
        loud += 1
        ac = np.correlate(fr, fr, "full")[n - 1:]
        if ac[0] > 0 and ac[int(rate / 400):int(rate / 90)].max() / ac[0] > 0.45:
            voiced += 1
    return voiced / loud if loud else 0.0


def feats(pcm):
    f = ta.features(pcm)
    f["voiced"] = round(voiced_ratio(pcm), 3)
    return f


def main():
    ids = {n: vid for n, vid, _ in v.CANDIDATES}
    ids["v1"] = V1
    names = sys.argv[1:] or ["unthawi", "mutasil", "emily", "v1"]
    sess = c.session()
    res = {}
    for name in names:
        def gen(text, label):
            pcm, _, _ = c.tts(text, voice_id=ids[name], sess=sess, model=ta.MODEL)
            c.save_wav(OUT / name / (label + ".wav"), pcm)
            return feats(pcm)
        plain = [gen(SENT, "plain_%d" % i) for i in (1, 2, 3)]
        pm = {k: sum(p[k] for p in plain) / 3 for k in plain[0]}
        res[name] = {"plain": plain, "tags": {}}
        print("\n%s  plain %.2f s  rms %.1f  f0 %.1f  range %.1f  voiced %.2f" % (
            name, pm["seconds"], pm["rms_db"], pm["f0_st"], pm["f0_range_st"], pm["voiced"]))
        for tag in TAGS:
            tk = [gen(tag + " " + SENT, "%s_%d" % (tag.strip("[]"), i)) for i in (1, 2)]
            d = {k: sum(t[k] for t in tk) / 2 - pm[k] for k in pm}
            res[name]["tags"][tag] = {"takes": tk, "delta": d}
            print("  %-13s dur %+5.0f%%  rms %+5.1f dB  f0 %+5.1f st  range %+5.1f st  voiced %+5.2f" % (
                tag, 100 * d["seconds"] / pm["seconds"], d["rms_db"], d["f0_st"],
                d["f0_range_st"], d["voiced"]))
    (OUT / "tag_response.json").write_text(json.dumps(res, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
