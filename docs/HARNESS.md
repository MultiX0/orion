# The harness: PC control and the extended brain

The harness is what lets Orion think with the help of a PC or a phone, and act on the PC. It lives in the app, in `lib/features/harness/`.

On a **Windows PC**, with PC control on, the Orion app runs a small server on the LAN. The board sends every turn there first. The app answers it as an agent: the model and key picked in the app, the date and time, the web, a memory of the conversation, and real control of the PC. Only the spoken answer goes back, and the board says it in Orion's voice.

On a **phone**, while the app is open and linked, the same server and brain answer the board's turns with the phone's model and key, the web, a memory, and one tool: opening links and apps on the phone.

The board stays the voice in both cases: it wakes, listens, shows the star and speaks. If neither brain answers, it answers with its own model. See [ARCHITECTURE.md](ARCHITECTURE.md#where-the-answer-is-written) for the routing and [DEVICE_PROTOCOL.md](DEVICE_PROTOCOL.md#board-to-brain) for the wire format.

## Turning it on

PC control has three settings, the same control on the desktop (the Hands step in onboarding, Settings, the Harness screen header) and on the phone (Settings):

| Choice | Means |
|---|---|
| **Off** | No server on the PC. The board never calls it. |
| **Ask me first** | Safe tools run at once; anything that could lose data, show the screen or type into an app waits for you on the PC. |
| **Act on your own** | Every tool runs the moment the brain asks, agent tasks included. Every call is still logged. |

The choice lives on the board (`pc.enabled`, `pc.approval`), so the phone, the PC and the board always agree; the desktop keeps a copy for when the board is away and reloads it from the board. Choosing it on the phone changes the board, and the PC follows.

When PC control goes on, the desktop app:

1. Starts the tool server on `0.0.0.0:7331`. If the port is still held by the app's own previous server it retries briefly; if another program has it, it moves to the next free port up to 7339.
2. On Windows, checks for the firewall rule **"Orion PC brain"** and, when it is missing, raises Windows' own consent prompt once. On Yes it removes any Block rules on the app's executable (a dismissed firewall prompt leaves one, and a Block rule beats every Allow rule) and allows TCP 7331 to 7339 from the local subnet only. Say No and PC control stays off, with a message saying so.
3. Tells the board where it is with `POST /api/config`: `pc.enabled`, `pc.base_url`, `pc.token` and `pc.approval`. The address is the local adapter on the board's own subnet, found from the local end of a TCP connection to the board, never a Hyper-V, WSL or VirtualBox adapter unless there is nothing else. The Harness header shows the address the board was told.

The server starts with the app when PC control was on at exit (it is up about 2 s after launch) and retries for half a minute if the network is not ready yet. A second Orion window brings the first to the front instead of starting another server.

## The tool server

`lib/features/harness/data/tool_server.dart`, shelf. Every request needs the pairing token (`X-Orion-Token`, a bearer, or `?token=`); with nothing paired yet it refuses everything.

| Endpoint | Used by |
|---|---|
| `GET /tools` | the board's health check, and anything that wants the tool list |
| `POST /v1/chat/completions` | the board's turns: the PC brain |
| `POST /tool`, `GET /tool/<id>` | direct tool calls (the mock board, the tests, `tool/pc_harness.dart`) |
| `GET /ws` | `tool.update` and `agent.log` events for direct calls |

## The PC brain

`lib/features/harness/data/pc_brain.dart`. The board's chat request comes in; an agent loop runs; only the words to speak go back as OpenAI SSE.

The board's own system prompt arrives already cut for its text to speech: with Fish it holds the voice tag rules, so a PC or phone answer carries the same `[laugh]`, `[sigh]` or `[pause]` cues as the board's own model; with any other voice it holds none and asks for no brackets. The brains add no tag rules of their own. What the model is given on top of it:

- Where it runs: this PC's name and OS (or "the user's phone"), the local date, time with the part of the day, and the UTC offset.
- How to speak about tool results: one or two short sentences, in the language of the user's last message even when the results are in another, metric units, never file paths, commands, code, URLs, JSON or long lists, never the name of a tool or how it checked ("I checked with ui_look" became "The calculator is open."). If something waits for approval, ask the user to approve it on the PC screen.
- How to act: do the task instead of describing it; a step is not the result (an opened search is not a song playing); check it worked before saying so (`ui_look`, `open_windows`, `media status`) and try another way if not; every action needs its tool call in this turn, even if it was done before; only the last message is the task.
- The apps with a window open right now (up to 15), the actions of the last 6 hours with how long ago, and the last 10 turns of the last 12 hours from the memory, with their tool calls replayed as tool calls.
- A last line naming the language to answer in, taken from the letters of what was heard: any Arabic words make it Arabic.

The tools are the PC's own (below), the web tools, and the board's `look`, which goes back to the board as a normal tool call so it takes the picture.

How a turn runs:

- It starts on the **fast model** (the provider's model, 600 tokens). If it only answers or looks something up (`web_search`, `fetch_page`, `weather`, `open_windows`, `system_stats`, `ui_look`), it finishes there.
- The moment the fast model calls a tool that acts, that round is dropped unrun and the turn moves to the **thinking model** (the provider's thinking model, 4000 tokens, with `reasoning_effort` when set), which plans the task from the request itself.
- Up to 14 rounds of tool calls (opening an app, looking, typing, looking again and clicking is five on its own) and 90 s of work, then it answers with what it has.
- A tool still waiting for approval after 20 s is reported to the model as waiting, so the board hears that it is waiting rather than silence.
- Before answering right after acting, without having looked at the result, the model is asked once to check and to keep going if it is not done.
- Out of rounds or time, one last request without tools asks for a summary, with the list of what was done this turn. Only the last round's words are spoken; a round that went on to call tools was the model thinking aloud.
- The first model request is made before anything is sent back. A PC with no model set up, a bad key or no internet answers 503, and the board answers with its own model.

What the board hears while it works:

- An empty opening event first, so the first word is not lost to the board's HTTP client.
- "One moment, I'm on it." (or "لحظة من فضلك، أعمل على ذلك.") the moment a turn becomes a task, or after 8 s on an everyday answer. Fillers are 15 letters or more, because the board's chunker holds a shorter first piece for the words after it.
- A keep-alive every 3 s: an SSE comment padded to 128 bytes, one full board read, so it is read at once and restarts the board's 30 s deadline.
- Model control tokens (`<turn|>`, `<|im_end|>`) and tool names are dropped from the spoken text.

Measured through the board, Gemma answering: the time in about 1 s to the first word, today's date, a web search or a PC tool in 4 to 6.5 s.

### Memory

`lib/features/harness/data/pc_memory.dart`. The PC keeps every turn and the actions it took in `%APPDATA%\Orion\pc_memory.json` (`~/.config/Orion/pc_memory.json` on Linux), the last 200. While the PC answers, this replaces the board's own short history. It is how a short request lands in the right app: "play Lifetime by Chris Grey" an hour after "open Spotify" goes to Spotify, "pause it" pauses, "what song is playing" reads the media session.

Three rules in the context each come from a measured failure: every action needs its tool call in this turn (the model answered "Spotify is already open" from memory when it had been closed); the windows list is the truth about what is open, the memory can be stale; and past turns come back with their tool calls and results, not as words (replayed as "Close Chrome." then "Closed Chrome.", the model learnt that saying so was the whole answer, and said it the next time without closing anything).

## Tools

`GET /tools` offers only what this machine can do. `safe` runs at once; `confirm` asks the first time in a session, with "always allow this session" on the card; `always` asks every time. Under "Act on your own" nothing asks.

### Native tools

| Tool | Tier | Does, on Windows |
|---|---|---|
| `open_app` | safe | Opens an app by name: an alias map (`spotify:` and friends), then `where`, then Start Menu shortcuts by name under the user's and the machine's `Start Menu\Programs`. Never hands an unknown name to `start`, which opens the "How do you want to open this file" dialog and blocks. Waits for the app's window. 0.2 to 0.6 s. |
| `system_stats` | safe | CPU, RAM, GPU load and temperature through CIM and `nvidia-smi`. About 3 s, most of it CIM. |
| `media` | safe | play, pause, play_pause, next, previous and **status** through Windows' media session (so it knows what is playing and whether it is paused); volume up, down and mute through media keys. |
| `lock_pc` | confirm | `LockWorkStation`. |
| `screenshot` | confirm | Captures the whole virtual desktop (about 1.8 MB of PNG), sends it to the chosen model with "describe what's on screen", and returns only the sentence. The board never sees the image. |
| `search_files` | confirm | File names in Documents, Downloads and Desktop, through the Windows Search index (`Search.CollatorDSO`, folders excluded) in about 0.5 s; a bounded walk (depth 4, 10 hits, 6 s) when indexing is off. |

### Control of any app (Windows)

`lib/features/harness/data/native_tools/desktop_control.dart`, through PowerShell, UI Automation and WScript. Nothing to install.

| Tool | Tier | Does |
|---|---|---|
| `open_link` | safe | Opens a web address, a file or an app link: `spotify:track:<id>` plays a song, `spotify:search:<words>` searches Spotify, `ms-settings:bluetooth`, `mailto:`. |
| `close_app` | safe | Closes every window of an app the way its close button does (an app with unsaved work still asks). Never closes Orion. |
| `focus_app` | safe | Brings an app to the front. |
| `open_windows` | safe | The apps with a window and what each shows ("Spotify: Chris Grey - LIFETIME"). |
| `ui_look` | safe | An app's buttons, fields, list items, links, tabs and menu items by name, in window order. A list row's text comes first ("Row: 9 Play Blinding Lights by The Weeknd ... 3:20"), and a name that repeats is numbered ("Play Blinding Lights #2"), because Spotify has that button for every cover. |
| `ui_act` | confirm | Clicks, types into or focuses a control `ui_look` named, by name and number. Waits for the app, then says what the window in front shows now. |
| `press_keys` | confirm | Keys to the window in front ("ctrl+l", "enter", several separated by commas). |
| `type_text` | confirm | Types text into a named app or the one in front, by pasting, so Arabic types too. |
| `run_powershell` | confirm | A PowerShell command, for anything no other tool does. Returns what it printed. |

`press_keys`, `type_text` and `ui_act` refuse when Orion's own window is in front, so a focus that did not take can never send alt+f4 to Orion. `ui_act`, `press_keys` and `type_text` end with what the window in front shows now, the first check that a step worked.

### Web

`lib/features/harness/data/pc_web_tools.dart`, no API keys:

| Tool | Does |
|---|---|
| `web_search` | DuckDuckGo's HTML results; Brave's when DuckDuckGo answers a burst of automated searches with a challenge; Wikipedia's search when both come back empty |
| `fetch_page` | one page as plain text |
| `weather` | Open-Meteo, now and the next two days, for a named place in English letters or where the device is. About 1 s. A weather question through web search had come back empty after 17 s. |

### Agent tasks (optional)

`agent_task` (tier `always`) hands a multi-step task to DeepSeek Harness (`dsh`), an open source agent runtime, when Node and dsh are installed. It is offered only when the probe finds them, and the app never depends on it to start.

- Needs Node `^22.19.0` or `>=24`. The probe runs `node --version`, then `npx -y @deepseek-ai/dsh --version` with 60 s (a first run downloads the package). A timeout means "not available".
- Runs `npx -y @deepseek-ai/dsh --profile headless "<task>"` in `~/Orion/agent` with `DSH_HOME=~/Orion/agent/.dsh`, `DSH_PERMISSION_MODE=workspace-write` and `DSH_TELEMETRY_MODE=DISABLED`. It never touches the user's own `~/.dsh`.
- `DshConfigWriter` writes `settings.yaml` (the provider and model chosen in the app) and a `.env` with `DP_ORION_KEY` (mode 0600 on POSIX). The key is never a command-line argument.
- To watch one run end to end: `DP_ORION_KEY=<key> dart run tool/dsh_e2e.dart --base-url https://api.deepinfra.com/v1/openai --model deepseek-ai/DeepSeek-V3.2`. It asks dsh to create `hello.txt` in the agent folder and checks it landed (about 16 s).

With the thinking model driving the UI tools, most tasks no longer need dsh.

### On Linux

The native tools exist (`xdg-open` and `.desktop` lookup, `loginctl lock-session`, `/proc` and `nvidia-smi`, `grim` or `scrot`, `playerctl`) and are covered by fixture tests. The control tools are Windows only, and the Linux build has not been run.

## Approvals and the log

- A call waiting under "Ask me first" shows as a card on the Harness screen with the tool and its arguments; approve, approve for this session, or deny. The board hears "denied by user" on a deny. There is no system notification; keep the Harness screen in view when approvals matter.
- Every call is written to `~/Orion/logs/tools.jsonl`: time, tool, arguments, status, result, the mode it ran under and who let it through (`approved_by`: `user`, `session` for "always allow this session", `policy` for "Act on your own").
- The server listens on the LAN but answers only the paired token, and the firewall rule allows only the local subnet.
- `run_powershell` and `agent_task` are the only ways to a shell. Both are in the asking tiers, and "Act on your own" deliberately includes them: choose it only on a PC you are happy for Orion to drive.

## The phone as a brain

`lib/features/harness/data/phone_brain_host.dart`. While the app runs on a phone and holds its link, it serves the same brain on port 7331 of the phone and tells the board through its `/ws` link (`brain=<host>:<port>`). It uses the phone's own model and key, the web tools, the date and time, and a memory in the app's support folder (`memory.json`, the same format as the PC's). Its one tool is `open_link`: a web address, a `spotify:` link, `geo:0,0?q=<place>`, `mailto:`.

- Order: the PC first when it is on and answering, then the phone, then the board's own model.
- **Android** runs a foreground service ("Orion is thinking on this phone") so the brain keeps answering while another app has the screen. Without it, "open YouTube" froze the app, the link went quiet after 15 s, and the next turn lost the phone and what it remembered.
- **iOS** does not allow that: the phone brain answers while the app is open.
- An Android emulator sits behind its own NAT. To test there: build with `--dart-define=ORION_BRAIN_ADDR=<pc ip>:7331`, run `adb forward tcp:7341 tcp:7331`, relay the PC's port 7331 to 127.0.0.1:7341, and keep the desktop app closed so the port is free.

## Choosing the models: a fast one to answer, a thinking one to act

The brain was tested on plain requests with no recipe per app ("play Blinding Lights by The Weeknd on Spotify", "open Chrome and search for the best shawarma in Amman"), by what happened on the screen, not by what the model said.

`dart run tool/brain_eval.dart <model> [reasoning_effort] [--thinking=<model>]` runs seven requests against the real apps on the PC with the board's own prompt, approval mode "act on your own", and checks the result: Spotify's window title for the song and the artist, Chrome's title for the search, no Chrome window after "close Chrome", an Arabic song request, a number in "what will the weather be in Irbid tomorrow", and the Calculator's display reading 5888 after "افتح الآلة الحاسبة واحسب ١٢٨ ضرب ٤٦". It logs every tool call and which model finished each task. A free Spotify account can start an ad mid task; that is part of the test.

One model doing everything:

| Model | Tasks | Notes |
|---|---|---|
| `google/gemma-4-31B-it-turbo` | 4/7, later 6/7 | Never checks. Played a cover and said it was The Weeknd; the Calculator showed 5888 and it said 5928 aloud. |
| gpt-oss-120b | 2/7 | Gave up, or described the steps instead of doing them. |
| MiMo-V2.6-Flash | 5/7 in 614 s | Too slow for a voice turn. |
| Qwen3.8-Flash | 6/7 in 297 s | No vision; kept going back to an earlier failed task. |

Gemma is too weak to act on its own: it reports success it never checked. It stays the fast model because it answers quickly, sees pictures and speaks good Arabic. On DeepInfra it was also the only Gemma 4 variant fast enough for a voice loop that also calls tools and sees: E4B has no vision, the 26B A4B was 3.9 s median in Arabic, the plain 31B took 35 s on a picture.

Thinking models, each paired with Gemma the way the app runs them, two runs each:

| Thinking model | $/M in, out | Vision | Run 1 | Run 2 | Time for 7 tasks |
|---|---|---|---|---|---|
| **zai-org/GLM-5.3-Flash** | 0.15, 0.50 | yes | 6/7 | 7/7 | 147 s, 100 s |
| deepseek-ai/DeepSeek-V4-Flash | 0.09, 0.18 | no | 6/7 | 6/7 | 215 s, 193 s |
| moonshotai/Kimi-K2.6 | 0.75, 3.50 | yes | 6/7 | 6/7 | 323 s, 245 s |

Every miss was the same task, picking the original among covers in Spotify's results, and every model said so honestly. A task costs well under a cent with any of the three. Two more GLM runs after the last harness changes: 6/7 and 6/7, 25 of 28 over four runs.

- **Arabic.** GLM wrote clean, warm فصحى; DeepSeek slipped into dialect in a joke.
- **Honesty**, the question that decided it: asked where an unfinished request stood, DeepSeek said the song was playing four times of four; GLM said it had found the button but not played it yet.

**Default: Gemma 4 31B turbo to answer, GLM 5.3 Flash to think.** DeepSeek V4 Flash is the cheaper choice; Kimi K2.6 is as good at eight times the price. Both pickers are in the app under the provider: "Model, everyday answers, fast" and "Thinking model, tasks on the PC and phone".

### What the runs fixed

- Memory replays each past turn's tool calls and results (above).
- Only the latest request is the task: a model kept retrying an earlier one that had gone wrong.
- `ui_look` numbers repeated names and prints a list row's text before its buttons.
- `ui_act`, `press_keys` and `type_text` report what the window shows afterwards; `ui_act` waits for the app before reading it, since a status read at once still named the song before.
- The closing summary is always asked for, with the list of what was done. Asked plainly "did it work", every model said yes after only looking.
- Gemma leaks `<turn|>` at the end of some replies; the brain and the board both drop it.
- English requests after Arabic turns came back in Arabic, and an Arabic request with an English song title came back in English. The request itself now ends with the language to answer in.
- The board sat silent for 20 to 30 s on a task and twice gave up: the fillers were under 15 letters, went out only after one long wait, and the keep-alives were 12 bytes where the board reads 128. Now a 38 s task runs to the end with the filler at 3.8 s.

### Through the board

The same brain driven the real way: requests typed into the board's `ask` command (a full turn through the state machine, the PC brain and the voice, minus the microphone), with the app linked and "act on your own".

| Request | Model | What happened | First audio |
|---|---|---|---|
| قديش الساعة هلأ؟ | Gemma | The time, in Arabic | 5.6 s |
| What is the weather in Amman today? | Gemma | Overcast, twenty nine and seventeen degrees | 4.7 s |
| What song is playing right now? | Gemma | Read the media session: Save Your Tears by The Weeknd | 4.3 s |
| Play Starboy on Spotify | GLM | Searched, looked, clicked Starboy, checked it plays | filler, 31 s in all |
| pause it | GLM | Paused what was playing | 7 s |
| شغّلي أغنية Blinding Lights | GLM | Played The Weeknd's original, not a cover; answered in Arabic | filler |
| افتح يوتيوب وشغّل أغنية Lifetime لكريس غراي | GLM | Opened YouTube's results, played the official video, checked | filler, 58 s in all |
| Open Chrome and find me a good mansaf recipe | GLM | Opened a recipe page in Chrome | filler |
| close that | GLM | Closed Chrome, from the turn before | filler |
| Open Chrome and search for flights from Amman to Dubai next Friday | GLM | Searched; said the site showed a robot check, gave the fares it found | 3.8 s filler, 54 s in all |
| Close Spotify | GLM | Checked the windows: already closed, true | 3 s filler |

## Without the window

| Command | Does |
|---|---|
| `dart run tool/pc_harness.dart <board ip> [token file]` | the PC side (tool server, tools, PC brain) from the command line; tells the board where it is and serves until Ctrl+C. Reads `DEEPINFRA_API_KEY` and `LLM_MODEL` from `.env`. Do not run it and the app at once: both want port 7331. |
| `dart run tool/pc_brain_probe.dart "What time is it?" "Open Spotify"` | the brain alone against the real model, with stand-in tools; prints what the board would speak |
| `dart run tool/native_tools_check.dart [open\|stats\|shot\|media\|find\|lock]` | fires each native tool once and prints what came back. Without arguments it runs all but `lock`. |
| `dart run tool/brain_eval.dart <model> --thinking=<model>` | the eval above |
