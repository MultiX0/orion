# Providers: the models behind Orion

A turn has three stages, and each can come from a different provider:

| Stage | Default | Options |
|---|---|---|
| Language model | DeepInfra: `google/gemma-4-31B-it-turbo` to answer, `zai-org/GLM-5.3-Flash` to think | any OpenAI compatible endpoint |
| Speech to text | Fish Audio `transcribe-1` | Fish (`transcribe-1`, `transcribe-1-pro`) or any OpenAI compatible `/audio/transcriptions` |
| Text to speech | Fish Audio `s2.1-pro-free`, Orion Voice | Fish (`s2.1-pro-free`, `s2.1-pro`, `s2-pro`, `s1`) or any OpenAI compatible `/audio/speech` |

All three are chosen in the app: in onboarding ("Brain and voice") and later under Providers. The board stores them and uses them from the next turn; the PC and phone brains use the same language model settings. Keys live in the OS keychain on the app side and in NVS on the board, nowhere else.

## Language model

Every provider is treated as OpenAI compatible: `GET <base>/models` to list, `POST <base>/chat/completions` to talk.

| Preset | Base URL | Notes |
|---|---|---|
| DeepInfra | `https://api.deepinfra.com/v1/openai` | the default; both models preselected |
| OpenAI | `https://api.openai.com/v1` | |
| Anthropic | `https://api.anthropic.com/v1` | Anthropic's OpenAI compatible layer: the app sends `x-api-key` as well as the bearer, and `anthropic-version: 2023-06-01` |
| Groq | `https://api.groq.com/openai/v1` | |
| OpenRouter | `https://openrouter.ai/api/v1` | |
| Ollama | `http://localhost:11434/v1` | no key; the app also reads `/api/tags` for model details |
| Custom | yours | must be OpenAI compatible |

Base URLs are editable.

**For the board, `localhost` is the board itself.** A model served on your PC (Ollama or anything else) must be given to the board by the PC's LAN address, for example `http://192.168.1.20:11434/v1`, and the server must listen on the network, not only on loopback. The board allows plain `http://` for this.

### Two models

Each provider has two model choices:

- **Model, everyday answers, fast.** Used by the board for every turn it answers itself, and by the PC and phone brains to start every turn.
- **Thinking model, tasks on the PC and phone.** The brain moves a turn to it the moment it has to act. Only the PC and phone brains use it.

Why Gemma and GLM: [HARNESS.md](HARNESS.md#choosing-the-models-a-fast-one-to-answer-a-thinking-one-to-act). A DeepInfra provider saved with no model loads as Gemma 4 31B turbo.

### What the app does with a provider

- **Check key**: `GET <base>/models`. 401 means the key is wrong.
- **Model list**: the same call, parsed into id, name, context length and flags. DeepInfra tags every model with its kind in `metadata.tags` (`chat`, `embed`, `tts`, `stt`, `image-gen`, `video-gen`, plus `vision`), about 190 models, so the picker shows only chat models for the language model and marks the ones that see pictures. Other providers do not tag, so their lists show everything.
- **The picker**: a searchable list (a dialog on desktop, a sheet on a phone). Search matches id and name in any case, Enter takes the first row, Escape closes, and "Use <text>" takes a typed id the list lacks or when the list did not load.
- **Test**: one short completion (`"Say hi in five words."`, 20 tokens), showing the reply and the time. 401 is a bad key, 404 a bad model.
- **Use on Orion**: `POST /api/config` with the `llm` block; the board answers with its masked config as confirmation. On desktop it also writes the optional dsh settings.

## Speech to text

| Preset | Provider on the board | Base URL | Model |
|---|---|---|---|
| Fish Audio | `fish` | | `transcribe-1` or `transcribe-1-pro` |
| DeepInfra | `openai_compatible` | `https://api.deepinfra.com/v1/openai` | `Qwen/Qwen3-ASR-1.7B` |
| Groq | `openai_compatible` | `https://api.groq.com/openai/v1` | `whisper-large-v3-turbo` |
| OpenAI | `openai_compatible` | `https://api.openai.com/v1` | `gpt-4o-mini-transcribe` |
| Custom | `openai_compatible` | yours | yours |

Fish is streamed while you talk and is the fastest by far (about 0.4 s after the last word, against 1 to 9 s for batch uploads); the measurements are in [FIRMWARE_CLOUD.md](FIRMWARE_CLOUD.md#why-fish-is-the-default). The OpenAI compatible models are picked from the endpoint's own list: DeepInfra's `stt` tag, and on OpenAI and Groq by id (`whisper` or `transcribe`).

## Text to speech

| Preset | Provider on the board | Base URL | Model | Voice |
|---|---|---|---|---|
| Fish Audio | `fish` | | `s2.1-pro-free` | Orion Voice |
| DeepInfra | `openai_compatible` | `https://api.deepinfra.com/v1/openai` | `Qwen/Qwen3-TTS` | `Serena` |
| OpenAI | `openai_compatible` | `https://api.openai.com/v1` | `gpt-4o-mini-tts` | `alloy` |
| Custom | `openai_compatible` | yours | yours | yours |

On Fish, Orion speaks in Orion Voice only; the app pins it. Another provider works, with its own voice, but the emotion tags are dropped (only Fish performs them). On DeepInfra, Qwen3-TTS is the one model that spoke both the English and the Arabic test lines correctly; Kokoro read Arabic as gibberish. The voice name for non-Fish providers is typed.

## One key per account

The speech presets for DeepInfra, OpenAI and Groq use the same keychain entry as the language model preset of that name, so a DeepInfra key typed once serves the model and speech to text. Fish has its own entry, shared by both voice stages; with both on Fish the app sends it in both blocks.

"Only changed blocks": the app remembers what the board has for each stage and sends a block only when something in it changed, or when a key was typed since the last send. A key is only ever sent inside a block going out; otherwise the board keeps its own.

## Fish Audio

Base URL `https://api.fish.audio`, bearer key from https://fish.audio (the app's "Get your Fish Audio API key" button).

| Call | What |
|---|---|
| `GET /model?self=true&page_size=1` | the key check: 200 good, 401 bad |
| `GET /wallet/self/api-credit` | the API credit balance, a decimal string of dollars; the app shows it and the hours of listening it buys |
| `POST /v1/tts` | the app's preview (`format: mp3`, `latency: balanced`) and the board's speech (`format: pcm`, 32 kHz) |
| `POST /v1/asr` | the board's speech to text |

Money, as it works today:

- **Text to speech on `s2.1-pro-free` is free**, with no hard cap under Fish's fair use policy, in 83 languages. It is the intended production model, not a workaround. The paid models (`s2.1-pro`, `s2-pro`, `s1`) answer 402 on an account with no API credit.
- **Speech to text is billed**: $0.36 per hour of audio for `transcribe-1` and `transcribe-1-pro`. $1 is about 2.8 hours of listening, or about 2,500 questions of 4 seconds. There is no free speech to text model; with no credit every path answers 402.
- **API credit is separate from a Fish plan's package credit.** A plan's credit pays for the web app and Fish's MCP server, not for API calls. Add API credit at https://fish.audio/app/developers.
- The app says all of this in the speech to text card, and turns a Fish 402 on Test into "this account has no API credit".

## Testing a stage

Each stage has a **Test** in the app, which calls `POST /api/config/test` on the board: the board makes the smallest real request with what it has stored (a one token completion, one second of silence transcribed, two words spoken) and reports the time or the error. The app sends the stage's block first if it changed. While Orion is talking the board answers busy, and the app retries every 2 s. On the console the same test is `cloud_test llm|stt|tts`.
