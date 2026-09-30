# Checks how the board's voice would sound, without playing it. The board runs
# its speaker pipeline at full volume with the amp silenced (spk silent on),
# records what it would have played (spk capture on), and prints it with
# `spk dump`. This reads those dumps out of a console log, saves each as a WAV
# and measures what the ear complains about: clicks, abrupt dropouts,
# clipping, level, and where the energy sits (bass that rattles a small
# speaker, harsh top).
#
#   python tools/cloud/console_session.py --out logs/voice.txt \
#       "spk silent on" "spk capture on" "vol 100" \
#       "ask Tell me a story." "spk dump"
#   python tools/audio/voice_check.py logs/voice.txt
#
# With --reference it also asks Fish for the same sentence directly (key from
# .env, never printed) and measures that too, so the board's output can be
# told apart from what the voice model sends.
import argparse
import base64
import json
import re
import sys
import urllib.request
import wave
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
BANDS = [(0, 150), (150, 300), (300, 1000), (1000, 3000), (3000, 6000), (6000, 12000)]


def dumps(log_text):
    """(label, rate, pcm) for each dump, labelled by the request before it."""
    out = []
    label = ''
    lines = log_text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        m_ask = re.match(r'^>>> (ask|talk) (.*)', line)
        if m_ask:
            label = m_ask.group(2)
            if label.startswith('hex:'):
                try:
                    label = bytes.fromhex(label[4:]).decode('utf-8')
                except ValueError:
                    pass
        m = re.match(r'^SPKDUMP BEGIN rate=(\d+) samples=(\d+)', line)
        if m:
            rate, n = int(m.group(1)), int(m.group(2))
            # Each line is "@<index hex>,<base64 of 768 bytes>". A line the
            # console mangled is left as a gap, marked, not decoded.
            buf = bytearray(n * 2)
            ok = np.zeros(n, dtype=bool)
            i += 1
            while i < len(lines) and not lines[i].startswith('SPKDUMP END'):
                mm = re.fullmatch(r'@([0-9a-f]+),([A-Za-z0-9+/=]+)', lines[i].strip())
                if mm:
                    try:
                        raw = base64.b64decode(mm.group(2), validate=True)
                    except ValueError:
                        raw = b''
                    at = int(mm.group(1), 16) * 768
                    if raw and at + len(raw) <= len(buf) and (len(raw) == 768 or at + len(raw) == len(buf)):
                        buf[at:at + len(raw)] = raw
                        ok[at // 2:(at + len(raw)) // 2] = True
                i += 1
            pcm = np.frombuffer(bytes(buf), dtype='<i2')
            out.append((label, rate, pcm, ok))
        i += 1
    return out


def reply_texts(log_text):
    return [m.group(1) for m in re.finditer(r'turn: reply: (.*)', log_text)]


def db(x):
    return 20 * np.log10(max(x, 1e-9))


def measure(pcm, rate, ok=None):
    if ok is None:
        ok = np.ones(len(pcm), dtype=bool)
    x = pcm.astype(np.float64) / 32768.0
    if len(x) < rate // 10:
        return None
    frame = rate // 100    # 10 ms
    n = len(x) // frame
    fr = x[:n * frame].reshape(n, frame)
    frame_rms = np.sqrt((fr ** 2).mean(axis=1))
    active = frame_rms > 10 ** (-50 / 20)
    act = fr[active].ravel() if active.any() else x

    # Clicks: a sample whose second difference towers over its 10 ms
    # neighbourhood. Speech has sharp consonants, so the bar is high.
    d2 = np.abs(np.diff(x, 2))
    k = frame
    c = np.cumsum(np.concatenate([[0.0], d2 ** 2]))
    local = np.sqrt((c[2 * k:] - c[:-2 * k]) / (2 * k))
    mid = d2[k:k + len(local)]
    clicks = np.nonzero((mid > 10 * local) & (mid > 0.08))[0] + k + 1
    # Only where the samples around are all real, not a gap in the dump.
    good = np.convolve(ok.astype(int), np.ones(2 * k + 3, dtype=int), 'same') == 2 * k + 3
    clicks = clicks[good[clicks]]

    # Abrupt dropouts: straight from sound to digital silence for 15 ms or
    # more, inside the reply. A faded pause does not count.
    zero = np.abs(pcm) < 4
    drops = []
    j = 0
    first = np.argmax(frame_rms > 10 ** (-45 / 20)) * frame
    last = (n - np.argmax(frame_rms[::-1] > 10 ** (-45 / 20))) * frame
    while j < len(pcm):
        if zero[j] and first < j < last:
            e = j
            while e < len(pcm) and zero[e]:
                e += 1
            if e - j >= rate * 15 // 1000 and abs(int(pcm[j - 1])) > 600 and ok[j - 1:e].all():
                drops.append((j, e - j))
            j = e
        else:
            j += 1

    spec = np.abs(np.fft.rfft(act * np.hanning(len(act)))) ** 2
    freqs = np.fft.rfftfreq(len(act), 1 / rate)
    total = spec.sum() + 1e-18
    bands = {f'{lo}-{hi}': round(10 * np.log10(spec[(freqs >= lo) & (freqs < hi)].sum() / total + 1e-12), 1)
             for lo, hi in BANDS}
    return {
        'seconds': round(len(x) / rate, 1),
        'peak_dbfs': round(db(np.abs(x).max()), 1),
        'rms_dbfs': round(db(np.sqrt((act ** 2).mean())), 1),
        'clipped': int((np.abs(pcm) >= 32700).sum()),
        'clicks': len(clicks),
        'click_ms': [int(t * 1000 / rate) for t in clicks[:8]],
        'dropouts': len(drops),
        'dropout_ms': [(int(s * 1000 / rate), int(d * 1000 / rate)) for s, d in drops[:5]],
        'dc': round(float(x.mean()), 5),
        'gaps_ms': int((~ok).sum() * 1000 / rate),
        'bands_db': bands,
    }


def fish_reference(text, rate):
    key = next(l.split('=', 1)[1].strip() for l in open(REPO / '.env', encoding='utf-8')
               if l.startswith('FISH_API_KEY='))
    body = json.dumps({'text': text, 'reference_id': '9a68c1d739134940a4297c996c5ca6a1',
                       'format': 'pcm', 'sample_rate': rate, 'latency': 'balanced'}).encode()
    req = urllib.request.Request('https://api.fish.audio/v1/tts', data=body, headers={
        'Authorization': f'Bearer {key}', 'Content-Type': 'application/json', 'model': 's2.1-pro-free'})
    with urllib.request.urlopen(req, timeout=60) as r:
        return np.frombuffer(r.read(), dtype='<i2')


def save(pcm, rate, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log')
    ap.add_argument('--out', default='logs/voice')
    ap.add_argument('--reference', action='store_true')
    args = ap.parse_args()
    text = Path(args.log).read_text(encoding='utf-8', errors='replace')
    found = dumps(text)
    replies = reply_texts(text)
    out_dir = REPO / args.out
    results = []
    for n, (label, rate, pcm, ok) in enumerate(found):
        save(pcm, rate, out_dir / f'{n:02d}_board.wav')
        row = {'n': n, 'request': label[:60], 'board': measure(pcm, rate, ok)}
        if args.reference and n < len(replies):
            ref = fish_reference(re.sub(r'\[[^\]]*\]\s*', '', replies[n]), rate)
            save(ref, rate, out_dir / f'{n:02d}_fish.wav')
            row['fish'] = measure(ref, rate)
        results.append(row)
        print(json.dumps(row, ensure_ascii=False))
    (out_dir / 'report.json').write_text(json.dumps(results, ensure_ascii=False, indent=1), encoding='utf-8')
    return 0 if found else 1


if __name__ == '__main__':
    sys.exit(main())
