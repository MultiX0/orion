# One real voice turn on the board, measured the same way every time.
#
# Resets the board and captures serial, waits for Wi-Fi, then plays a clip
# through the PC speakers ("Orion, [pause], question") so the wake word, the
# microphone, the end of speech detector and every cloud stage all run for real.
# Then it pulls the per turn timings out of the log.
#
#   python tools/cloud/voice_turn.py logs/test/ar_time_pause.wav
#   python tools/cloud/voice_turn.py logs/test/en_france_pause.wav --runs 3

import argparse
import re
import subprocess
import threading
import sys
import time
import winsound
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

TURN = re.compile(r"turn=(\d+) .*")
FIELDS = re.compile(r"(\w+)=(\d+)")
FIRST_AUDIO = re.compile(r"speech_end_to_audio_ms=(\d+)")


class Lines:
    """serial_capture only writes its file when it exits, but it prints every
    line as it arrives. So the live view comes from its stdout."""

    def __init__(self, proc):
        self.lines = []
        self.lock = threading.Lock()
        threading.Thread(target=self._pump, args=(proc,), daemon=True).start()

    def _pump(self, proc):
        for raw in proc.stdout:
            with self.lock:
                self.lines.append(raw.decode("utf-8", "replace").rstrip())

    def text(self):
        with self.lock:
            return "\n".join(self.lines)


def wait_for(lines, pattern, timeout):
    rx = re.compile(pattern)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if rx.search(lines.text()):
            return True
        time.sleep(0.3)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wav")
    ap.add_argument("--runs", type=int, default=1)
    ap.add_argument("--out", default="logs/voice_turn.txt")
    ap.add_argument("--gap", type=float, default=35.0, help="seconds between runs")
    args = ap.parse_args()

    out = REPO / args.out
    out.parent.mkdir(parents=True, exist_ok=True)

    seconds = 30 + args.runs * args.gap
    cap = subprocess.Popen([sys.executable, str(REPO / "tools" / "serial_capture.py"),
                            "--seconds", str(seconds), "--out", str(out)],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    lines = Lines(cap)
    try:
        if not wait_for(lines, r"orion_net: up", 60):
            print("the board never reported Wi-Fi up")
            return 1
        # Let the wake word model settle after boot before talking to it.
        wait_for(lines, r"wakeword: listening", 15)
        time.sleep(4)
        for i in range(args.runs):
            print("run %d: playing %s" % (i + 1, args.wav))
            winsound.PlaySound(str(REPO / args.wav), winsound.SND_FILENAME)
            if not wait_for(lines, r"turn=%d " % (i + 1), args.gap):
                print("  no turn=%d line within %.0f s" % (i + 1, args.gap))
                continue
            time.sleep(2)
    finally:
        cap.wait()

    text = lines.text()
    for line in text.splitlines():
        if "heard:" in line or "reply:" in line or TURN.search(line) \
                or "speech_end_to_audio_ms" in line or "recorded" in line:
            print("  " + line.strip()[-220:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
