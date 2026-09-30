# WAV and PCM helpers. Fish returns raw headerless PCM and its own WAV headers
# carry placeholder sizes, so every header in this project is built here.

import struct
import wave
from pathlib import Path

SAMPLE_RATE = 16000


def wav_header(pcm_bytes, rate=SAMPLE_RATE, channels=1, bits=16):
    block = channels * bits // 8
    return b"RIFF" + struct.pack("<I", 36 + pcm_bytes) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, channels, rate, rate * block, block, bits
    ) + b"data" + struct.pack("<I", pcm_bytes)


def pcm_to_wav(pcm, rate=SAMPLE_RATE):
    return wav_header(len(pcm), rate) + pcm


def save_wav(path, pcm, rate=SAMPLE_RATE):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(pcm_to_wav(pcm, rate))
    return path


def load_wav(path):
    """Returns (pcm_bytes, rate). Refuses anything that is not 16-bit mono."""
    with wave.open(str(path), "rb") as w:
        if w.getnchannels() != 1 or w.getsampwidth() != 2:
            raise ValueError("%s is not 16-bit mono" % path)
        return w.readframes(w.getnframes()), w.getframerate()


def pcm_seconds(pcm, rate=SAMPLE_RATE):
    return len(pcm) / 2.0 / rate


def pcm_stats(pcm):
    """rms, peak and clipped sample count, for judging a generated clip."""
    n = len(pcm) // 2
    if n == 0:
        return {"rms": 0, "peak": 0, "clipped": 0, "silence_ratio": 1.0}
    vals = struct.unpack("<%dh" % n, pcm[:n * 2])
    total = 0
    peak = 0
    clipped = 0
    quiet = 0
    for v in vals:
        total += v * v
        a = abs(v)
        if a > peak:
            peak = a
        if a >= 32700:
            clipped += 1
        if a < 300:
            quiet += 1
    return {"rms": int((total / n) ** 0.5), "peak": peak, "clipped": clipped,
            "silence_ratio": quiet / float(n)}
