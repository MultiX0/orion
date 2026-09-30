# Time to first token for two system prompts, streamed the way the board
# streams, the prompts interleaved question by question so service drift hits
# both alike. Text only, nothing is spoken.
#
#   python tools/voice_eval/ttft.py --rounds 3

import argparse
import json
import statistics
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cases import CASES, LOOK_TOOL, NOTE_ALONE, NOW
from voice_eval import DEFAULT_ENV, MODEL, PROMPT_PATH, REPO, URL, load_prompt, read_key


def first_token_ms(key, system, text):
    body = {"model": MODEL, "stream": True, "max_tokens": 200, "temperature": 0.6,
            "tools": LOOK_TOOL, "tool_choice": "auto",
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": text}]}
    req = urllib.request.Request(URL, data=json.dumps(body).encode("utf-8"), headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    t0 = time.monotonic()
    with urllib.request.urlopen(req, timeout=60) as resp:
        for raw in resp:
            line = raw.decode("utf-8").strip()
            if not line.startswith("data:") or line == "data: [DONE]":
                continue
            delta = json.loads(line[5:])["choices"][0].get("delta", {})
            if delta.get("content") or delta.get("tool_calls"):
                return int((time.monotonic() - t0) * 1000)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", default="git:777b5e0")
    ap.add_argument("--new", default=str(REPO / PROMPT_PATH))
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--env", default=str(DEFAULT_ENV))
    args = ap.parse_args()
    key = read_key(args.env)
    systems = {name: load_prompt(spec) + NOW + NOTE_ALONE
               for name, spec in (("old", args.old), ("new", args.new))}
    times = {"old": [], "new": []}
    questions = [c[1] for c in CASES if len(c) == 2][:10]
    for r in range(args.rounds):
        for i, q in enumerate(questions):
            # Alternate which prompt goes first, so neither always gets a warm connection.
            order = ("old", "new") if (r + i) % 2 == 0 else ("new", "old")
            for name in order:
                ms = first_token_ms(key, systems[name], q)
                if ms is not None:
                    times[name].append(ms)
    for name, ts in times.items():
        ts.sort()
        p95 = ts[max(0, int(len(ts) * 0.95) - 1)]
        print("%s  bytes %d  n %d  min %d  median %d  p95 %d ms" % (
            name, len(systems[name].encode()), len(ts), ts[0], statistics.median(ts), p95))


if __name__ == "__main__":
    main()
