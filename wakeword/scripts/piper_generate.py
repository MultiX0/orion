"""Generates wake word and negative samples with Piper.

Upstream uses rhasspy/piper-sample-generator, which is a torch checkpoint plus
torch and torchaudio. That is over a gigabyte of wheels, too much for a small
disk, so this script uses the ONNX Piper runtime instead
(pip install piper-tts) with the same multi speaker voices. en_US-libritts_r
alone carries 904 speakers, which is the variety the sample generator exists
for. Output is 16 kHz mono 16-bit WAV.

Usage:
    python scripts/piper_generate.py --voices        # download the voices
    python scripts/piper_generate.py --phrase orion --count 3000
    python scripts/piper_generate.py --phrase negative --count 3000
"""

import argparse
import io
import json
import os
import random
import sys
import urllib.request
import wave
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from scipy.signal import resample_poly

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.environ.get("ORION_WW_WORK", os.path.expanduser("~/orion_ww"))
VOICE_DIR = os.path.join(WORK, "piper_voices")
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main"

# name -> (path on hugging face, number of speakers)
VOICES = {
    "en_US-libritts_r-medium": ("en/en_US/libritts_r/medium", 904),
    "en_GB-vctk-medium": ("en/en_GB/vctk/medium", 109),
    "ar_JO-kareem-medium": ("ar/ar_JO/kareem/medium", 1),
}

# Piper has one Arabic voice, so Arabic text goes to kareem and English
# spellings cover the rest. The odd spellings push the English voices toward
# the way an Arabic speaker says it.
PHRASES = {
    "orion": {
        "en": [
            "Orion", "orion", "Oh-rye-on", "Ohryon", "Oriyon", "Orrion",
            "Oryon", "Or-yon", "Oh ree on", "Ooryon",
        ],
        "ar": ["أوريون", "اوريون", "أُوريون", "أوريون."],
    },
    "hey_orion": {
        "en": [
            "Hey Orion", "Hey, Orion", "hey orion", "Hey Oh-rye-on",
            "Hey Oriyon", "Hi Orion", "Hey Or-yon", "Hey Ohryon",
        ],
        "ar": ["يا أوريون", "هاي أوريون", "يا اوريون", "هيه أوريون"],
    },
}

CONFUSABLE_EN = [
    "orange", "origin", "original", "Oreo", "Ryan", "O'Brien", "onion",
    "or on", "hey Siri", "Alexa", "okay Google", "oriental", "aurion",
    "hey Ryan", "oh really", "ocean", "opinion", "Orlando", "Ontario",
    "oregano", "Oregon", "iron", "irony", "arrive on", "carry on", "rely on",
    "Orion's belt", "million", "billion", "union", "opera", "aurora",
]

CONFUSABLE_AR = [
    "أوريو", "أوركيد", "أوراق", "أوروبا", "أوريجانو", "يا ريان", "يا أريج",
    "أوقيانوس", "عريون", "أرجوان", "يا رامون", "هاي سيري", "أليكسا",
    "أوكي جوجل", "يا أنطون", "أوريجن", "يا ريّس", "مليون", "بليون", "زيتون",
    "عيون", "يا رفيق", "أورانيوم", "يا ريم",
]

# Short everyday sentences, the kind of thing said in a room with the board in
# it. These are the bulk of the generated negatives.
FILLER_EN = [
    "what time is it", "turn on the lights please", "play some music",
    "the weather today is nice", "can you hear me", "I will be back later",
    "open the window", "send him a message", "how much does it cost",
    "we are going out tonight", "call my brother", "set a timer for ten minutes",
    "this code does not compile", "the build failed again", "where is my phone",
    "pass me the remote", "did you see that", "let me think about it",
    "no thank you", "that is very funny", "start the video", "stop the music",
    "I am working on the project", "the meeting is at five",
]

FILLER_AR = [
    "شو الأخبار", "كيفك اليوم", "شغل الأغاني", "الجو حلو اليوم",
    "بتسمعني منيح", "رح ارجع بعدين", "افتح الشباك", "ابعتله رسالة",
    "قديش سعرها", "رايحين نطلع الليلة", "اتصل بأخوي", "حط تايمر عشر دقايق",
    "في مشكلة بالكود", "البيلد وقع كمان مرة", "وين تلفوني", "ناولني الريموت",
    "شفت هاد", "خليني افكر شوي", "لا شكرا", "هاد بضحك",
    "شغل الفيديو", "وقف الأغنية", "انا شغال عالمشروع", "الاجتماع الساعة خمسة",
]


def download_voices():
    os.makedirs(VOICE_DIR, exist_ok=True)
    for name, (path, _) in VOICES.items():
        for suffix in (".onnx", ".onnx.json"):
            out = os.path.join(VOICE_DIR, name + suffix)
            if os.path.exists(out) and os.path.getsize(out) > 1000:
                continue
            url = "%s/%s/%s%s" % (HF, path, name, suffix)
            print("downloading", name + suffix, flush=True)
            urllib.request.urlretrieve(url, out)
    print("voices in", VOICE_DIR)


def to_16k(raw, rate, width, channels):
    data = np.frombuffer(raw, dtype=np.int16).astype(np.float32)
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    if rate != 16000:
        # 22050 -> 16000 is exactly 320/441, other rates fall back to a ratio.
        if rate == 22050:
            data = resample_poly(data, 320, 441)
        else:
            data = resample_poly(data, 16000, rate)
    return np.clip(data, -32768, 32767).astype(np.int16)


def render(args):
    voice_name, jobs, out_dir = args
    from piper import PiperVoice, SynthesisConfig

    voice = PiperVoice.load(os.path.join(VOICE_DIR, voice_name + ".onnx"))
    written = 0
    for job in jobs:
        path = os.path.join(out_dir, job["name"])
        if os.path.exists(path):
            continue
        syn = SynthesisConfig(
            speaker_id=job["speaker"],
            length_scale=job["length_scale"],
            noise_scale=job["noise_scale"],
            noise_w_scale=job["noise_w"],
            volume=job["volume"],
            normalize_audio=False,
        )
        buf = io.BytesIO()
        with wave.open(buf, "wb") as wf:
            voice.synthesize_wav(job["text"], wf, syn_config=syn)
        buf.seek(0)
        with wave.open(buf, "rb") as wf:
            rate = wf.getframerate()
            width = wf.getsampwidth()
            channels = wf.getnchannels()
            raw = wf.readframes(wf.getnframes())
        samples = to_16k(raw, rate, width, channels)
        if samples.size < 1600:
            continue
        with wave.open(path, "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(16000)
            out.writeframes(samples.tobytes())
        written += 1
    return voice_name, written


def texts_for(kind, rng):
    if kind == "negative":
        pool = [
            ("en", CONFUSABLE_EN, 0.35),
            ("ar", CONFUSABLE_AR, 0.25),
            ("en", FILLER_EN, 0.2),
            ("ar", FILLER_AR, 0.2),
        ]
        roll = rng.random()
        acc = 0.0
        for lang, items, weight in pool:
            acc += weight
            if roll <= acc:
                return lang, rng.choice(items)
        return "en", rng.choice(CONFUSABLE_EN)
    lang = "ar" if rng.random() < 0.35 else "en"
    return lang, rng.choice(PHRASES[kind][lang])


def build_jobs(kind, count, seed):
    rng = random.Random(seed)
    per_voice = {name: [] for name in VOICES}
    for i in range(count):
        lang, text = texts_for(kind, rng)
        if lang == "ar":
            voice_name = "ar_JO-kareem-medium"
        else:
            voice_name = rng.choice(["en_US-libritts_r-medium", "en_GB-vctk-medium"])
        speakers = VOICES[voice_name][1]
        per_voice[voice_name].append(
            {
                "name": "%06d.wav" % i,
                "text": text,
                "speaker": rng.randrange(speakers) if speakers > 1 else None,
                "length_scale": round(rng.uniform(0.75, 1.35), 3),
                "noise_scale": round(rng.uniform(0.45, 0.85), 3),
                "noise_w": round(rng.uniform(0.5, 1.0), 3),
                "volume": round(rng.uniform(0.6, 1.0), 2),
            }
        )
    return per_voice


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--voices", action="store_true", help="download voices and exit")
    parser.add_argument("--phrase", help="orion, hey_orion or negative")
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=5)
    parser.add_argument("--workers", type=int, default=3)
    args = parser.parse_args()

    if args.voices:
        download_voices()
        return

    out_dir = os.path.join(HERE, "data", "piper", args.phrase)
    os.makedirs(out_dir, exist_ok=True)
    per_voice = build_jobs(args.phrase, args.count, args.seed)
    print({k: len(v) for k, v in per_voice.items()}, flush=True)

    tasks = []
    for voice_name, jobs in per_voice.items():
        if not jobs:
            continue
        chunk = max(1, len(jobs) // args.workers + 1)
        for start in range(0, len(jobs), chunk):
            tasks.append((voice_name, jobs[start : start + chunk], out_dir))

    total = 0
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        for voice_name, written in pool.map(render, tasks):
            total += written
            print(voice_name, "wrote", written, flush=True)
    print("phrase=%s written=%d dir=%s" % (args.phrase, total, out_dir))


if __name__ == "__main__":
    main()
