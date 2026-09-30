"""Non-interactive serial reader for the Orion board.

`idf.py monitor` never returns, so it cannot be scripted. This resets the
board, captures for a fixed number of seconds, writes the text to a file and
exits.

    python tools/serial_capture.py --seconds 20 --out logs/boot.txt
    python tools/serial_capture.py --seconds 15 --send "talk hello" --out logs/talk.txt
    python tools/serial_capture.py --seconds 1800 --out logs/soak.txt --no-reset

Shares the flash lock with tools/flash.ps1, because there is one board and one
port. Both treat a lock older than 10 minutes as stale.

Wake clips: the firmware frames debug audio as

    ORION_CLIP_BEGIN <name> <sample_rate>
    <base64, any number of lines>
    ORION_CLIP_END

and each one is written to logs/wake_clips/<name>.wav.
"""

import argparse
import base64
import os
import re
import sys
import time
import wave
from datetime import datetime
from pathlib import Path

try:
    import serial
except ImportError:
    sys.exit("pyserial is missing. Run: python -m pip install pyserial")

REPO = Path(__file__).resolve().parent.parent
LOCK = Path(os.environ["USERPROFILE"]) / ".orion" / "flash.lock"
STALE_SECONDS = 10 * 60

CLIP_BEGIN = re.compile(rb"ORION_CLIP_BEGIN\s+(\S+)\s+(\d+)")
CLIP_END = b"ORION_CLIP_END"


def pid_alive(pid):
    """A killed process cannot run its cleanup, so it leaves the lock behind.
    Waiting 10 minutes for that is wasted time when the holder is plainly gone."""
    import ctypes
    QUERY_LIMITED = 0x1000
    STILL_ACTIVE = 259
    h = ctypes.windll.kernel32.OpenProcess(QUERY_LIMITED, False, pid)
    if not h:
        return False
    code = ctypes.c_ulong()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(h)
    return bool(ok) and code.value == STILL_ACTIVE


def lock_holder_gone():
    try:
        text = LOCK.read_text()
    except OSError:
        return False
    m = re.search(r"pid=(\d+)", text)
    return bool(m) and not pid_alive(int(m.group(1)))


class Lock:
    """Exclusive against tools/flash.ps1, which opens the same path with
    FileShare.None. Holding an open handle here is what blocks it."""

    def __init__(self, wait_minutes=15):
        self.wait = wait_minutes * 60
        self.fd = None

    def __enter__(self):
        LOCK.parent.mkdir(parents=True, exist_ok=True)
        deadline = time.time() + self.wait
        while True:
            if LOCK.exists() and (
                    time.time() - LOCK.stat().st_mtime > STALE_SECONDS
                    or lock_holder_gone()):
                print("serial_capture: lock is stale, taking it over", flush=True)
                try:
                    LOCK.unlink()
                except OSError:
                    pass
            try:
                self.fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_RDWR)
                os.write(self.fd, f"pid={os.getpid()} at={datetime.now().isoformat()}".encode())
                return self
            except FileExistsError:
                if time.time() > deadline:
                    sys.exit(f"serial_capture: gave up waiting for {LOCK}")
                time.sleep(5)

    def __exit__(self, *exc):
        if self.fd is not None:
            os.close(self.fd)
        try:
            LOCK.unlink()
        except OSError:
            pass


def read_port():
    f = REPO / "tools" / "port.txt"
    if f.exists():
        return f.read_text().strip()
    return None


def hard_reset(port, baud):
    """Pulse EN on a USB-Serial-JTAG board without entering download mode.

    RTS drives EN, DTR drives GPIO0. DTR stays low the whole time so the chip
    boots the app. Windows only propagates RTS when the state actually changes,
    hence the repeated set.
    """
    try:
        s = serial.Serial(port, baud, timeout=0.1)
    except serial.SerialException as e:
        print(f"serial_capture: cannot open {port} to reset: {e}", flush=True)
        return
    try:
        s.setDTR(False)
        s.setRTS(False)
        time.sleep(0.05)
        s.setDTR(False)
        s.setRTS(True)
        s.setRTS(True)
        time.sleep(0.1)
        s.setRTS(False)
        s.setDTR(False)
    finally:
        try:
            s.close()
        except Exception:
            pass


def connect(port, baud, timeout_s=20):
    """The board re-enumerates its USB after a reset, so the COM port vanishes
    for a second or two. Keep retrying until it comes back."""
    deadline = time.time() + timeout_s
    last = None
    while time.time() < deadline:
        try:
            # Opening with the port set asserts DTR and RTS, which resets a
            # USB-Serial-JTAG board even with --no-reset. Configure the lines
            # low first, then open.
            s = serial.Serial(baudrate=baud, timeout=0.2)
            s.dtr = False
            s.rts = False
            s.port = port
            s.open()
            return s
        except serial.SerialException as e:
            last = e
            time.sleep(0.15)
    sys.exit(f"serial_capture: {port} never came back after reset: {last}")


def save_clip(name, rate, payload, out_dir):
    try:
        pcm = base64.b64decode(payload, validate=False)
    except Exception as e:
        print(f"serial_capture: clip {name} failed to decode: {e}", flush=True)
        return
    if not pcm:
        return
    out_dir.mkdir(parents=True, exist_ok=True)
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", name)
    path = out_dir / f"{safe}.wav"
    if path.exists():
        path = out_dir / f"{safe}_{int(time.time())}.wav"
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    print(f"serial_capture: wrote {path} ({len(pcm)} bytes pcm)", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--seconds", type=float, default=20)
    p.add_argument("--out", default=None)
    p.add_argument("--port", default=None)
    p.add_argument("--baud", type=int, default=115200)
    p.add_argument("--send", action="append", default=[],
                   help="line to write after connecting, repeatable")
    p.add_argument("--send-delay", type=float, default=1.5,
                   help="seconds to wait after connecting before sending")
    p.add_argument("--no-reset", action="store_true")
    p.add_argument("--clips-dir", default=None)
    p.add_argument("--quiet", action="store_true", help="do not echo to stdout")
    a = p.parse_args()

    port = a.port or read_port()
    if not port:
        sys.exit("serial_capture: no port. Pass --port COMx or write tools/port.txt.")

    clips_dir = Path(a.clips_dir) if a.clips_dir else REPO / "logs" / "wake_clips"
    out_path = Path(a.out) if a.out else None
    if out_path and not out_path.is_absolute():
        out_path = REPO / out_path

    captured = []

    with Lock():
        if not a.no_reset:
            hard_reset(port, a.baud)

        s = connect(port, a.baud)
        raw = bytearray()
        pending = None          # (name, rate, bytearray) while inside a clip
        sent = False
        start = time.time()
        try:
            while time.time() - start < a.seconds:
                if a.send and not sent and time.time() - start >= a.send_delay:
                    for line in a.send:
                        s.write((line + "\n").encode())
                        s.flush()
                        time.sleep(0.1)
                    sent = True

                chunk = s.read(4096)
                if not chunk:
                    continue
                raw.extend(chunk)

                # Handle clip framing on whole lines only.
                while b"\n" in raw:
                    line, raw = raw.split(b"\n", 1)
                    line = line.rstrip(b"\r")

                    if pending is not None:
                        if CLIP_END in line:
                            name, rate, buf = pending
                            save_clip(name, rate, bytes(buf), clips_dir)
                            pending = None
                        else:
                            pending[2].extend(line.strip())
                        continue

                    m = CLIP_BEGIN.search(line)
                    if m:
                        pending = (m.group(1).decode("ascii", "replace"),
                                   int(m.group(2)), bytearray())
                        continue

                    text = line.decode("utf-8", "replace")
                    if not a.quiet:
                        print(text, flush=True)
                    if out_path:
                        captured.append(text)
        except KeyboardInterrupt:
            pass
        finally:
            leftover = raw.decode("utf-8", "replace")
            if leftover.strip():
                if not a.quiet:
                    print(leftover, flush=True)
                if out_path:
                    captured.append(leftover)
            s.close()

    if out_path:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(captured), encoding="utf-8")
        print(f"serial_capture: {len(captured)} lines -> {out_path}", flush=True)


if __name__ == "__main__":
    main()
