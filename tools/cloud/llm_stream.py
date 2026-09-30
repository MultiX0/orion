# How soon can Orion start talking? Streams the chat completion over SSE, the
# way the board will, and measures what the non streaming call hides:
#
#   first token   when the first word of the reply exists
#   first clause  when the chunker would hand the first piece to TTS
#   complete      when the non streaming call would have returned
#
# Also proves the tool call path survives streaming: a look tool_call arrives in
# the deltas, and the board has to notice it there.
#
#   python tools/cloud/llm_stream.py
#   python tools/cloud/llm_stream.py --no-tools

import argparse
import json
import sys
import time
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
import chunker
import cloud_api as c

PROMPT_FILE = c.REPO / "firmware" / "assets" / "system_prompt.txt"

LOOK_TOOL = [{"type": "function", "function": {
    "name": "look",
    "description": "Take a picture with the camera and look at what is in front of "
                   "the device. Call this whenever the user asks about something "
                   "you can see.",
    "parameters": {"type": "object", "properties": {}}}}]

QUESTIONS = [
    "شو عاصمة الأردن؟",
    "احكيلي نكتة قصيرة",
    "What is the capital of France?",
    "شو بتعرف عن البترا؟",
    "شو شايف قدامك؟",
]


def stream_chat(messages, tools=None, max_tokens=200, sess=None):
    """Yields (event, value, ms) as the SSE stream arrives.

    event is "content" with a text delta, "tool" with a function name, or
    "done". Timing is from the moment the request is sent.
    """
    body = {"model": c.env("LLM_MODEL"), "messages": messages, "stream": True,
            "max_tokens": max_tokens, "temperature": 0.6}
    if tools:
        body["tools"] = tools
        body["tool_choice"] = "auto"
    http = sess or requests
    t0 = time.perf_counter()
    r = http.post(c.DEEPINFRA_URL, stream=True, timeout=60,
                  headers={"Authorization": "Bearer " + c.env("DEEPINFRA_API_KEY"),
                           "Content-Type": "application/json"},
                  data=json.dumps(body, ensure_ascii=False).encode("utf-8"))
    if r.status_code != 200:
        raise RuntimeError("deepinfra %d: %s" % (r.status_code, r.text[:200]))
    for raw in r.iter_lines():
        if not raw or not raw.startswith(b"data:"):
            continue
        data = raw[5:].strip()
        ms = (time.perf_counter() - t0) * 1000.0
        if data == b"[DONE]":
            yield "done", None, ms
            return
        # DeepInfra ends with a usage frame whose choices list is empty. The
        # board's parser has to skip it the same way.
        choices = json.loads(data).get("choices") or []
        if not choices:
            continue
        delta = choices[0].get("delta") or {}
        for call in delta.get("tool_calls") or []:
            name = (call.get("function") or {}).get("name")
            if name:
                yield "tool", name, ms
        if delta.get("content"):
            yield "content", delta["content"], ms


def measure(q, prompt, tools, sess):
    msgs = [{"role": "system", "content": prompt}, {"role": "user", "content": q}]
    first_tok = first_clause = tool_at = None
    text = ""
    ck = chunker.Chunker()
    for ev, val, ms in stream_chat(msgs, tools=tools, sess=sess):
        if ev == "tool" and tool_at is None:
            tool_at = ms
        elif ev == "content":
            if first_tok is None:
                first_tok = ms
            text += val
            if first_clause is None and ck.feed(val):
                first_clause = ms
        elif ev == "done":
            return {"first_tok": first_tok, "first_clause": first_clause or ms,
                    "done": ms, "tool": tool_at, "text": text,
                    "chunks": chunker.split_all(text)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-tools", action="store_true")
    ap.add_argument("--runs", type=int, default=2)
    ap.add_argument("--short-prompt", action="store_true",
                    help="a 300 byte prompt, to see what the 2.6 KB one costs")
    args = ap.parse_args()

    prompt = c.system_prompt()
    if args.short_prompt:
        prompt = ("You are Orion, a voice assistant in Amman. Answer in one or two short "
                  "spoken sentences. Reply in the user's language. Write numbers as words. "
                  "No markdown. Call the look tool when asked what you see.")
    tools = None if args.no_tools else LOOK_TOOL
    print("prompt %d bytes, tools %s, model %s" % (
        len(prompt.encode("utf-8")), "on" if tools else "off", c.env("LLM_MODEL")))
    sess = c.session()
    # One throwaway call so every measured run is on a warm socket, which is
    # what the board has after orion_cloud_prewarm.
    list(stream_chat([{"role": "user", "content": "hi"}], max_tokens=1, sess=sess))

    firsts, clauses, dones = [], [], []
    print("\n| question | first token | first clause | complete | chunks |")
    print("|---|---|---|---|---|")
    for q in QUESTIONS:
        for _ in range(args.runs):
            m = measure(q, prompt, tools, sess)
            if m["first_tok"] is None and m["tool"] is None:
                print("| %s | no content | | %.0f | |" % (q, m["done"]))
                continue
            if m["tool"] is not None:
                print("| %s | tool_call look at %.0f ms | | %.0f | |" % (q, m["tool"], m["done"]))
                continue
            firsts.append(m["first_tok"])
            clauses.append(m["first_clause"])
            dones.append(m["done"])
            print("| %s | %.0f | %.0f | %.0f | %d |" % (
                q, m["first_tok"], m["first_clause"], m["done"], len(m["chunks"])))
        print("|  | reply: %s | | | |" % m["text"].replace("\n", " ")[:90])

    med = lambda v: c.percentiles(v)[1]
    print("\nmedian: first token %.0f ms, first clause %.0f ms, complete %.0f ms" % (
        med(firsts), med(clauses), med(dones)))


if __name__ == "__main__":
    main()
