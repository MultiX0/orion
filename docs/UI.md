# The app's interface

The `brand/` folder is the spec: colours, type, spacing, radii, motion and the voice of the copy. This page is how that becomes Flutter, and what each screen does. When this page and `brand/` disagree, `brand/` wins. The board's own screen is described in [FIRMWARE_SCREEN.md](FIRMWARE_SCREEN.md).

## What it aims for

- The first thing a new user sees is the orb finding the board. Discovery is a moment, not a spinner.
- Every change of the board's state shows in the app within about 200 ms, with motion, not a text label swap.
- The camera opens in under a second and never shows a broken image.
- Tool calls on the PC appear as they happen, like a terminal that respects you.
- Nothing reads like a settings page from 2012.

## Brand to Flutter

- `dart run tool/gen_tokens.dart` reads `brand/tokens.json` and writes `lib/core/theme/tokens.dart`: colours, spacing, radii, elevation, motion durations and curves, font families. It is generated; do not edit it by hand.
- `lib/core/theme/theme.dart` builds the `ThemeData` from the tokens. Nothing in a screen sets a colour literal, a font size or a magic padding number.
- Fonts from `brand/fonts`, converted to TTF in `assets/fonts/`: Playfair Display (display), Source Serif 4 (reading), Inter (interface), DM Mono (labels, the machine voice). Text styles are named by role (`display`, `headline`, `title`, `body`, `label`, `mono`), not by size.
- Copy follows `brand/voice.md`: short, warm, certain, a little cosmic, never cute. Buttons are verbs. Errors say what to do next. Section labels are mono with the brand's `//` marker ("// Settings"). The name is "Orion", never "ORION".
- The mark is the four point star in `brand/assets/logo.png`. `OrionMark` paints it from the same geometry the icons use, so the in-app mark and the icons cannot drift apart.
- Every visible control comes from `lib/core/widgets` (`OrionButton`, `OrionCard`, `OrionTextField`, `KeyField`, `OrionChip`, `OrionSelectField`, `OrionSwitch`, `OrionDialog`, `OrionToast`, `StatusDot`, `EmptyState`, `Skeleton`), never a Material default.

## Motion

Timings and curves come from `brand/motion.md` through `lib/core/motion/motion.dart` (`Motion.fast`, `base`, `slow`, `enter`, `exit`, `stagger`, the brand ease and the UI ease). One shared route transition for every page; tabs fade in 200 ms. `StepSwitcher` uses the same fade inside a screen, so moving between onboarding steps looks like moving between routes.

Reduced motion (the OS setting, or the app's own switch in Settings) cuts animations to nothing except the orb, which slows down instead of stopping.

## The orb

`lib/core/motion/orb.dart`, `orb_painter.dart`, `orb_sim.dart`: a `CustomPainter` driven by a ticker, in a `RepaintBoundary`, with no allocations per frame. It mirrors the board's `state.mode` over the WebSocket:

| Mode | Look |
|---|---|
| offline | dim, desaturated, slow breath |
| idle | soft breath in the brand colour |
| listening | larger and brighter, a gentle pulse |
| thinking | faster inner motion, a turning highlight, toward the accent |
| speaking | a rhythmic pulse between `tts.start` and `tts.end`, the outer ring blooming |
| error | a short shake, then the idle look with a warning tint |

State changes are tweened, never cut.

## The shell

- **Phones**: a bottom bar with Home, Talk, Camera, Conversation, and More (Providers, Settings).
- **Desktop**: a collapsible side rail with Home, Talk, Camera, Conversation, Providers, Settings and Harness, the mark at the top and the connection status at the bottom. The window opens at 1280x800, with a minimum of 1100x720.
- The shell is the only widget that asks `PlatformInfo.isMobile` about layout.

## Screens

Every screen has designed loading, empty, error and offline states. Offline is the most common real state and has to look intentional. Screenshots of every screen are in the top level [README](../README.md) and `docs/screenshots/`.

### Onboarding

Welcome, Find, Pair, Brain and voice, Hands (desktop only), Ready, drawn as a constellation at the top with one star per step and the current one lit. The orb is present on every step. Everything after Pair has "Later", and nothing blocks the way to Home.

- **Welcome**: the mark, one line, "Find my Orion".
- **Find**: boards appear as they are confirmed, each card with its name, address, firmware and a mono source tag (`beacon`, `mdns`, `sweep`, `name`). Manual entry stays visible. Under "// Not on the network yet", **A new Orion** starts Bluetooth setup (on phones and Windows).
- **Pair**: for a board on the network, the six digit code from its screen. For a new board, the Bluetooth flow: nearby boards with signal bars, the code, the board's networks, the password, the join.
- **Brain and voice**: three cards, one per stage (the mind, listening, speaking), each with a provider, a key field with Check, a model picker and Test. The Fish key has "Get your Fish Audio API key" and a credit note. See [PROVIDERS.md](PROVIDERS.md).
- **Hands** (desktop): "Hands on this PC?" Off, Ask me first, Act on your own, each with one honest sentence. "Act on your own" says it includes agent tasks.
- **Ready**: the orb wakes, one line, a single button to Home.

### Home

The orb, centred. Under it the last exchange as two short bubbles that slide in as `turn.*` events arrive. A status strip: signal (`-52 dBm`, or "no link"), volume, wake word. Tap the strip for Settings.

### Talk

"Speak, or type". A large hold to talk button, which starts listening on the board (release does nothing: the board ends the recording itself on silence; tapping while it is busy stops the turn), and a text field with Send, which runs the turn on typed text. The live transcript and reply for the current turn below. It exists so the assistant works in a room too loud for the wake word.

### Camera

Live MJPEG from the board, full bleed on a phone and a centred card on desktop, with the frame rate and resolution in a muted overlay. Snapshot, Save (the path appears in a toast), and "Ask about this", which opens a one line field and sends the question with a picture (`/api/talk/snapshot`); the answer shows over the image. The stream starts when the screen is visible and stops when it is not. A `onFrame` hook is left in the widget for on-device detection later.

### Conversation

Turns newest first: transcript, reply, tool calls as chips when a turn has them, timings in a muted mono line. Tapping a turn expands its timings. Live turns from the WebSocket appear at the top before the history is fetched again.

### Providers

The language model providers (DeepInfra, OpenAI, Anthropic, Groq, OpenRouter, Ollama, Custom), each with its base URL, key, model and thinking model pickers, Test and "Use on Orion"; below them the voice: speech to text and text to speech, with "Save to Orion". The same form widgets as onboarding, so there is one implementation of each.

### Settings

- **Device**: name (Rename), volume, wake word, mute, language, time zone. The wake word switch turns the board's listener on or off; with it off the idle screen asks for a tap. Time zone is Automatic (this device's zone, sent again whenever the app reaches the board) or a fixed UTC offset picked from a list. Mute mirrors the board, which has no mute of its own yet.
- **Board**: firmware, address, uptime, device id, camera; Change Wi-Fi, Restart, Unpair this Orion. When the board is out of reach: Change Wi-Fi and Pair another Orion.
- **PC control**: Off, Ask me first, Act on your own, on every platform. On a phone it writes the board's `pc.approval` and the PC follows.
- **App**: reduced motion.
- **About**: Orion by MultiX0, the link to https://github.com/MultiX0, the license.

### Harness (desktop)

The header: whether the tool server is listening and on which address the board was told, the PC control mode, dsh and Node versions when found, the active provider and model. Approval cards pinned above the feed until resolved (approve, approve for this session, deny). The feed: tool calls as they happen, newest first, each with its status and the mode it ran under ("on its own", "allowed this session", "approved by you"). See [HARNESS.md](HARNESS.md).

## Keys on screen

`KeyField` is the only place a key is typed: reveal, Check, and a checked state shown by the field's hairline accent. Keys never appear in a URL, a log line or a toast. When a check is not possible yet, the key is kept as typed and the field says so.
