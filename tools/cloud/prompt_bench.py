# System prompt measurements, driven from loop_test.py.
#
#   --prompt-bench A.txt B.txt   LLM time to first token, prompts interleaved
#   --questions                  the 15 question set through the full loop,
#                                replies logged verbatim with the speech checks
#
# Streaming per docs.deepinfra.com/chat/streaming: "stream": true, SSE lines
# "data: {...}" with choices[0].delta.content, ending "data: [DONE]"; the last
# chunk before [DONE] carries usage.

import json
import time
from pathlib import Path

import cloud_api as c
import prompt_test as pt

ARABIC = [
    "ما عاصمة الأردن؟",
    "كم الساعة الآن؟",
    "كيف حال الطقس اليوم؟",
    "ماذا تعرف عن مدينة البتراء؟",
    "أخبرني نكتة قصيرة.",
    "شغّل أغنية على Spotify.",
    "ما أفضل طريقة لتعلم البرمجة؟",
    "كم عدد سكان الأردن تقريباً؟",
    "ما اسمك؟ وما أنت بالضبط؟",
    "ماذا ترى أمامك الآن؟",
]
ENGLISH = [
    "What is the capital of Jordan?",
    "How do I restart a stuck ESP32?",
    "Tell me a very short joke",
    "What are you, exactly?",
    "Explain what PSRAM is in one line",
]
BENCH = ARABIC  # the same ten questions for every prompt

# The tool the firmware offers on every first request, see cloud_reply.c.
LOOK_TOOL = [{"type": "function", "function": {
    "name": "look",
    "description": "Take a picture with the camera and look at what is in front of the "
                   "device. Call this whenever the user asks about something you can see.",
    "parameters": {"type": "object", "properties": {}}}}]


def chat_stream(messages, sess, max_tokens=200, temperature=0.6, timeout=60):
    """Returns (text, ttft_ms, total_ms, usage)."""
    body = {"model": c.env("LLM_MODEL", "google/gemma-4-31B-it-turbo"),
            "messages": messages, "max_tokens": max_tokens,
            "temperature": temperature, "stream": True,
            "tools": LOOK_TOOL, "tool_choice": "auto"}
    headers = {"Authorization": "Bearer " + c.env("DEEPINFRA_API_KEY"),
               "Content-Type": "application/json"}
    t0 = time.perf_counter()
    r = sess.post(c.DEEPINFRA_URL, headers=headers, stream=True, timeout=timeout,
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"))
    if r.status_code != 200:
        raise RuntimeError("deepinfra %d: %s" % (r.status_code, r.text[:200]))
    text, ttft, usage = "", None, {}
    for line in r.iter_lines(decode_unicode=False):
        if not line.startswith(b"data:"):
            continue
        data = line[5:].strip()
        if data == b"[DONE]":
            break
        chunk = json.loads(data.decode("utf-8"))
        usage = chunk.get("usage") or usage
        for ch in chunk.get("choices", []):
            delta = ch.get("delta") or {}
            piece = delta.get("content") or ""
            if delta.get("tool_calls"):
                piece = piece or "<look>"   # a tool call is the model's first token too
            if piece and ttft is None:
                ttft = (time.perf_counter() - t0) * 1000.0
            text += piece
    total = (time.perf_counter() - t0) * 1000.0
    return text.strip(), ttft or total, total, usage


def bench(files, sess, runs=2):
    prompts = [(Path(f).name, c.system_prompt(path=Path(f))) for f in files]
    stats = {name: {"ttft": [], "total": [], "ptok": 0} for name, _ in prompts}
    for _ in range(runs):
        for q in BENCH:
            for name, prompt in prompts:   # interleaved so drift hits both alike
                _, ttft, total, usage = chat_stream(
                    [{"role": "system", "content": prompt}, {"role": "user", "content": q}], sess)
                stats[name]["ttft"].append(ttft)
                stats[name]["total"].append(total)
                stats[name]["ptok"] = usage.get("prompt_tokens", 0)
    print("\n| prompt | bytes | prompt tokens | ttft min | ttft median | ttft p95 | total median | n |")
    print("|---|---|---|---|---|---|---|---|")
    for name, prompt in prompts:
        s = stats[name]
        lo, med, p95, _ = c.percentiles(s["ttft"])
        print("| %s | %d | %d | %.0f | %.0f | %.0f | %.0f | %d |" % (
            name, len(prompt.encode("utf-8")), s["ptok"], lo, med, p95,
            c.percentiles(s["total"])[1], len(s["ttft"])))


def questions(sess, one_turn, out):
    """The 15 question set through the real loop: typed turn, LLM, TTS."""
    rows = []
    for i, q in enumerate(ARABIC + ENGLISH, 1):
        row = one_turn(None, sess, [], typed_text=q, tools=LOOK_TOOL)
        if row.get("tool_call"):
            print("\nQ: %s\nA: <calls %s>   llm %.0f ms" % (q, row["tool_call"], row["llm_ms"]))
            continue
        problems = pt.check(q, row["reply"])
        if row.get("pcm"):
            c.save_wav(out / ("q%02d.wav" % i), row["pcm"])
        rows.append(row)
        print("\nQ: %s\nA: %s\n   llm %.0f ms  ttfb %.0f ms  speak %.1f s  tags %s  %s" % (
            q, row["reply"], row["llm_ms"], row["tts_first_ms"], row["speak_s"],
            ",".join(pt.tags_in(row["reply"])) or "none",
            ("PROBLEM: " + ", ".join(problems)) if problems else "clean"))
        row["problems"] = problems
    clean = sum(1 for r in rows if not r["problems"])
    spk = [r["speak_s"] for r in rows]
    print("\n%d of %d clean, median reply %d chars, median spoken %.1f s, max %.1f s" % (
        clean, len(rows), c.percentiles([len(r["reply"]) for r in rows])[1],
        c.percentiles(spk)[1], max(spk)))
