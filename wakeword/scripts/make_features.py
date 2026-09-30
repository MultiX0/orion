"""Turns generated WAV clips into microWakeWord spectrogram features.

Runs the upstream augmentation chain (room impulse responses, background noise,
EQ, distortion, pitch shift, gain) and writes ragged mmap folders that
microwakeword.data can sample from.

Raw audio stays on the Windows drive, features go to the WSL side, and the
caller can delete the raw audio afterwards. Disk is the constraint here, so
augmentation_duration_s is 2.4 s rather than upstream's 3.2 s. It cannot go
lower: with clip_duration_ms 1500, a stride of 3 and this MixedNet, the trainer
asks for 204 feature windows, and slide_frames=10 costs another 9, so a
spectrogram has to be at least 2.15 s long. 2.4 s leaves a little room.

Usage:
    python scripts/make_features.py --name orion_positive --dirs data/fish/orion data/piper/orion --truth
    python scripts/make_features.py --name adversarial --dirs data/piper/negative data/fish/confusable
    python scripts/make_features.py --name music --dirs work/fma_16k --split-seconds 10
"""

import argparse
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))


def build(args):
    from mmap_ninja.ragged import RaggedMmap
    from microwakeword.audio.augmentation import Augmentation
    from microwakeword.audio.clips import Clips
    from microwakeword.audio.spectrograms import SpectrogramGeneration

    out_root = os.path.join(WORK, "features", args.name)
    if args.force and os.path.isdir(out_root):
        shutil.rmtree(out_root)

    # Clips only takes one directory, so the sources are symlinked into one.
    pooled = os.path.join(WORK, "pooled", args.name)
    os.makedirs(pooled, exist_ok=True)
    count = 0
    for source in args.dirs:
        source = source if os.path.isabs(source) else os.path.join(HERE, source)
        if not os.path.isdir(source):
            print("missing source, skipped:", source)
            continue
        tag = os.path.basename(os.path.dirname(source)) + "_" + os.path.basename(source)
        for entry in sorted(os.listdir(source)):
            if not entry.endswith(".wav"):
                continue
            link = os.path.join(pooled, tag + "_" + entry)
            if not os.path.exists(link):
                os.symlink(os.path.join(source, entry), link)
            count += 1
    print("pooled clips:", count, flush=True)
    if count == 0:
        raise SystemExit("no clips found")

    clips = Clips(
        input_directory=pooled,
        file_pattern="*.wav",
        max_clip_duration_s=None,
        remove_silence=False,
        random_split_seed=10,
        split_count=0.1,
    )

    backgrounds = [p for p in (os.path.join(WORK, "fma_16k"),) if os.path.isdir(p)]
    impulses = [p for p in (os.path.join(WORK, "mit_rirs"),) if os.path.isdir(p)]
    augmenter = Augmentation(
        augmentation_duration_s=args.duration,
        augmentation_probabilities={
            "SevenBandParametricEQ": 0.25,
            "TanhDistortion": 0.25,
            "PitchShift": 0.25,
            "BandStopFilter": 0.25,
            "AddColorNoise": 0.25,
            "AddBackgroundNoise": 0.75,
            "Gain": 1.0,
            "RIR": 0.5,
        },
        impulse_paths=impulses,
        background_paths=backgrounds,
        background_min_snr_db=-5,
        background_max_snr_db=10,
        min_jitter_s=0.195,
        max_jitter_s=0.205,
    )
    print("impulses:", impulses, "backgrounds:", backgrounds, flush=True)

    plan = [
        ("training", "train", args.repeat, args.slide),
        ("validation", "validation", 1, args.slide),
        ("testing", "test", 1, 1),
    ]
    for split_dir, split_name, repeat, slide in plan:
        out_dir = os.path.join(out_root, split_dir)
        target = os.path.join(out_dir, args.name + "_mmap")
        if os.path.isdir(target):
            print("exists, skipped:", target)
            continue
        os.makedirs(out_dir, exist_ok=True)
        if args.split_seconds:
            spectrograms = SpectrogramGeneration(
                clips=clips,
                augmenter=augmenter,
                step_ms=10,
                split_spectrogram_duration_s=args.split_seconds,
            )
        else:
            spectrograms = SpectrogramGeneration(
                clips=clips, augmenter=augmenter, step_ms=10, slide_frames=slide
            )
        started = time.time()
        RaggedMmap.from_generator(
            out_dir=target,
            sample_generator=spectrograms.spectrogram_generator(
                split=split_name, repeat=repeat
            ),
            batch_size=100,
            verbose=False,
        )
        size = sum(
            os.path.getsize(os.path.join(target, f)) for f in os.listdir(target)
        )
        print(
            "%s: %.0f s, %.0f MB" % (split_dir, time.time() - started, size / 1e6),
            flush=True,
        )

    shutil.rmtree(pooled, ignore_errors=True)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--dirs", nargs="+", required=True)
    parser.add_argument("--truth", action="store_true", help="kept for the caller's notes")
    parser.add_argument("--duration", type=float, default=2.4)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--slide", type=int, default=10)
    parser.add_argument("--split-seconds", type=float, default=None)
    parser.add_argument("--force", action="store_true")
    build(parser.parse_args())


if __name__ == "__main__":
    main()
