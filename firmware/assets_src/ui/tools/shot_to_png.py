"""Turn a `ui shot` dump from the board's serial console into a PNG.

The firmware prints the LVGL framebuffer as base64 RGB565 between two
markers and this reassembles it. A screenshot is the only way to prove that
Arabic actually joined and ran right to left.

    python tools/serial_capture.py --seconds 12 --send "ui shot" --out logs/s.txt
    python firmware/assets_src/ui/tools/shot_to_png.py logs/s.txt logs/idle.png

Multiple shots in one capture become name.png, name-2.png, and so on.
Needs Pillow.
"""
import base64
import re
import sys
from pathlib import Path

from PIL import Image

BEGIN = re.compile(r"SHOT BEGIN (\d+) (\d+) rgb565")
B64 = re.compile(r"^[A-Za-z0-9+/]+=*$")


def payload(line):
    """The console prompt and an ESP_LOG line can land in the middle of the
    dump. Take only what is unambiguously a base64 chunk."""
    s = line.strip()
    if s.startswith("orion>"):
        s = s[6:].strip()
    return s if len(s) >= 64 and B64.match(s) else ""


def shots(text):
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = BEGIN.search(lines[i])
        if not m:
            i += 1
            continue
        w, h = int(m.group(1)), int(m.group(2))
        body = []
        i += 1
        while i < len(lines) and "SHOT END" not in lines[i]:
            body.append(payload(lines[i]))
            i += 1
        blob = "".join(body)
        blob = blob[:len(blob) - len(blob) % 4]
        yield w, h, base64.b64decode(blob)
        i += 1


def to_image(w, h, raw):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        row = y * w * 2
        for x in range(w):
            v = raw[row + x * 2] | (raw[row + x * 2 + 1] << 8)  # LVGL is little endian
            r = (v >> 11) & 0x1F
            g = (v >> 5) & 0x3F
            b = v & 0x1F
            px[x, y] = (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2)
    return img


def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    dst.parent.mkdir(parents=True, exist_ok=True)
    text = src.read_text(encoding="utf-8", errors="replace")
    n = 0
    for w, h, raw in shots(text):
        n += 1
        if len(raw) < w * h * 2:
            print("  shot %d truncated: %d of %d bytes" % (n, len(raw), w * h * 2))
            raw = raw + bytes(w * h * 2 - len(raw))
        out = dst if n == 1 else dst.with_name("%s-%d%s" % (dst.stem, n, dst.suffix))
        to_image(w, h, raw).save(out)
        print("  %s" % out)
    if n == 0:
        sys.exit("no SHOT BEGIN block in %s" % src)


if __name__ == "__main__":
    main()
