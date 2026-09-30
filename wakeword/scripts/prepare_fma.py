"""Turns the Free Music Archive zip into 16 kHz mono WAV background clips.

Upstream converts the whole set and also pulls a slice of AudioSet. Both are
too big for this machine, so this takes a capped number of tracks, keeps ten
seconds of each, and deletes the zip when it is done. The result is used twice:
as the background noise the augmenter mixes into every clip, and as the
no_speech negative feature set.

Usage:
    python scripts/prepare_fma.py --tracks 700 --seconds 10
"""

import argparse
import io
import os
import random
import sys
import wave
import zipfile

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", default=os.path.join(WORK, "fma_xs.zip"))
    parser.add_argument("--out", default=os.path.join(WORK, "fma_16k"))
    parser.add_argument("--tracks", type=int, default=700)
    parser.add_argument("--seconds", type=float, default=10.0)
    parser.add_argument("--seed", type=int, default=3)
    parser.add_argument("--keep-zip", action="store_true")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    archive = zipfile.ZipFile(args.zip)
    names = [n for n in archive.namelist() if n.lower().endswith((".mp3", ".wav", ".flac"))]
    print("tracks in zip:", len(names))
    random.Random(args.seed).shuffle(names)

    written = 0
    failed = 0
    for name in names:
        if written >= args.tracks:
            break
        out_path = os.path.join(args.out, "fma_%05d.wav" % written)
        if os.path.exists(out_path):
            written += 1
            continue
        try:
            raw = archive.read(name)
            data, rate = sf.read(io.BytesIO(raw), dtype="float32", always_2d=True)
        except Exception:
            failed += 1
            continue
        mono = data.mean(axis=1)
        if rate != 16000:
            from math import gcd

            g = gcd(int(rate), 16000)
            mono = resample_poly(mono, 16000 // g, int(rate) // g)
        want = int(args.seconds * 16000)
        if mono.size < want // 2:
            failed += 1
            continue
        if mono.size > want:
            start = (mono.size - want) // 2
            mono = mono[start : start + want]
        samples = np.clip(mono * 32767, -32768, 32767).astype(np.int16)
        with wave.open(out_path, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(16000)
            out.writeframes(samples.tobytes())
        written += 1
        if written % 100 == 0:
            print(" ", written, "written", flush=True)

    archive.close()
    if not args.keep_zip and os.path.exists(args.zip):
        os.remove(args.zip)
        print("deleted", args.zip)
    total_mb = sum(
        os.path.getsize(os.path.join(args.out, f)) for f in os.listdir(args.out)
    ) / 1e6
    print("written %d, failed %d, %.0f MB in %s" % (written, failed, total_mb, args.out))


if __name__ == "__main__":
    main()
