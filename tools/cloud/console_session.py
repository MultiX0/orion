# Drives the board's console one command at a time and waits for each to
# finish, for the latency tables.
#
# serial_capture --send fires every line at once, which is fine for one
# command but loses lines once a talk turn keeps the console busy for seconds
# and the rest pile up in its receive buffer. This sends a line, waits for that
# command's own result line, then sends the next.
#
# Uses serial_capture's lock, so it waits its turn for the shared board.
# Nothing is played through the PC, and the first command after the reset is
# vol 0, so the board streams its audio at zero amplitude: every stage still
# runs in real time, nobody in the room hears it.
#
#   python tools/cloud/console_session.py --out logs/session.txt \
#       "asr_test earcons/error.wav" "talk What is the capital of France?"

import argparse
import re
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import serial_capture as sc

# The line each command prints when it has finished.
# The second talk and asr forms are what older firmware prints.
DONE = [
    (re.compile(r"^talk "), re.compile(r"^talk llm_first_ms=|^llm_ms=\d+ tts_first_ms=|failed")),
    # "asr 12/12": the last of a repeated run, where both numbers match.
    (re.compile(r"^asr_test"), re.compile(r"^asr (\d+)/\1 |^asr \d+\.\d s|^asr failed")),
    (re.compile(r"^ask "), re.compile(r"turn_perf |sm: .* -> idle|turn \d+ failed")),
    (re.compile(r"^vol"), re.compile(r"vol|volume")),
    (re.compile(r"^cloud_test"), re.compile(r"^cloud_test \w+ ok=")),
    (re.compile(r"^cloud_reload"), re.compile(r"^cloud_reload ")),
    (re.compile(r"^cfg_"), re.compile(r"^cfg_set ")),
    (re.compile(r"^heap"), re.compile(r"heap_int=")),
    (re.compile(r"^spk dump"), re.compile(r"^SPKDUMP END")),
]


def done_pattern(cmd):
    for rx, pattern in DONE:
        if rx.search(cmd):
            return pattern
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("commands", nargs="+")
    ap.add_argument("--out", default="logs/session.txt")
    ap.add_argument("--timeout", type=float, default=45.0)
    ap.add_argument("--settle", type=float, default=3.0,
                    help="seconds after Wi-Fi before the first command")
    args = ap.parse_args()

    port = sc.read_port()
    out = REPO / args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    state = {"rebooted": False}
    reboot = re.compile(r"ESP-ROM:|rst:0x")

    def pump(s, until=None, timeout=5.0):
        """Reads lines until one matches until, or timeout. Returns the match."""
        buf = bytearray()
        deadline = time.time() + timeout
        while time.time() < deadline:
            chunk = s.read(4096)
            if chunk:
                buf.extend(chunk)
            while b"\n" in buf:
                raw, buf = buf.split(b"\n", 1)
                text = raw.rstrip(b"\r").decode("utf-8", "replace")
                lines.append(text)
                print(text, flush=True)
                if reboot.search(text):
                    state["rebooted"] = True
                    return None
                if until and until.search(text):
                    return text
        return None

    def ready(s):
        """Wi-Fi up, then silence the speaker. After every boot, not just the first."""
        state["rebooted"] = False
        if not pump(s, re.compile(r"orion_net: up"), 60):
            return False
        pump(s, None, args.settle)
        s.write(b"vol 0\n")
        s.flush()
        lines.append(">>> vol 0")
        pump(s, None, 1.5)
        return True

    with sc.Lock():
        sc.hard_reset(port, 115200)
        s = sc.connect(port, 115200)
        try:
            if not ready(s):
                print("console_session: Wi-Fi never came up")
                return 1
            for cmd in args.commands:
                print(">>> %s" % cmd, flush=True)
                lines.append(">>> " + cmd)
                s.write((cmd + "\n").encode("utf-8"))
                s.flush()
                pattern = done_pattern(cmd)
                if pattern and not pump(s, pattern, args.timeout):
                    print("console_session: no result for '%s' within %.0f s%s" % (
                        cmd, args.timeout, ", the board rebooted" if state["rebooted"] else ""))
                pump(s, None, 1.5)
                if state["rebooted"] and not ready(s):
                    print("console_session: the board did not come back")
                    return 1
        finally:
            s.close()

    out.write_text("\n".join(lines), encoding="utf-8")
    print("console_session: %d lines -> %s" % (len(lines), out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
