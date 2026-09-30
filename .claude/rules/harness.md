---
paths:
  - "lib/features/harness/**"
  - "test/features/harness/**"
  - "tool/pc_harness.dart"
  - "tool/pc_brain_probe.dart"
  - "tool/brain_eval.dart"
  - "tool/native_tools_check.dart"
  - "tool/dsh_e2e.dart"
  - "harness/**"
---

# PC and phone brain rules

Read `docs/HARNESS.md` and the `add-harness-tool` skill before adding or changing a tool.

- Every tool has a tier in `ToolCatalog`: `safe` runs at once, `confirm` asks the first time, `always` asks every time. Anything that runs commands, types, presses keys, reads private content or changes files or settings is `confirm` or stricter. Never hand a raw string from the model to a shell.
- The board's `pc.approval` (`ask` or `auto`) decides; the desktop's copy is only for when the board is away. Every call is logged to `~/Orion/logs/tools.jsonl` with who approved it.
- Tool results are short spoken sentences in the user's language: no paths, commands, code, URLs, JSON or long lists. Tool names never reach the voice (`withoutToolNames`); name new tools in `snake_case` with an underscore.
- Only pure look-ups belong in `PcBrain._lookUps`. Any other call moves the turn to the thinking model before it runs.
- The reply stream is read by the board 128 bytes at a time: it starts with an empty `role` event, keep-alives are SSE comments padded to 128 bytes at least every 3 s, a spoken filler has at least 15 letters and is followed by a keep-alive, and model control tokens are dropped. A PC with no model, a bad key or no internet answers 503 before streaming so the board falls back.
- dsh runs only in `~/Orion/agent` with its own `DSH_HOME`, its key through an env file, never on a command line.
- The tool scripts in `tool/` act on the real machine (apps open, music plays). Ask before running them; keys come from `.env` and are never printed.
