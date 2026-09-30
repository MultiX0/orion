# Orion's voice

How Orion sounds and how it talks: the voice on Fish Audio, the languages, the emotion tags, the system prompt and the earcons.

## Orion Voice

| | |
|---|---|
| Name on Fish Audio | Orion Voice |
| Voice id | `9a68c1d739134940a4297c996c5ca6a1` |
| Visibility | unlisted: any Fish key can use it by id, it does not show in library searches |
| Model | `s2.1-pro-free` (Fish S2.1 Pro, free tier) |
| Character | soft, warm and gentle; natural Arabic with a light Saudi accent, natural English; says its name the English way |

Orion Voice is the project's own voice, made with Fish Voice Design (`voice-design-1`, about $0.01 a request) from a written description: two rounds of six candidates, the final one picked by ear, then published on Fish with the Orion star as its cover. It is the default everywhere: in the firmware when no voice is stored, in `tools/cloud/provision.py`, in the app, and in the mock board. The app offers no other Fish voice.

To use it in your own project: any Fish Audio key, `reference_id: "9a68c1d739134940a4297c996c5ca6a1"` on `POST /v1/tts`.

### How it got here

1. The first voice was a young Jordanian man from Fish's public library, speaking Levantine Arabic, chosen from six library voices by measurement.
2. The brief then changed to a woman's voice speaking fluent Modern Standard Arabic in a phone assistant's register, like Siri. Fourteen female library voices were screened and eight auditioned on seven lines each, scored by two independent recognizers (Whisper large v3 and Fish's own), for character error rate, whether the name came out right, loudness and pace. Two tied on intelligibility; the one 3.5 dB louder at the same peak, faster (12.1 against 10.6 characters a second) and published as friendly rather than as a phone menu voice won. The full audition is in `voice/VOICE.md`, and the first voice's in `voice/VOICE_v1.md`, with the clips under `voice/auditions/` and `voice/auditions_v2/`.
3. A library voice belongs to another Fish user and cannot be branded as Orion's, so Orion Voice was designed instead, once Voice Design was available on the account.

### The name

- Orion writes its name أوريون in Arabic. Before the text goes to Fish, every Arabic spelling of the name (أوريون، اوريون، أورايون، اورايون) is replaced with the Latin "Orion", which Orion Voice says the English way inside an Arabic sentence. The screen keeps what the model wrote. This is in `cloud_tts.c`.
- An earlier voice swallowed the initial hamza and said "وريون"; a fully vowelled spelling (أُورْيُون) fixed that for that voice. The Latin substitution replaced it.
- In connected speech "يا أوريون" naturally becomes "يا واريون"; that is how Arabic is spoken, not a fault, and the wake word was trained on it.

## Languages and register

From the system prompt:

- **Arabic**: fluent Modern Standard Arabic in the friendly, natural register of a phone assistant. Simple everyday فصحى, never a dialect (jokes included), not a news anchor. Orion speaks as a woman (أنا سعيدة، لستُ متأكدة) and addresses the user with the plain forms (لك، يمكنك).
- **Native, not translated**: the verb itself (شغّلتُ الأغنية، فتحتُ Spotify), never أقوم بتشغيل or تم فتح; لا أستطيع, never لا أملك أداة; no هو as a linking verb; times the way people say them (الثانية عشرة إلا ثلثاً for 11:40).
- **English**: an English question gets a whole English answer, technical questions included.
- **Brand and tech names** stay in Latin letters inside Arabic: Spotify، Wi-Fi، YouTube، PC.
- **Short**: one or two sentences, under about twenty words. Answer, then stop.
- **Speakable**: numbers, times, dates and units as words; no markdown, lists, emoji, parentheses or code.
- **Honest**: no reminders or timers (say so in one sentence); never guess what is in front of the camera (call the look tool); never invent the time, weather or news (they are given when known, or tools fetch them); if unsure, say so.
- **Self-knowledge**: asked what it is, two sentences: its name, a home assistant on its own small board with a camera, screen, microphone and speaker, and that its voice comes from Fish Audio. The hardware list only when asked about the hardware. The language model is never named, because the owner can switch it.

The prompt was tested with ten Arabic and five English questions per revision, checking what breaks speech (digits, markdown, length, the wrong language). The first Modern Standard Arabic draft scored 13 of 14 but tagged nearly every reply and answered one joke in Gulf dialect; the revision scored 14 of 14 with tags on 6 of 14 replies, and the median spoken reply fell from 5.8 s to 4.3 s.

## Emotion tags

Fish S2.1-Pro and S2-Pro read a cue in square brackets as free natural language, not a fixed set, and perform it without reading it aloud. Fish's models overview lists these as common examples: `[whisper] [laugh] [emphasis] [sigh] [gasp] [pause] [angry] [excited] [sad] [surprised] [inhale] [exhale]`, and descriptive ones like `[whispers sweetly]` or `[laughing nervously]`. Cues "can be placed anywhere in your text to control emotion at specific positions", for example `I can't believe it [gasp] you actually did it [laugh]`. The `(parenthesis)` syntax is for the older S1 model only.

The prompt's tag rules sit between a `<fish>` line and a `</fish>` line, so the board can send them only to a Fish voice (see the next section). They ask for cues:

- in English, from the list above or described in a few words;
- exactly where the sound or feeling happens, anywhere in the sentence: a mood before the words it colours, a laugh right after what is funny;
- wherever a person would really sound that way: a light `[laugh]` when something is warm or funny, in a joke one `[pause]` before the punchline and one `[laugh]` after it, `[excited]` for good news, `[sigh]` for a pity, `[whisper]` for a secret;
- one at a time, never two side by side, and none before a plain fact, number, time or name.

Measured with `tools/cloud/prompt_test.py` on Gemma: the old rules (seven allowed tags, sentence start only, "most replies have none") tagged 3 of 15 replies; the new ones tag 8 of 15, with facts, numbers and times left plain, and all 15 replies clean. A first draft without the last rule tagged 13 of 15 and put `[pause]` before plain numbers.

Earlier measurements with a library voice found that only a few tags (`[laughing]`, `[chuckling]`, `[apologetic]`, `[confident]`) changed the delivery beyond take to take noise in Arabic, and that `[whispering]` did not whisper. Orion Voice and S2.1 are newer; listen before relying on a subtle mood cue. What is certain: across hundreds of tagged takes, no tag was ever spoken as words, in either language, and tags cost no measurable latency (first audio 583 to 663 ms with or without a 71 character tag).

Where the cues go on the board:

- The chunker never cuts inside `[...]`, a cue in the middle of a sentence stays with its words, and a sound cue right after a sentence end (`did it! [laugh]`) stays with that sentence, so a closing laugh is not lost. A mood cue at the start of a sentence is carried over a comma cut; a sound cue is not, or the laugh is heard twice.
- The screen (`ui_set_text`) and the app's transcript strip every `[...]` span, with no space left before a stop.
- With a non-Fish text to speech the prompt has no tag section at all and asks for no brackets, and the board strips any that slip through before the speech request.

## The system prompt

`firmware/assets/system_prompt.txt`, about 5.7 KB, in the `assets` partition. The board loads it once at boot; with no assets partition it falls back to a short built-in prompt.

At runtime the board adds to it, per turn:

- the current local date and time, when the clock has synced;
- when the board answers alone, that no PC or phone is connected (or that it did not answer), so the model never claims to have acted;
- the `<fish>` section with the tag rules only when text to speech is Fish; with any other voice that section is left out and a line asking for no square brackets is added. This is worked out again on every config reload.

The PC and phone brains add their own context on top (where they run, how to speak about tool results, the memory); see [HARNESS.md](HARNESS.md#the-pc-brain).

Prompt size costs almost nothing: from 700 to 1600 prompt tokens, the fastest first token did not move (881 to 887 ms) and the median moved about 100 ms, inside the service's own run to run noise.

### Changing it

1. Edit `firmware/assets/system_prompt.txt`. Keep it plain text, UTF-8, and keep the rules that protect speech (short, words for numbers, no markdown).
2. Test it from a PC without the board: `python tools/cloud/prompt_test.py` sends ten Arabic and five English questions through the real prompt and model and flags digits, markdown, long answers and the wrong language; `--speak` also synthesizes each reply. It cuts the prompt the way the board does (`--tts openai` for the prompt a non-Fish voice gets) and flags stacked cues, a cue not in English, and any cue for a non-Fish voice. `python tools/cloud/prompt_cut_test.py` checks the cut itself, offline. Keys come from `.env`.
3. Build and write only the assets partition, so nothing else on the board changes:

```
idf.py build
python -m esptool --chip esp32s3 write_flash 0x510000 build/assets.bin
```

On Windows: `tools\flash.ps1 -Bin firmware\build\assets.bin -Address 0x510000`. The board picks it up at the next boot.

## Earcons

Short sounds from `/assets/earcons/`, all in Orion Voice except the chime. See [FIRMWARE_AUDIO.md](FIRMWARE_AUDIO.md#earcons) for when each plays. `python tools/cloud/make_earcons.py` regenerates them: two plain and two tagged takes of each line, every take transcribed, the tagged take kept only if it does not leak and costs at most 0.06 in character error rate, then peak normalised to -1 dBFS. `--only <name>` does one, `--no-tags` plain takes only. The wake chime is generated locally and only regenerated when asked for by name.

## Changing the voice

- **Another Fish voice.** The app pins Orion Voice, but the board takes any voice id: on the console, `cfg_set tts_voice <voice id>` then `cloud_reload`, or `TTS_VOICE` in `.env` with `provision.py`. The emotion tags are tuned for Fish voices in general.
- **Another provider.** Pick DeepInfra, OpenAI or a custom endpoint for text to speech in the app. Tags are dropped and the voice is that provider's.
- **Clearer on the speaker.** Fish is asked for 32 kHz (`tts_rate` on the console tries 16000, 24000, 32000 or 44100 until the next restart). The board's optional loudness chain is described in [FIRMWARE_AUDIO.md](FIRMWARE_AUDIO.md#the-voice-as-fish-sends-it).

## Fish text to speech settings, and why

| Setting | Why |
|---|---|
| `format: pcm` | the default is mp3; `wav` comes back with a placeholder header whose sizes are wrong |
| `latency: balanced` | the default `normal` was four times slower to first audio (2868 ms against 639 ms median) |
| no `prosody` object | sending one costs about 9 dB of loudness; the plain body is the loudest option |
| 32 kHz | 16 kHz cuts off at 8 kHz, where a soft voice keeps much of its consonants; the amplifier cannot lock to 24 kHz; the voice has almost nothing above 10 kHz, so 44.1 kHz adds nothing |
| model in the `model` header | how Fish picks the model; `s2.1-pro-free` is the free tier |

Generation varies: identical text peaks 2 to 4 dB apart between takes, so the board's playback path must expect samples near full scale.
