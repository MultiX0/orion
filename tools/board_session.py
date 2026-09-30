"""Flash, reset, capture and play test audio as one locked session.

flash.ps1 and serial_capture.py each take the board lock for one step, so
another process can flash its own build in the gap between them, and a test
then measures the wrong firmware. This holds the lock for the whole sequence.

    python tools/board_session.py --app firmware/build/orion.bin \
        --model firmware/build/wakeword_model.bin \
        --play logs/test/a.wav --play logs/test/b.wav --gap 40 --out logs/x.txt
"""

import argparse
import subprocess
import sys
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import serial_capture as sc  # noqa: E402

REPO = sc.REPO


def esptool_write(port, pairs):
    args = ["powershell", "-ExecutionPolicy", "Bypass", "-File", str(REPO / "tools" / "idf.ps1"),
            "--esptool", "--chip", "esp32s3", "--port", port, "write_flash"]
    for addr, path in pairs:
        args += [addr, str(path)]
    r = subprocess.run(args, capture_output=True, text=True)
    ok = r.returncode == 0 and "Hash of data verified" in r.stdout
    print(f"board_session: flashed {', '.join(a for a, _ in pairs)}: {'ok' if ok else 'FAILED'}", flush=True)
    if not ok:
        sys.exit(r.stdout[-2000:] + r.stderr[-2000:])


def play_later(files, first_delay, gap):
    import winsound
    time.sleep(first_delay)
    for f in files:
        winsound.PlaySound(str(f), winsound.SND_FILENAME)
        print(f"board_session: played {Path(f).name} at {time.strftime('%H:%M:%S')}", flush=True)
        time.sleep(gap)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app")
    p.add_argument("--model")
    p.add_argument("--play", action="append", default=[])
    p.add_argument("--first-delay", type=float, default=20)
    p.add_argument("--gap", type=float, default=40)
    p.add_argument("--seconds", type=float, default=0)
    p.add_argument("--out", required=True)
    a = p.parse_args()

    port = sc.read_port()
    seconds = a.seconds or a.first_delay + len(a.play) * a.gap + 15
    lines = []
    with sc.Lock():
        pairs = []
        if a.app:
            pairs.append(("0x10000", REPO / a.app))
        if a.model:
            pairs.append(("0x710000", REPO / a.model))
        if pairs:
            esptool_write(port, pairs)
        sc.hard_reset(port, 115200)
        s = sc.connect(port, 115200)
        t = threading.Thread(target=play_later, args=(a.play, a.first_delay, a.gap), daemon=True)
        t.start()
        buf = bytearray()
        end = time.time() + seconds
        while time.time() < end:
            buf.extend(s.read(4096))
        s.close()
        lines = buf.decode("utf-8", "replace").splitlines()
    out = REPO / a.out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"board_session: {len(lines)} lines -> {out}", flush=True)


if __name__ == "__main__":
    main()
