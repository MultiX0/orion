"""Generates wake word samples with the Fish Audio TTS API.

Many voices, both Arabic and English, with varied speed, volume and sampling
temperature. Output is 16 kHz mono 16-bit WAV, which is what microWakeWord and
the board both want, so no conversion step is needed.

Reads FISH_API_KEY from .env at the repo root. The key is never printed.
Every request is logged to work/fish_log.jsonl with its character count.

Usage:
    python scripts/fish_generate.py --phrase orion --count 1100
    python scripts/fish_generate.py --phrase hey_orion --count 700
    python scripts/fish_generate.py --phrase orion --count 4 --smoke
"""

import argparse
import json
import os
import queue
import random
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(HERE)
API = "https://api.fish.audio/v1/tts"
# s2.1-pro-free is the free developer tier: it needs no API credit, where the
# paid models answer 402 without it, and it works with public voice ids.
TTS_MODEL = "s2.1-pro-free"

# Text variants per phrase. Arabic first, it is the main audience.
VARIANTS = {
    "orion": {
        "ar": ["أوريون", "أوريون؟", "أوريون!", "أوريون.", "أُوريون", "اوريون"],
        "en": ["Orion", "Orion?", "Orion!", "Orion.", "Oh-ryan", "O-rion"],
    },
    "hey_orion": {
        "ar": [
            "يا أوريون",
            "يا أوريون!",
            "هاي أوريون",
            "هيه أوريون",
            "يا اوريون؟",
            "يلا يا أوريون",
        ],
        "en": [
            "Hey Orion",
            "Hey Orion!",
            "Hey, Orion.",
            "Hey Orion?",
            "Hi Orion",
            "Hey Oh-ryan",
        ],
    },
}

# Negative phrases that sound close to the wake word. Same pipeline, same
# voices, so the model cannot cheat by learning the TTS engine.
CONFUSABLES = {
    "ar": [
        "أوريو",
        "أوركيد",
        "أوراق",
        "أوروبا",
        "أوريجانو",
        "يا ريان",
        "يا أريج",
        "أوقيانوس",
        "عريون",
        "أرجوان",
        "يا رامون",
        "هاي سيري",
        "أليكسا",
        "أوكي جوجل",
        "يا أنطون",
        "بصليون",
        "أوريجن",
        "يا ريّس",
    ],
    "en": [
        "orange",
        "origin",
        "Oreo",
        "Ryan",
        "O'Brien",
        "onion",
        "or on",
        "hey Siri",
        "Alexa",
        "okay Google",
        "oriental",
        "aurion",
        "hey Ryan",
        "oh really",
        "ocean",
        "opinion",
        "Orlando",
        "hey Google",
    ],
}


# Ordinary short words and phrases in the same voices. The first model learned
# "a Fish voice saying one short word" as the wake word because the Fish
# negatives were few and all confusables, so this set is broad, not close.
NEGATIVES = {
    "ar": [
        "مرحبا", "شكرا", "طيب", "خلاص", "يلا", "ماشي", "أكيد", "ممكن", "لحظة",
        "صباح الخير", "مساء الخير", "كيف الحال", "وين رايح", "شو صار", "ليش",
        "الحمد لله", "إن شاء الله", "ما شاء الله", "الله يخليك", "تمام",
        "يا محمد", "يا أحمد", "يا سارة", "يا عمر", "يا ليلى", "يا خالد", "يا نور",
        "يا يوسف", "يا مريم", "يا علي", "يا فاطمة", "يا حسن", "يا زينب",
        "الساعة كم", "وين المفتاح", "افتح الباب", "سكر الشباك", "شغل الضوء",
        "طفي الضوء", "ارفع الصوت", "وطي الصوت", "شو الأخبار", "بكرا",
        "اليوم", "السيارة", "المطبخ", "الغرفة", "التلفزيون", "الموسيقى",
        "القهوة", "الشاي", "العشاء", "الفطور", "المدرسة", "الشغل", "البيت",
        "عشرة", "عشرين", "خمسة", "سبعة", "تسعة", "مية", "ألف", "مليون",
        "كمبيوتر", "موبايل", "تلفون", "انترنت", "سماعة", "كاميرا",
        "أوكي", "أهلا", "باي", "لا", "نعم", "أيوة", "شوي", "كتير", "حلو",
    ],
    "en": [
        "hello", "thanks", "okay", "sure", "maybe", "later", "tonight", "tomorrow",
        "good morning", "good night", "how are you", "what time is it", "come on",
        "let's go", "no way", "of course", "never mind", "hold on", "one second",
        "hey Mark", "hey Sarah", "hey Tom", "hey Anna", "hey Ali", "hey Sam",
        "hey Leo", "hey Maya", "hey John", "hey Emma", "hey Noah", "hey Lily",
        "open the door", "close the window", "turn on the light", "turn it off",
        "volume up", "volume down", "play some music", "stop the song",
        "the car", "the kitchen", "the bedroom", "the television", "coffee",
        "tea", "dinner", "breakfast", "school", "work", "home", "weekend",
        "seven", "eleven", "twenty", "a hundred", "a thousand", "a million",
        "computer", "phone", "internet", "camera", "speaker", "keyboard",
        "olive", "oven", "over", "only", "open", "order", "organ", "owner",
        "carry on", "arrive on", "iron", "ion", "lion", "line", "alien", "onion",
    ],
}


def load_key():
    with open(os.path.join(REPO, ".env"), encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("FISH_API_KEY="):
                return line.split("=", 1)[1].strip()
    raise SystemExit("FISH_API_KEY not found in .env")


def load_voices():
    path = os.path.join(HERE, "work", "fish_voices.json")
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def synth(key, text, voice_id, speed, volume, temperature, top_p):
    body = {
        "text": text,
        "reference_id": voice_id,
        "format": "wav",
        "sample_rate": 16000,
        "latency": "normal",
        "temperature": temperature,
        "top_p": top_p,
        "normalize": False,
        "prosody": {"speed": speed, "volume": volume},
    }
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": "Bearer " + key,
            "Content-Type": "application/json",
            "model": TTS_MODEL,
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def worker(jobs, key, out_dir, log_lock, log_file, stats):
    while True:
        try:
            job = jobs.get_nowait()
        except queue.Empty:
            return
        name = job["name"]
        path = os.path.join(out_dir, name)
        if os.path.exists(path) and os.path.getsize(path) > 2000:
            jobs.task_done()
            continue
        audio = None
        error = ""
        for attempt in range(3):
            try:
                audio = synth(
                    key,
                    job["text"],
                    job["voice"],
                    job["speed"],
                    job["volume"],
                    job["temperature"],
                    job["top_p"],
                )
                break
            except urllib.error.HTTPError as exc:
                error = "http %d" % exc.code
                if exc.code in (429, 500, 502, 503):
                    time.sleep(2 * (attempt + 1))
                    continue
                break
            except Exception as exc:  # network flakiness
                error = type(exc).__name__
                time.sleep(2 * (attempt + 1))
        with log_lock:
            if audio and len(audio) > 2000:
                with open(path, "wb") as f:
                    f.write(audio)
                stats["ok"] += 1
                stats["chars"] += len(job["text"])
                stats["bytes"] += len(audio)
                record = dict(job, result="ok", bytes=len(audio))
            else:
                stats["fail"] += 1
                record = dict(job, result="fail", error=error)
            log_file.write(json.dumps(record, ensure_ascii=False) + "\n")
            log_file.flush()
            done = stats["ok"] + stats["fail"]
            if done % 25 == 0:
                print(
                    "  %d done, %d ok, %d failed, %d chars"
                    % (done, stats["ok"], stats["fail"], stats["chars"]),
                    flush=True,
                )
        jobs.task_done()


def build_jobs(kind, count, voices, seed):
    rng = random.Random(seed)
    ar_voices = [v for v in voices if v["bucket"] == "ar"]
    en_voices = [v for v in voices if v["bucket"] == "en"]
    jobs = []
    for i in range(count):
        # 70 percent Arabic voices, the audience speaks Arabic.
        arabic = rng.random() < 0.70
        voice = rng.choice(ar_voices if arabic else en_voices)
        lang = "ar" if arabic else "en"
        if kind in VARIANTS:
            text = rng.choice(VARIANTS[kind][lang])
        elif kind == "negative":
            text = rng.choice(NEGATIVES[lang])
        else:
            text = rng.choice(CONFUSABLES[lang])
        jobs.append(
            {
                "name": "%05d_%s.wav" % (i, voice["id"][:8]),
                "text": text,
                "voice": voice["id"],
                "lang": lang,
                "speed": round(rng.uniform(0.75, 1.35), 2),
                "volume": rng.choice([0, 0, 0, -4, 4]),
                "temperature": round(rng.uniform(0.4, 0.95), 2),
                "top_p": round(rng.uniform(0.6, 0.95), 2),
            }
        )
    return jobs


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser()
    parser.add_argument("--phrase", required=True, help="orion, hey_orion or confusable")
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--threads", type=int, default=6)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()

    key = load_key()
    voices = load_voices()
    out_dir = os.path.join(HERE, "data", "fish", args.phrase)
    os.makedirs(out_dir, exist_ok=True)

    jobs_list = build_jobs(args.phrase, args.count, voices, args.seed)
    jobs = queue.Queue()
    for job in jobs_list:
        jobs.put(job)

    stats = {"ok": 0, "fail": 0, "chars": 0, "bytes": 0}
    log_lock = threading.Lock()
    log_path = os.path.join(HERE, "work", "fish_log.jsonl")
    started = time.time()
    with open(log_path, "a", encoding="utf-8") as log_file:
        threads = []
        for _ in range(1 if args.smoke else args.threads):
            t = threading.Thread(
                target=worker,
                args=(jobs, key, out_dir, log_lock, log_file, stats),
                daemon=True,
            )
            t.start()
            threads.append(t)
        for t in threads:
            t.join()

    print(
        "phrase=%s ok=%d fail=%d chars=%d wav_mb=%.1f seconds=%.0f"
        % (
            args.phrase,
            stats["ok"],
            stats["fail"],
            stats["chars"],
            stats["bytes"] / 1e6,
            time.time() - started,
        )
    )


if __name__ == "__main__":
    main()
