# How slow is the speech server itself, right now? Sends the same clip to the
# same model every few seconds from the PC, whose link is fast, and prints the
# time for each. Run it while the board runs asr_test: if the PC is slow at the
# same moments the board is, the time is the server's, not the chip's.
#
#   python tools/cloud/asr_server_probe.py --runs 12 --gap 3
#   python tools/cloud/asr_server_probe.py --model Qwen/Qwen3-ASR-0.6B

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

DEFAULT_CLIP = c.REPO / "firmware" / "assets" / "earcons" / "error.wav"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--clip", default=str(DEFAULT_CLIP))
    ap.add_argument("--model", default="Qwen/Qwen3-ASR-1.7B")
    ap.add_argument("--runs", type=int, default=12)
    ap.add_argument("--gap", type=float, default=3.0)
    args = ap.parse_args()

    pcm, _ = c.load_wav(args.clip)
    wav = c.pcm_to_wav(pcm)
    sess = c.session()
    times = []
    for i in range(args.runs):
        if i:
            time.sleep(args.gap)
        stamp = time.strftime("%H:%M:%S")
        try:
            text, ms = c.stt_deepinfra(wav, sess=sess, model=args.model)
        except RuntimeError as e:
            print("%s run %2d FAILED %s" % (stamp, i + 1, str(e)[:100]), flush=True)
            continue
        times.append(ms)
        print("%s run %2d %6.0f ms  %s" % (stamp, i + 1, ms, text[:40]), flush=True)
    if times:
        lo, med, p95, hi = c.percentiles(times)
        print("%s: min %.0f median %.0f p95 %.0f max %.0f ms over %d" % (
            args.model, lo, med, p95, hi, len(times)))


if __name__ == "__main__":
    main()
