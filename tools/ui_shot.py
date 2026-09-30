# Turns the board's "ui shot" console dump into a PNG: what is on the 240x240
# screen right now, at twice the size. Log lines the board prints while it
# dumps are skipped.
#
#   python tools/serial_capture.py --no-reset --seconds 8 --send "ui shot" --out shot.txt
#   python tools/ui_shot.py shot.txt screen.png
import base64
import re
import sys

from PIL import Image


def main():
    log, out = sys.argv[1], sys.argv[2]
    lines = open(log, encoding='utf-8', errors='replace').read().splitlines()
    start = max(i for i, l in enumerate(lines) if l.startswith('SHOT BEGIN'))
    w, h = map(int, lines[start].split()[2:4])
    b64 = re.compile(r'^[A-Za-z0-9+/=]{100,}$')
    raw = bytearray()
    for l in lines[start + 1:]:
        if l.startswith('SHOT END'):
            break
        if b64.match(l.strip()):
            raw += base64.b64decode(l.strip())
    if len(raw) < w * h * 2:
        sys.exit(f'short dump: {len(raw)} of {w * h * 2} bytes')
    img = Image.new('RGB', (w, h))
    px = img.load()
    for i in range(w * h):
        v = raw[2 * i + 1] << 8 | raw[2 * i]   # RGB565, little endian
        px[i % w, i // w] = (((v >> 11) & 0x1F) * 255 // 31,
                             ((v >> 5) & 0x3F) * 255 // 63,
                             (v & 0x1F) * 255 // 31)
    img.resize((w * 2, h * 2), Image.NEAREST).save(out)
    print('saved', out)


if __name__ == '__main__':
    main()
