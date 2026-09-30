# The sounds the board makes without asking the cloud first.
#
# Four of them are speech in the Orion voice. The wake chime is not speech: it
# is two tones generated here, so waking up costs no network and no API credit.
#
# Two takes of every spoken line. The take that is kept is the one a second
# engine transcribes closest to what was asked for, so "most natural" is a
# measurement and not a guess.
#
#   python tools/cloud/make_earcons.py
#   python tools/cloud/make_earcons.py --only repeat

import argparse
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import arabic_text as at
import cloud_api as c

EARCONS = c.REPO / "firmware" / "assets" / "earcons"
TAKES = c.REPO / "logs" / "earcon_takes"

# name -> what Orion says, and the inline emotion tag to try in front of it.
# Short lines on purpose: these play before the real reply, so every extra
# syllable is dead air in the turn.
#
# Tags are performed and never spoken, proved in Arabic in emotion_test.py. Each
# line is generated both ways and the tagged take only ships if it does not cost
# intelligibility, measured, not assumed.
#
# The lines are fluent MSA in the Orion voice, with no spoken "ok" in the
# loop. Only tags tag_audition.py showed this voice performs are tried:
# [apologetic] where tone carries the meaning, and nothing on "one moment",
# which no kept tag fits. Speech is normalized to -1 dBFS.
LINES = [
    ("thinking", "لحظة من فضلك.", ""),
    ("repeat", "عذراً، هل يمكنك الإعادة؟", "[apologetic]"),
    ("offline", "لا يوجد اتصال بالإنترنت حالياً.", "[apologetic]"),
    ("error", "عذراً، حدث خطأ ما. حاول مرة أخرى.", "[apologetic]"),
]

# How much transcription accuracy a tagged take is allowed to give up before it
# is rejected. Expressive delivery is less canonical, so a small loss is the
# price of the feature, not a fault. Anything past this and the plain take wins.
CER_TOLERANCE = 0.06

# No prosody object, matching cloud_tts.c, and for the same measured reason:
# sending one costs about 9 dB and volume does not climb back to where leaving
# it out already sits. The earcons come out of the same speaker as the replies,
# so they are generated exactly the same way.
PROSODY = None


def chime(rate=c.SAMPLE_RATE):
    """The wake chime. Two tones a fifth apart, the second entering late.

    The envelope is the brand's signature curve in sound: an instant attack and
    a long settle, cubic-bezier(0.16, 1, 0.3, 1) rendered as an exponential
    decay. 400 ms, which is the brand's panel transition, so the chime and the
    screen waking up finish together.
    """
    total_ms = 400
    n = int(rate * total_ms / 1000)
    notes = [
        # freq Hz, start ms, gain, decay time constant ms
        (659.25, 0, 0.55, 150),    # E5
        (987.77, 90, 0.45, 190),   # B5, a fifth up
    ]
    buf = [0.0] * n
    for freq, start_ms, gain, tau in notes:
        start = int(rate * start_ms / 1000)
        for i in range(start, n):
            t = (i - start) / float(rate)
            # 6 ms attack, then exponential settle
            attack = min(1.0, t / 0.006)
            env = attack * math.exp(-t * 1000.0 / tau)
            # a quiet second partial gives it a bell edge instead of a beep
            s = math.sin(2 * math.pi * freq * t) + 0.22 * math.sin(4 * math.pi * freq * t)
            buf[i] += gain * env * s

    peak = max(abs(v) for v in buf) or 1.0
    # -1.5 dBFS, to sit with the speech now that the speech is mastered to about
    # -1 dBFS peak. A chime is a known deterministic waveform, so unlike the
    # speech there is no take to take variance to leave room for.
    scale = 0.841 / peak
    return b"".join(struct.pack("<h", int(max(-32767, min(32767, v * scale * 32767))))
                    for v in buf)


def normalize_peak(pcm, dbfs=-1.0):
    """Scale so the loudest sample sits at dbfs. Up or down, never clipping."""
    n = len(pcm) // 2
    vals = struct.unpack("<%dh" % n, pcm[:n * 2])
    peak = max(abs(v) for v in vals) or 1
    g = (32767.0 * 10 ** (dbfs / 20.0)) / peak
    return struct.pack("<%dh" % n, *(int(max(-32767, min(32767, round(v * g))))
                                     for v in vals))


def take_group(name, text, tag, sess, takes=2):
    """Two takes of one variant. Returns the best, lowest error then shortest."""
    results = []
    sent = (tag + text) if tag else text
    for i in range(1, takes + 1):
        pcm, first, _ = c.tts(sent, voice_id=c.env("FISH_VOICE_ID") or None,
                              sess=sess, model=c.env("FISH_TTS_MODEL", c.TTS_MODEL),
                              prosody=PROSODY)
        heard, _ = c.stt_deepinfra(c.pcm_to_wav(pcm), language="ar", sess=sess)
        stats = c.pcm_stats(pcm)
        # Always scored against the bare line: a tag that got spoken would show
        # up here as a large error, which is exactly what we want it to do.
        err = at.cer(text, heard)
        label = "%s_%s_take%d" % (name, "tagged" if tag else "plain", i)
        c.save_wav(TAKES / (label + ".wav"), pcm)
        results.append({"take": i, "tag": tag, "pcm": pcm, "cer": err,
                        "heard": heard, "seconds": c.pcm_seconds(pcm),
                        "rms": stats["rms"], "clipped": stats["clipped"],
                        "ttfb": first})
        print("  %-7s take%d  %.2f s  cer %.3f  rms %5d  heard: %s" % (
            "tagged" if tag else "plain", i, results[-1]["seconds"], err,
            stats["rms"], heard[:44]))

    results.sort(key=lambda r: (r["cer"], r["seconds"]))
    return results[0]


def best_take(name, text, tag, sess, takes=2):
    """Plain against tagged, two takes each. Says which won and why."""
    plain = take_group(name, text, "", sess, takes)
    if not tag:
        return plain, "no tag tried"

    tagged = take_group(name, text, tag, sess, takes)

    if "[" in tagged["heard"] or "]" in tagged["heard"]:
        return plain, "tag leaked into the audio, plain wins"
    if tagged["cer"] <= plain["cer"] + CER_TOLERANCE:
        return tagged, "tagged %s wins, cer %.3f against %.3f" % (
            tag, tagged["cer"], plain["cer"])
    return plain, "tagged %s cost too much accuracy, %.3f against %.3f" % (
        tag, tagged["cer"], plain["cer"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None)
    ap.add_argument("--takes", type=int, default=2)
    ap.add_argument("--no-tags", action="store_true", help="plain takes only")
    args = ap.parse_args()

    EARCONS.mkdir(parents=True, exist_ok=True)
    sess = c.session()
    print("voice %s, tts model %s" % ((c.env("FISH_VOICE_ID") or "none")[:8],
                                      c.env("FISH_TTS_MODEL", c.TTS_MODEL)))

    summary = []
    # The wake chime is final; it is rebuilt only when asked for by name.
    if args.only == "wake":
        pcm = chime()
        path = c.save_wav(EARCONS / "wake.wav", pcm)
        stats = c.pcm_stats(pcm)
        print("\nwake  generated locally, no API call")
        print("  %.2f s  rms %d  peak %d  clipped %d  ->  %s" % (
            c.pcm_seconds(pcm), stats["rms"], stats["peak"], stats["clipped"],
            path.name))
        summary.append(("wake", "(two tone chime)", "-", c.pcm_seconds(pcm),
                        0.0, stats["rms"], path.stat().st_size))

    for name, text, tag in LINES:
        if args.only and args.only != name:
            continue
        print("\n%s  %s   tag %s" % (name, text, tag or "(none)"))
        best, why = best_take(name, text, tag if not args.no_tags else "",
                              sess, takes=args.takes)
        pcm = normalize_peak(best["pcm"])
        path = c.save_wav(EARCONS / ("%s.wav" % name), pcm)
        st = c.pcm_stats(pcm)
        print("  %s -> %s  peak %d  clipped %d" % (why, path.name, st["peak"], st["clipped"]))
        summary.append((name, text, best["tag"] or "-", best["seconds"],
                        best["cer"], st["rms"], path.stat().st_size))

    print("\n| earcon | says | tag kept | seconds | CER | rms | bytes |")
    print("|---|---|---|---|---|---|---|")
    total = 0
    for name, text, tag, secs, err, rms, size in summary:
        total += size
        print("| %s | %s | %s | %.2f | %.3f | %d | %d |" % (
            name, text, tag, secs, err, rms, size))
    print("\n%d files, %.0f KB total, 16 kHz 16 bit mono, in %s" % (
        len(summary), total / 1024.0, EARCONS))


if __name__ == "__main__":
    main()
