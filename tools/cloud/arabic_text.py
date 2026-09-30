# Comparing Arabic strings for the voice audition and the ASR tests.
#
# A transcript that says اهلين when the script said أهلين is the same word,
# so alef forms, ta marbuta, alef maqsura, tatweel, diacritics and punctuation
# are all folded away before anything is counted.

import re
import unicodedata

DIACRITICS = re.compile(r"[ؐ-ًؚ-ٰٟۖ-ۭـ]")
PUNCT = re.compile(r"[^\w\s؀-ۿ]", re.UNICODE)
# Arabic comma, semicolon, question mark and full stop live inside the Arabic
# block that PUNCT spares, so they are removed separately.
ARABIC_PUNCT = re.compile(r"[،؛؟۔]")

FOLD = {
    "آ": "ا", "أ": "ا", "إ": "ا", "ٱ": "ا",
    "ة": "ه",
    "ى": "ي",
    "ؤ": "و",
    "ئ": "ي",
    "ک": "ك",
    "ی": "ي",
}

# Whisper likes to sign off short clips with a subtitle credit that was never
# spoken. It is a hallucination, not a transcription error, so it is cut before
# scoring rather than counted against the voice.
HALLUCINATIONS = [
    "ترجمة نانسي قنقر", "ترجمة نانسي", "اشتركوا في القناة", "شكرا على المشاهدة",
    "الترجمة", "Amara.org", "subtitles by", "Thanks for watching",
]


def normalize(text):
    text = unicodedata.normalize("NFKC", text or "")
    for bad in HALLUCINATIONS:
        text = text.replace(bad, " ")
    text = DIACRITICS.sub("", text)
    text = "".join(FOLD.get(ch, ch) for ch in text)
    text = PUNCT.sub(" ", text)
    text = ARABIC_PUNCT.sub(" ", text)
    return " ".join(text.split()).strip()


def edit_distance(a, b):
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def cer(reference, hypothesis):
    """Character error rate after folding. 0.0 is a perfect match."""
    a = normalize(reference).replace(" ", "")
    b = normalize(hypothesis).replace(" ", "")
    if not a:
        return 1.0 if b else 0.0
    return edit_distance(a, b) / float(len(a))


def wer(reference, hypothesis):
    a = normalize(reference).split()
    b = normalize(hypothesis).split()
    if not a:
        return 1.0 if b else 0.0
    return edit_distance(a, b) / float(len(a))


def kept_english(reference, hypothesis):
    """Did the English words in the line survive as English?

    Returns (found, total). The Orion voice has to say "Spotify" and "PC" as
    English words inside an Arabic sentence, and a voice that reads them as
    Arabic letters is the wrong voice.
    """
    words = re.findall(r"[A-Za-z][A-Za-z0-9]{1,}", reference)
    if not words:
        return (0, 0)
    low = (hypothesis or "").lower()
    return (sum(1 for w in words if w.lower() in low), len(words))
