# Asks the chat model the fixed questions in cases.py under two system prompts
# and writes the replies side by side to tools/voice_eval/out/. Text only: no
# text to speech, nothing is played.
#
#   python tools/voice_eval/voice_eval.py
#   python tools/voice_eval/voice_eval.py --old git:777b5e0 --samples 2
#
# A prompt is a file path, or git:<rev> for firmware/assets/system_prompt.txt
# at that commit. The key is read from the repo .env and never printed.

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cases import CASES, LOOK_TOOL, NOTE_ALONE, NOW

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
PROMPT_PATH = "firmware/assets/system_prompt.txt"
DEFAULT_ENV = Path(r"C:\Users\multix\Desktop\Dev\yt-projects\orion\.env")
URL = "https://api.deepinfra.com/v1/openai/chat/completions"
MODEL = "google/gemma-4-31B-it-turbo"

TAG = re.compile(r"\[[^\]]*\]")
SENTENCE_END = ".!?\u061f\n"


def read_key(env_path):
    for line in Path(env_path).read_text(encoding="utf-8").splitlines():
        name, _, value = line.partition("=")
        if name.strip() == "DEEPINFRA_API_KEY":
            return value.strip().strip('"').strip("'")
    sys.exit("DEEPINFRA_API_KEY is not in %s" % env_path)


def load_prompt(spec):
    if spec.startswith("git:"):
        rev = spec[4:]
        out = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (rev, PROMPT_PATH)],
                             capture_output=True, check=True)
        return as_sent(out.stdout.decode("utf-8"))
    return as_sent(Path(spec).read_text(encoding="utf-8"))


def as_sent(prompt):
    """What the board sends with Fish: the <fish> marker lines go."""
    return re.sub(r"^</?fish>\n", "", prompt, flags=re.M)


def allowed_tags(prompt):
    # An old prompt listed its tags one per line, each line starting with the
    # tag. The current one lists none there: Fish cues are free text.
    return {m.group(0) for m in re.finditer(r"(?m)^\[[a-z ]+\]", prompt)}


def ask(key, system, case):
    history = case[2] if len(case) > 2 else []
    messages = [{"role": "system", "content": system}]
    for user, reply in history:
        messages += [{"role": "user", "content": user}, {"role": "assistant", "content": reply}]
    messages.append({"role": "user", "content": case[1]})
    body = {"model": MODEL, "messages": messages, "max_tokens": 200, "temperature": 0.6,
            "tools": LOOK_TOOL, "tool_choice": "auto"}
    req = urllib.request.Request(URL, data=json.dumps(body).encode("utf-8"), headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    t0 = time.monotonic()
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode("utf-8"))
            break
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == 2:
                return {"text": "<error: %s>" % type(e).__name__, "ms": 0, "tokens": 0}
            time.sleep(2)
    msg = data["choices"][0]["message"]
    text = msg.get("content") or ""
    if msg.get("tool_calls"):
        text = (text + " <calls %s>" % msg["tool_calls"][0]["function"]["name"]).strip()
    return {"text": text.strip(), "ms": int((time.monotonic() - t0) * 1000),
            "tokens": data.get("usage", {}).get("prompt_tokens", 0)}


def flags(text, allowed):
    out = []
    # Fish S2 cues are free natural language and go anywhere, a trailing
    # [laugh] included (the chunker keeps it with its sentence). What still
    # breaks: two cues side by side, and a cue not in English.
    for m in TAG.finditer(text):
        tag = m.group(0)
        if allowed and tag not in allowed:
            out.append("off-list " + tag)
        if re.search(r"[^\x20-\x7e]", tag):
            out.append("non-English cue " + tag)
    if re.search(r"\]\s*\[", text):
        out.append("stacked cues")
    spoken = TAG.sub("", text)
    if re.search(r"[^\s؀-ۿ -~ -ɏ -⁯]", spoken):
        out.append("foreign script")
    if re.search(r"[0-9\u0660-\u0669]", re.sub(r"[A-Za-z]+[0-9]+|[0-9]+[A-Za-z]+", "", spoken)):
        out.append("digits")
    if re.search(r"[*#`_()]|^\s*-\s", spoken, re.M):
        out.append("markup")
    for bad in ("لكِ", "يمكنكِ", "أقوم ب", "قمت ب", "قمتُ ب", "تم ", "هل تريد مني"):
        if bad in spoken:
            out.append("says " + bad)
    return out


def spoken_len(text):
    return len(TAG.sub("", text).strip())


def run(key, name, system, samples, pool):
    jobs = [(c, s) for c in CASES for s in range(samples)]
    results = list(pool.map(lambda job: ask(key, system, job[0]), jobs))
    by_case = {}
    for (case, _), r in zip(jobs, results):
        by_case.setdefault(case[0], []).append(r)
    print("%s: %d replies" % (name, len(results)))
    return by_case


def md(text):
    return text.replace("\n", " / ")


def write_report(path, prompts, answers, samples):
    old_p, new_p = prompts
    lines = ["# Voice eval, %s" % datetime.now().strftime("%Y-%m-%d %H:%M"), "",
             "Model %s, temperature 0.6, max_tokens 200, look tool offered, %d sample(s) per "
             "question. System prompt plus the board's clock line and the no PC note." % (MODEL, samples),
             "", "| | old | new |", "|---|---|---|",
             "| prompt chars | %d | %d |" % (len(old_p), len(new_p)),
             "| prompt bytes | %d | %d |" % (len(old_p.encode()), len(new_p.encode()))]
    stats = []
    for p, a in zip(prompts, answers):
        rs = [r for rows in a.values() for r in rows]
        allowed = allowed_tags(p)
        tagged = sum(1 for r in rs if TAG.search(r["text"]))
        flagged = sum(1 for r in rs if flags(r["text"], allowed))
        lens = sorted(spoken_len(r["text"]) for r in rs)
        ms = sorted(r["ms"] for r in rs)
        stats.append((max(r["tokens"] for r in rs), tagged, len(rs), flagged, lens[len(lens) // 2],
                      lens[-1], ms[len(ms) // 2]))
    rows = [("prompt tokens", 0), ("replies tagged", 1), ("replies flagged", 3),
            ("median spoken chars", 4), ("longest spoken chars", 5), ("median request ms", 6)]
    for label, i in rows:
        vals = [("%d/%d" % (s[i], s[2]) if i in (1, 3) else str(s[i])) for s in stats]
        lines.append("| %s | %s | %s |" % (label, vals[0], vals[1]))
    lines.append("")
    allowed = [allowed_tags(p) for p in prompts]
    for case in CASES:
        lines += ["## %s" % case[0], "", "**Q:** %s" % case[1], ""]
        for label, a, allow in (("old", answers[0], allowed[0]), ("new", answers[1], allowed[1])):
            for r in a[case[0]]:
                f = flags(r["text"], allow)
                lines.append("- **%s:** %s%s" % (label, md(r["text"]), ("  `%s`" % ", ".join(f)) if f else ""))
        lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", default="git:777b5e0")
    ap.add_argument("--new", default=str(REPO / PROMPT_PATH))
    ap.add_argument("--samples", type=int, default=1)
    ap.add_argument("--env", default=str(DEFAULT_ENV))
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    key = read_key(args.env)
    prompts = [load_prompt(args.old), load_prompt(args.new)]
    with ThreadPoolExecutor(max_workers=6) as pool:
        answers = [run(key, name, p + NOW + NOTE_ALONE, args.samples, pool)
                   for name, p in (("old", prompts[0]), ("new", prompts[1]))]
    out_dir = HERE / "out"
    out_dir.mkdir(exist_ok=True)
    path = Path(args.out) if args.out else out_dir / ("report_%s.md" % datetime.now().strftime("%Y%m%d_%H%M%S"))
    write_report(path, prompts, answers, args.samples)
    print("wrote", path)


if __name__ == "__main__":
    main()
