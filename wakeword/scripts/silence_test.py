"""Counts detections on audio that contains no speech at all.

The failure this looks for is wakes in complete silence and on room noise.
This feeds each model long stretches of synthetic audio through the same
frontend the board uses (pymicro-features via microwakeword.inference.Model)
and counts every detection at each cutoff, with the same 5 window average
and 25 slice cooldown the trainer's false accept measure uses:

  digital silence   all zeros
  white noise       flat spectrum at a few levels, rms 3, 30 and 300 of 32767
                    (about -81, -61 and -41 dBFS)
  pink noise        1/f, the shape of fans and air, rms 30 and 300
  hum               50 Hz with harmonics plus a little white noise, rms 100

Optionally also runs unseen spectrogram sets (a RaggedMmap folder the model
never trained on, such as a prefix of fsd50k_no_speech that was fetched
separately) and reports detections per hour there.

Usage:
    python scripts/silence_test.py --models work/scout_orion_ft/orion_ft_step500.tflite \
        work/scout_orion_ft4/orion_ft4_step2000.tflite --minutes 10 \
        --mmap ~/orion_ww/negative_datasets/unseen/fsd50k_no_speech_mmap
"""

import argparse
import os
import sys

os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np  # noqa: E402

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RATE = 16000
WINDOW = 5
COOLDOWN = 25
STRIDE = 3
STEP_S = 0.01


def pink(n, rng):
    white = rng.standard_normal(n)
    spectrum = np.fft.rfft(white)
    freqs = np.arange(len(spectrum)) + 1.0
    spectrum /= np.sqrt(freqs)
    return np.fft.irfft(spectrum, n)


def scaled(signal, rms):
    signal = signal - signal.mean()
    current = np.sqrt((signal ** 2).mean()) or 1.0
    return np.clip(signal * (rms / current), -32767, 32767).astype(np.int16)


def make_signals(seconds, rng):
    n = seconds * RATE
    t = np.arange(n) / RATE
    hum = sum(np.sin(2 * np.pi * 50 * k * t) / k for k in (1, 2, 3, 5)) + 0.2 * rng.standard_normal(n)
    return [
        ("silence", np.zeros(n, dtype=np.int16)),
        ("white rms 3", scaled(rng.standard_normal(n), 3)),
        ("white rms 30", scaled(rng.standard_normal(n), 30)),
        ("white rms 300", scaled(rng.standard_normal(n), 300)),
        ("pink rms 30", scaled(pink(n, rng), 30)),
        ("pink rms 300", scaled(pink(n, rng), 300)),
        ("hum rms 100", scaled(hum, 100)),
    ]


def count_detections(probabilities, cutoffs):
    from numpy.lib.stride_tricks import sliding_window_view

    if len(probabilities) < WINDOW:
        return np.zeros(len(cutoffs), dtype=int), 0.0
    averaged = sliding_window_view(np.asarray(probabilities), WINDOW).mean(axis=-1)
    counts = np.zeros(len(cutoffs), dtype=int)
    cooldown = np.zeros(len(cutoffs), dtype=int)
    for p in averaged:
        cooldown = np.maximum(cooldown - 1, 0)
        fired = (p > cutoffs) & (cooldown == 0)
        counts += fired
        cooldown[fired] = COOLDOWN
    hours = len(probabilities) * STRIDE * STEP_S / 3600
    return counts, hours


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--models", nargs="+", required=True)
    parser.add_argument("--minutes", type=int, default=10)
    parser.add_argument("--cutoffs", default="0.88,0.95,0.98")
    parser.add_argument("--mmap", nargs="*", default=[], help="unseen RaggedMmap spectrogram folders")
    parser.add_argument("--mmap-limit", type=int, default=2000, help="entries per folder")
    args = parser.parse_args()

    from microwakeword.inference import Model

    cutoffs = np.array([float(c) for c in args.cutoffs.split(",")])
    rng = np.random.default_rng(3)
    signals = make_signals(args.minutes * 60, rng)

    print("detections in %d minutes of each signal, cutoffs %s" % (args.minutes, args.cutoffs))
    header = "%-28s %-16s " % ("model", "signal") + " ".join("%8.2f" % c for c in cutoffs) + "   max prob"
    print(header)
    for path in args.models:
        full = path if os.path.isabs(path) else os.path.join(HERE, path)
        model = Model(full, stride=STRIDE)
        name = os.path.basename(path).replace(".tflite", "")
        for label, samples in signals:
            probabilities = np.array(model.predict_clip(samples, step_ms=10))
            counts, _ = count_detections(probabilities, cutoffs)
            print("%-28s %-16s " % (name, label) + " ".join("%8d" % c for c in counts)
                  + "   %.3f" % probabilities.max(), flush=True)
        for folder in args.mmap:
            from mmap_ninja.ragged import RaggedMmap

            folder = os.path.expanduser(folder)
            data = RaggedMmap(folder)
            total = np.zeros(len(cutoffs), dtype=int)
            hours = 0.0
            for i in range(min(len(data), args.mmap_limit)):
                probabilities = model.predict_spectrogram(np.array(data[i]))
                counts, h = count_detections(probabilities, cutoffs)
                total += counts
                hours += h
            print("%-28s %-16s " % (name, os.path.basename(folder)[:16])
                  + " ".join("%8.2f" % (c / hours) for c in total)
                  + "   per hour over %.2f h" % hours, flush=True)


if __name__ == "__main__":
    main()
