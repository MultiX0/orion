"""Builds quiet, low SNR clips for the room problems: soft speech and faint
non-speech sounds that must not wake the board, and soft "Orion" that must.

The board's frontend normalises level (PCAN), so what separates a quiet word
from a loud one is the mic noise floor under it: signal to noise ratio, not
absolute gain. Every clip here is speech or a synthetic sound scaled to a
target SNR over a fixed floor of white, pink or brown noise at a rms the
board mic shows (8 to 25 on int16), with a lead of floor alone so the
frontend has settled before the sound starts.

Usage:
    python scripts/make_quiet.py --src data/fish/negative --out data/quiet/neg_speech \
        --snr -3 12 --lead 0.4 --max 1500 --seed 1
    python scripts/make_quiet.py --synth 800 --out data/quiet/neg_sounds --snr 0 15 --seed 2
"""

import argparse
import os
import random
import wave

import numpy as np

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 16000


def read(path):
    with wave.open(path, "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != SR:
            return None
        return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)


def write(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(np.clip(np.round(x), -32768, 32767).astype(np.int16).tobytes())


def colored(n, rng, kind):
    white = rng.standard_normal(n)
    if kind == "white":
        return white
    spec = np.fft.rfft(white)
    f = np.arange(spec.size) + 1.0
    spec = spec / (np.sqrt(f) if kind == "pink" else f)
    x = np.fft.irfft(spec, n)
    return x / (x.std() + 1e-9)


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)) + 1e-9)


def active_rms(x):
    # rms of the loudest 100 ms frames, so leading silence does not bias it
    frames = x[: x.size // 1600 * 1600].reshape(-1, 1600)
    if frames.size == 0:
        return rms(x)
    e = np.sqrt((frames ** 2).mean(axis=1))
    return float(np.sort(e)[-max(1, e.size // 3):].mean() + 1e-9)


def synth_sound(rng, seconds):
    n = int(seconds * SR)
    x = np.zeros(n)
    t = np.arange(n) / SR
    kind = rng.choice(["click", "knock", "rustle", "hum", "beep", "breath", "mixed"])
    kinds = [kind] if kind != "mixed" else list(rng.choice(["click", "knock", "rustle", "beep"], 2))
    for k in kinds:
        if k == "click":
            for _ in range(rng.integers(1, 7)):
                s = rng.integers(0, n - 800)
                length = rng.integers(80, 800)
                x[s:s + length] += rng.standard_normal(length) * np.exp(-np.arange(length) / (length / 5))
        elif k == "knock":
            for _ in range(rng.integers(1, 5)):
                s = rng.integers(0, n - 4000)
                f0 = rng.uniform(70, 350)
                tt = np.arange(4000) / SR
                x[s:s + 4000] += np.sin(2 * np.pi * f0 * tt) * np.exp(-tt * rng.uniform(20, 60))
        elif k == "rustle":
            for _ in range(rng.integers(1, 4)):
                length = min(n - 1, int(rng.uniform(0.1, 0.7) * SR))
                s = rng.integers(0, max(1, n - length))
                b = colored(length, rng, rng.choice(["white", "pink"]))
                x[s:s + length] += b * np.hanning(length)
        elif k == "hum":
            f0 = rng.choice([50, 60, 100, 120, rng.uniform(80, 400)])
            for h in range(1, 5):
                x += np.sin(2 * np.pi * f0 * h * t + rng.uniform(0, 6)) / h
        elif k == "beep":
            for _ in range(rng.integers(1, 4)):
                length = min(n - 1, int(rng.uniform(0.05, 0.4) * SR))
                s = rng.integers(0, max(1, n - length))
                f0 = rng.uniform(400, 3500)
                x[s:s + length] += np.sin(2 * np.pi * f0 * np.arange(length) / SR)
        elif k == "breath":
            length = min(n - 1, int(rng.uniform(0.3, 1.0) * SR))
            s = rng.integers(0, max(1, n - length))
            b = np.diff(colored(length + 1, rng, "white"))
            x[s:s + length] += b * np.hanning(length)
    return x


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--src", nargs="*", default=[])
    p.add_argument("--synth", type=int, default=0)
    p.add_argument("--out", required=True)
    p.add_argument("--snr", type=float, nargs=2, default=[0, 12])
    p.add_argument("--floor", type=float, nargs=2, default=[8, 25])
    p.add_argument("--lead", type=float, default=0.4)
    p.add_argument("--tail", type=float, default=0.0)
    p.add_argument("--max", type=int, default=0)
    p.add_argument("--copies", type=int, default=1)
    p.add_argument("--seed", type=int, default=1)
    args = p.parse_args()

    rng = np.random.default_rng(args.seed)
    out = args.out if os.path.isabs(args.out) else os.path.join(HERE, args.out)
    os.makedirs(out, exist_ok=True)
    items = []
    for d in args.src:
        d = d if os.path.isabs(d) else os.path.join(HERE, d)
        items += [os.path.join(d, f) for f in sorted(os.listdir(d)) if f.endswith(".wav")]
    random.Random(args.seed).shuffle(items)
    if args.max:
        items = items[: args.max]
    made = 0
    for c in range(args.copies):
        for i, path in enumerate(items):
            x = read(path)
            if x is None or x.size < 1600:
                continue
            made += mix(x, rng, args, os.path.join(out, "q%d_%s" % (c, os.path.basename(path))))
    for i in range(args.synth):
        x = synth_sound(rng, rng.uniform(0.8, 2.0))
        made += mix(x, rng, args, os.path.join(out, "s%05d.wav" % i))
    print("wrote", made, "clips to", out)


def mix(x, rng, args, path):
    floor_rms = rng.uniform(*args.floor)
    snr = rng.uniform(*args.snr)
    x = x * (floor_rms * 10 ** (snr / 20) / active_rms(x))
    lead = int(args.lead * SR)
    tail = int(args.tail * SR)
    y = np.concatenate([np.zeros(lead), x, np.zeros(tail)])
    noise = colored(y.size, rng, rng.choice(["white", "pink", "pink", "brown"]))
    y = y + noise * floor_rms
    write(path, y)
    return 1


if __name__ == "__main__":
    main()
