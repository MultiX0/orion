# CLAUDE.md

Read `AGENTS.md` first. It is the source of truth for this repo: what Orion is, how to build, flash and test each part, code style, commits, the hard rules and the reasons behind the design. This file only adds what is specific to Claude Code.

## What is set up for you

- `.claude/agents/`: focused subagents. `firmware` for anything under `firmware/` and `tools/`, `app` for the Flutter app, the mock and the PC brain, `docs` for documentation, `reviewer` for a read-only review of a change against the rules in `AGENTS.md`.
- `.claude/skills/`: step by step workflows. `flash-firmware`, `add-console-command`, `add-app-feature`, `add-harness-tool`, `tune-system-prompt`, `cut-release`.
- `.claude/rules/`: path rules that load when you work in `firmware/`, `lib/` and `test/`, the harness, the protocol files, `wakeword/` and `tools/`.
- `.mcp.json`: two Fish Audio servers. `fish-audio` searches the Fish documentation; check any Fish endpoint, header or field there before relying on memory. `fish-audio-api` can generate speech, transcribe and search voices after an OAuth sign-in, and bills the account's package credits. It is a development tool only: the board cannot speak MCP and always uses the REST API.
- `.worktreeinclude` copies `.env` into new worktrees, so dev scripts work there. The copy is gitignored like the original.

## Working here with Claude Code

- Never run `idf.py monitor` or anything else that holds the serial port open without an end. Use `tools/serial_capture.py --seconds N`, `tools/cloud/console_session.py` or `tools/board_session.py`, which exit on their own and share the board lock.
- Ask before flashing a board or playing sound. Flash the app partition only unless told otherwise, and send `volume 0` before tests that do not need sound.
- On Windows the Bash tool is Git Bash. Run the board scripts as `powershell -ExecutionPolicy Bypass -File tools\idf.ps1 build` (the script clears the MSYS variables ESP-IDF rejects). Set `PYTHONIOENCODING=utf-8` for any Python that prints Arabic.
- Deep worktree paths break two builds on Windows: the firmware (build with `tools\idf.ps1 -B C:\<short> build`) and the Windows app (MSB3491, build from a short checkout).
- Never print, echo or log a key or a pairing token, even to check it. Print its length.
- Long-running jobs (wake word training) go in a detached `tmux` inside WSL, not in the foreground of a tool call.
- Before a commit: `flutter analyze`, `dart format .` and `flutter test` for app changes; a clean `idf.py build` for firmware changes. No em dashes and no emojis, in code or in commit messages.
