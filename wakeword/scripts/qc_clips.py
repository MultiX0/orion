"""Trims and filters generated clips before they become features.

A TTS engine asked for one word sometimes answers with silence, a click, or a
long pause before it starts. Feeding those to the trainer teaches the model
nothing and hurts the positive set, so every clip is trimmed to the speech it
contains and rejected if what is left is too short, too long, or too quiet.

Rewrites the clips in place and prints what it threw away.

Usage:
    python scripts/qc_clips.py --dirs data/fish/orion data/piper/orion
    python scripts/qc_clips.py --dirs data/fish/orion --dry-run
"""

import argparse
import os
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PAD_S = 0.08
FRAME = 320  # 20 ms at 16 kHz


def read_wav(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != 16000:
            return None
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16)


def write_wav(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(16000)
        w.writeframes(samples.astype(np.int16).tobytes())


def trim(samples):
    if samples.size < FRAME:
        return None
    frames = samples[: samples.size // FRAME * FRAME].reshape(-1, FRAME)
    rms = np.sqrt((frames.astype(np.float64) ** 2).mean(axis=1))
    peak = rms.max()
    if peak < 200:
        return None
    # Speech is anything within 20 dB of the loudest frame, floored well above
    # the noise a TTS engine leaves between words.
    threshold = max(peak * 0.1, 80.0)
    loud = np.where(rms > threshold)[0]
    if loud.size == 0:
        return None
    pad = int(PAD_S * 16000)
    start = max(0, loud[0] * FRAME - pad)
    end = min(samples.size, (loud[-1] + 1) * FRAME + pad)
    return samples[start:end]


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--dirs", nargs="+", required=True)
    parser.add_argument("--min-seconds", type=float, default=0.22)
    parser.add_argument("--max-seconds", type=float, default=2.2)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    for directory in args.dirs:
        path = directory if os.path.isabs(directory) else os.path.join(HERE, directory)
        if not os.path.isdir(path):
            print("missing:", path)
            continue
        kept = 0
        dropped = 0
        durations = []
        for entry in sorted(os.listdir(path)):
            if not entry.endswith(".wav"):
                continue
            full = os.path.join(path, entry)
            samples = read_wav(full)
            trimmed = trim(samples) if samples is not None else None
            seconds = trimmed.size / 16000 if trimmed is not None else 0.0
            if trimmed is None or not (args.min_seconds <= seconds <= args.max_seconds):
                dropped += 1
                if not args.dry_run:
                    os.remove(full)
                continue
            if not args.dry_run:
                write_wav(full, trimmed)
            durations.append(seconds)
            kept += 1
        durations = np.array(durations) if durations else np.zeros(1)
        print(
            "%-28s kept %5d dropped %4d  duration mean %.2f s, p05 %.2f, p95 %.2f"
            % (
                os.path.relpath(path, HERE),
                kept,
                dropped,
                durations.mean(),
                np.percentile(durations, 5),
                np.percentile(durations, 95),
            )
        )


if __name__ == "__main__":
    main()
