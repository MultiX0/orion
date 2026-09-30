# Does a second ASR request escape when the first one stalls?
#
# The board's ASR time is erratic because DeepInfra's speech endpoint sometimes
# takes 4 to 11 s to answer a request it usually answers in under one. A hedged
# request only helps if those stalls hit requests independently. So this sends
# pairs at the same instant, same clip, and counts how often one of the pair is
# slow while the other is fast.
#
#   python tools/cloud/asr_hedge_probe.py --pairs 20
#   python tools/cloud/asr_hedge_probe.py --b Qwen/Qwen3-ASR-0.6B

import argparse
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

CLIP = c.REPO / "firmware" / "assets" / "earcons" / "error.wav"
SLOW_MS = 2500


def one(wav, model, out, key):
    try:
        _, ms = c.stt_deepinfra(wav, sess=c.session(), model=model)
        out[key] = ms
    except RuntimeError:
        out[key] = None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", default="Qwen/Qwen3-ASR-1.7B")
    ap.add_argument("--b", default="Qwen/Qwen3-ASR-1.7B")
    ap.add_argument("--pairs", type=int, default=20)
    ap.add_argument("--gap", type=float, default=2.0)
    args = ap.parse_args()

    pcm, _ = c.load_wav(CLIP)
    wav = c.pcm_to_wav(pcm)
    both_slow = one_slow = none_slow = 0
    best = []
    for i in range(args.pairs):
        if i:
            time.sleep(args.gap)
        out = {}
        ts = [threading.Thread(target=one, args=(wav, args.a, out, "a")),
              threading.Thread(target=one, args=(wav, args.b, out, "b"))]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        a, b = out.get("a"), out.get("b")
        slow = [x is None or x > SLOW_MS for x in (a, b)]
        both_slow += all(slow)
        one_slow += (any(slow) and not all(slow))
        none_slow += not any(slow)
        best.append(min(x for x in (a, b) if x is not None) if (a or b) else 99999)
        print("pair %2d  a %6s  b %6s%s" % (
            i + 1, "%.0f" % a if a else "fail", "%.0f" % b if b else "fail",
            "   <- one escaped" if any(slow) and not all(slow) else
            ("   <- both slow" if all(slow) else "")), flush=True)
    lo, med, p95, hi = c.percentiles(best)
    print("\na=%s b=%s: %d pairs, both slow %d, one slow %d, neither %d" % (
        args.a, args.b, args.pairs, both_slow, one_slow, none_slow))
    print("faster of the pair: median %.0f, p95 %.0f, max %.0f ms" % (med, p95, hi))


if __name__ == "__main__":
    main()
