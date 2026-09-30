---
name: add-harness-tool
description: Add a tool the PC brain (or the phone brain) can call when the board hands it a turn, with the right safety tier, a spoken result, model routing, tests and a real try-out. Use when adding or changing a PC or phone capability, a web look-up for the brain, or anything in lib/features/harness that the model can call.
---

# Add a harness tool for the PC brain

The board sends a turn to the desktop app's tool server (`POST /v1/chat/completions` on port 7331). `PcBrain` runs it as an agent with the user's model, calls tools, and streams back only the words to speak. Read `docs/HARNESS.md` and the "PC and phone brain safety" rules in `AGENTS.md` first.

## 1. Decide what kind of tool it is

| The tool | Where it goes |
|---|---|
| Reads or acts on the PC (apps, windows, keys, files, settings) | a `ToolSpec` in `lib/features/harness/domain/tool_catalog.dart`, run by `ToolExecutor` |
| Only looks something up on the web, no PC state | `lib/features/harness/data/pc_web_tools.dart`, run inside `PcBrain` |
| Acts on the phone | `lib/features/harness/data/phone_brain_host.dart` |
| Uses the board itself (camera) | the board offers it in the request (`look`); the brain hands it back, nothing to add here |

Name it in `snake_case` with an underscore (`read_clipboard`, not `clipboard`): `withoutToolNames` strips only underscore names from spoken text, and the prompt tells the model never to say a tool's name.

## 2. Define it

For a PC tool, add a `ToolSpec` to `ToolCatalog` and put it in the `native` list (implemented on every desktop OS through `NativeTools`) or the `control` list (Windows desktop control through `DesktopControl`):

```dart
static const readClipboard = ToolSpec(
  name: 'read_clipboard',
  description: 'Read the text on the clipboard, when the user asks what they copied',
  safety: ToolSafety.confirm,
  parameters: <String, dynamic>{'type': 'object', 'properties': <String, dynamic>{}},
);
```

- The description is for the model: when to use it, in one or two sentences, with the words the user would say. Argument descriptions give an example value.
- Pick the tier honestly. `safe` runs at once and must not be able to lose data or show private content. Anything that runs commands, types, presses keys, reads private content, or changes files or settings is `confirm`. `always` is for open-ended agent work.
- `ToolCatalog.available` decides what `GET /tools` offers; a tool this machine cannot run must not be offered.

## 3. Implement it

- `native` tool: add the method to `NativeTools` (`domain/native_tools.dart`) and implement it in `data/native_tools/windows_tools.dart`, `linux_tools.dart` and `unsupported_tools.dart`, plus `test/support/stub_tools.dart`. Run processes through `ProcessRunner` so a child that hangs is killed on timeout, and never pass a raw string from the model to a shell.
- `control` tool: add the method to `data/native_tools/desktop_control.dart`.
- Dispatch it in `ToolExecutor._run` (`data/tool_executor.dart`), returning `call.copyWith(status: HarnessCallStatus.done, result: said)`. Throw `NativeToolException` with a sentence the user can hear for expected failures.
- Web tool: add a spec to `PcWebTools.specs`, a method on `PcWebTools`, and a branch in `PcBrain._tool`. Keyless services only, with a timeout.
- Phone tool: add a `ToolSpec` next to `openLink` and a branch in `PhoneBrainHost._run`.

The result string is what the model reads and then speaks from: short, plain, already in words. Never return paths, command lines, raw JSON, code or long lists; summarize ("Three files match, the newest is Budget from Monday").

## 4. Route it

`PcBrain._lookUps` lists the tools that only look something up. The fast model may call those itself. Any other tool call moves the turn to the thinking model before it runs, because a fast model claimed actions it never checked. Add your tool to `_lookUps` only if it cannot change anything. For an action tool, return enough in the result for the model to check that it worked (what the window shows now, what is playing).

## 5. Show it

Add a line to `toolDescription` in `lib/features/harness/presentation/tool_copy.dart`, so the feed and the confirmation card say what the call does. Add the tool to the tables in `docs/HARNESS.md` with its tier.

## 6. Test

```
flutter test test/features/harness
```

- Executor and tier: see `tool_server_test.dart` and `approval_mode_test.dart`; a `confirm` tool must wait for approval in `ask` mode and run at once in `auto`.
- OS output parsing: record real output into `test/fixtures/` and parse it in a unit test (`windows_tools_test.dart`, `stats_parsers_test.dart`). No personal paths or names in fixtures.
- Routing: `pc_brain_test.dart` shows how to assert a look-up stays on the fast model and an action moves to the thinking one, and that a tool name never reaches the spoken answer.

Then `flutter analyze`, `dart format .`.

## 7. Try it for real

These act on the machine you run them on. Ask first.

```
dart run tool/pc_brain_probe.dart "What did I copy?"           # the brain against the real model, stand-in PC tools
dart run tool/native_tools_check.dart stats                     # fire one native tool and print the result
dart run tool/pc_harness.dart <board ip>                        # the real PC side for a real board, no window
dart run tool/brain_eval.dart google/gemma-4-31B-it-turbo --thinking=zai-org/GLM-5.3-Flash
```

`pc_brain_probe.dart` offers only two stand-in tools; extend its catalog locally if you need yours in the loop, or run the desktop app with PC control on. `brain_eval.dart` drives real apps (Spotify plays, Chrome opens) and checks the screen, and writes `logs/eval/<model>.txt`. The keys come from `.env` and are never printed. Through a board, test with typed turns at volume 0: `python tools/cloud/console_session.py --out logs/pc.txt "vol 0" "ask <request>"`.

Report the tier you chose and why, the test results, and what the tool said in a real run.
