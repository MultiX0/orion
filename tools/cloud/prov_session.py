"""Serial capture that survives the board rebooting itself.

`prov start` restarts the board into Bluetooth setup mode, and a plain
serial_capture.py dies when the USB port drops. This holds the same board lock,
sends lines at chosen times, reconnects whenever the port vanishes, and keeps
capturing until the deadline.

    python tools/cloud/prov_session.py --seconds 180 --send-at "3:prov start" --out logs/prov.txt
    python tools/cloud/prov_session.py --seconds 60 --reset --send-at "12:heap" --out logs/boot.txt
"""

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import serial_capture as sc  # noqa: E402

try:
    import serial
except ImportError:
    sys.exit("pyserial is missing. Run: python -m pip install pyserial")


def reopen(port, baud, timeout_s):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        try:
            s = serial.Serial(baudrate=baud, timeout=0.2)
            s.dtr = False
            s.rts = False
            s.port = port
            s.open()
            return s
        except serial.SerialException:
            time.sleep(0.3)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=float, default=120)
    ap.add_argument("--send-at", action="append", default=[], help="SECONDS:line, repeatable")
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--out", required=True)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    port = sc.read_port()
    sends = []
    for item in a.send_at:
        t, line = item.split(":", 1)
        sends.append((float(t), line))
    sends.sort()

    out = Path(a.out)
    if not out.is_absolute():
        out = sc.REPO / out
    lines = []
    raw = bytearray()

    with sc.Lock():
        if a.reset:
            sc.hard_reset(port, 115200)
        s = reopen(port, 115200, 20)
        if not s:
            sys.exit(f"prov_session: cannot open {port}")
        start = time.time()
        while time.time() - start < a.seconds:
            now = time.time() - start
            while sends and sends[0][0] <= now:
                _, line = sends.pop(0)
                try:
                    s.write((line + "\n").encode())
                    s.flush()
                    stamp = f"[prov_session +{now:.1f}s sent: {line}]"
                    lines.append(stamp)
                    if not a.quiet:
                        print(stamp, flush=True)
                except serial.SerialException:
                    sends.insert(0, (now + 1, line))
            try:
                chunk = s.read(4096)
            except serial.SerialException:
                stamp = f"[prov_session +{now:.1f}s port dropped, reconnecting]"
                lines.append(stamp)
                if not a.quiet:
                    print(stamp, flush=True)
                try:
                    s.close()
                except Exception:
                    pass
                s = reopen(port, 115200, 30)
                if not s:
                    lines.append("[prov_session port never came back]")
                    break
                continue
            if not chunk:
                continue
            raw.extend(chunk)
            while b"\n" in raw:
                line, raw = raw.split(b"\n", 1)
                text = line.rstrip(b"\r").decode("utf-8", "replace")
                lines.append(text)
                if not a.quiet:
                    print(text, flush=True)
        try:
            s.close()
        except Exception:
            pass

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"prov_session: {len(lines)} lines -> {out}", flush=True)


if __name__ == "__main__":
    main()
