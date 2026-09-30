# The Orion voice, v1 (history)

The first voice, replaced by the voice in VOICE.md. Kept as a record of how it was
chosen.

Orion speaks natural, spoken Levantine Arabic, the way people talk in Amman. This file
records which voice was chosen, how it was chosen, and the TTS settings that go with it.

The id itself lives in `.env` as `FISH_VOICE_ID`, never in git.

## The voice

| | |
|---|---|
| Name in the project | Orion |
| Source | Fish Audio public Voice Library, `صوت شب اردني`, a young Jordanian man |
| Reference id | in `.env` as `FISH_VOICE_ID`, first eight characters `ec69015c` |
| Visibility | public, `licensed: false`, not a named real person |
| TTS model | `s2.1-pro`, set through `FISH_TTS_MODEL` in `.env` |

## How it was made

Section 1b gives three ways to get the voice, in order of preference. Here is what
happened to each.

1. **Design it from a description.** `POST /v1/voice-design` exists and takes exactly the
   prompt section 1b describes. It returned `402 Insufficient API credit`. The account's
   Fish API credit is at zero, so this route was closed. The prompt is kept in
   `tools/cloud/voice_audition.py` as `DESIGN_PROMPT` and `--design` retries it in one
   command the day credit exists. This is the route to take then: a designed voice is ours,
   and it can be named Orion inside Fish Audio itself.
2. **Clone the user's own voice from `voice/reference/`.** The folder holds only a README.
   Nothing was recorded, so there was nothing to clone.
3. **Choose from the public library.** This is what shipped. Six public Arabic voices were
   auditioned. None of them is a named real person: voices titled after actual public
   figures were filtered out on purpose.

## The audition

Every candidate spoke the five section 1b test lines. The WAVs are committed under
`voice/auditions/<candidate>/`, 16 kHz mono, plus an `audition.json` per candidate with
the measurements.

Judging was not left to taste. Every clip was transcribed back by a second, independent
engine (`openai/whisper-large-v3` on DeepInfra, Arabic hint) and compared to the line that
was sent, after folding alef forms, ta marbuta, diacritics and punctuation. A voice that
slides into fusha, swallows a Levantine word, or reads "Spotify" as Arabic letters comes
back with a higher character error rate. That is measurable; "sounds nice" is not.

| candidate | title | mean CER | English kept | speech rate ch/s | median ttfb ms | rms |
|---|---|---|---|---|---|---|
| shami | شامي | 0.116 | 2/2 | 10.3 | 619 | 3488 |
| **shab-urduni** | **صوت شب اردني** | **0.146** | **2/2** | **13.9** | **786** | **9650** |
| lubnani | لبناني | 0.249 | 2/2 | 9.0 | 655 | 2780 |
| falastini | فلسطيني | 0.251 | 0/2 | 8.6 | 738 | 3027 |
| urduni-fakhm | اردني فخم | 0.288 | 2/2 | 12.5 | 1196 | 1083 |
| shab-lubnani | شاب لبناني | 0.379 | 0/2 | 13.3 | 666 | 4443 |

Three candidates were out on the evidence, not on a feeling:

- `shab-lubnani` and `lubnani` drifted into formal fusha. Asked to say "خليني أشوف" they
  came back as "دعوني أرى" and "ماذا تريد". Orion never speaks fusha unless asked.
- `shab-lubnani` and `falastini` read the English words as Arabic letters: "Spotify"
  became "سباتيفاي" and "باتيفاي". Orion has to say "شغّل الـ Spotify" the way a Jordanian
  says it.
- `urduni-fakhm` came out at rms 1083, roughly 19 dB quieter than the loudest candidate,
  which is the wrong direction for a one inch speaker.

## The tiebreak

`shami` and `shab-urduni` finished close, so they were run again on the nine lines Orion
actually says in service: the five earcons and four typical replies, two takes each,
better take kept.

| candidate | mean CER, 9 real lines | speech rate ch/s | rms |
|---|---|---|---|
| shami | 0.070 | 7.7 | 2982 |
| **shab-urduni** | **0.060** | **12.0** | **10635** |

The mean is close; the individual lines are not. On the Levantine markers that matter,
`shab-urduni` came back exact and `shami` did not:

| line | shab-urduni | shami |
|---|---|---|
| مافي إنترنت هلأ | ما في انترنت هلأ | ما فيه أنترنت هلّا |
| ما بعرف، بس بقدر أدوّرلك | ما بعرف بس بقدر ادور لك | مبارث بس بقدر أدورلك |
| ما سمعتك منيح، عيدها؟ | ما سمعتك منيح؟ عيدها؟ | مع سمعتك منيح عيدا؟ |

Add the two things that are not about dialect at all. It is roughly 11 dB louder at the
source, which matters on the FUET 2112 speaker. And it is genuinely Jordanian, which is
the brief: Amman, not Levantine in general.

**Chosen: `shab-urduni`.**

### One number in that table is a lie, and it is worth writing down

Line 3 of the audition, "حوالي خمسة وعشرين درجة", scores CER 0.297 for every single
candidate. That is not five voices making the same mistake. The judging transcriber writes
the numeral "25" where the script spelled the number out, and the comparison counts every
one of those characters as wrong. Same thing for "الساعة تسعة ونص", transcribed "الساعة 9
ونصف", which is the one bad score `shab-urduni` got in the tiebreak. Discount those two
lines and the tiebreak reads 0.033 against 0.079, which is the real gap.

Numbers spelled as words are exactly what the system prompt asks the model to produce, so
this artifact will show up in any future ASR scoring. It is a scoring artifact, not a
pronunciation fault.

## TTS settings

```json
{
  "text": "...",
  "reference_id": "<FISH_VOICE_ID>",
  "format": "pcm",
  "sample_rate": 16000,
  "latency": "balanced"
}
```

with the model in the HTTP header, `model: s2.1-pro`.

- `format: "pcm"` is raw 16 bit mono little endian, no header. The board writes it straight
  into I2S. Asking for `wav` instead returns a placeholder RIFF header whose size fields
  are always 4294967076, so the header is built locally in both the Python tools and the
  firmware.
- `sample_rate: 16000` matches the mic and the speaker, so nothing resamples anywhere.
- `latency: "balanced"` measured on this voice, time to first PCM byte, 3 runs each:

  | mode | median ms |
  |---|---|
  | low | 700 |
  | balanced | 639 |
  | normal | 2868 |

  `normal` is four times slower to first audio and it is the API default, so it has to be
  set explicitly on every request. `low` and `balanced` are within noise of each other;
  `balanced` is kept for the better prosody.
- No `prosody` override. The voice runs at about 12 characters per second, which is brisk
  and suits an assistant. If it ever needs slowing, `prosody.speed` takes 0.5 to 2.0.
- `chunk_length` left at the default. The replies are one to three short sentences, well
  under one chunk, so splitting it would only add overhead.

## Emotion tags

S2.1 Pro performs inline square bracket tags and never speaks them, and this holds in
Arabic, not only in English. Nine cases were transcribed back and not one contained a
bracket, an English tag word, or an Arabic translation of one. Twenty more tagged earcon
takes and three full model-to-speaker replies since: still zero leaks.

The delivery changes in the direction the tag names. `[whispering]` came out 19% longer
with more silence between words. `[laughing][excited]` came out 88% longer on a sentence
whose words did not change, because an actual laugh was added. Open domain phrases work,
so this is not a fixed vocabulary: `[the calm, measured tone of someone who has done this
a thousand times]` produced a 25% louder, 7% slower reading.

Tags cost no measurable latency. A 71 character open domain phrase reached first audio in
661 ms against 663 ms for no tag at all. They are billed as characters, so they cost
credits, not time.

Orion uses four, and only four:

```
[warm]  [playful]  [apologetic]  [thoughtful]
```

The system prompt allows one, at the very start, and says that no tag is the normal case.
Over fifteen test questions the model tagged six: both refusals got `[apologetic]`, both
jokes got `[playful]` in two different languages, and every flat factual answer got
nothing. It never invented a tag outside the list.

The earcons use tags too, chosen the same way as the voice: generated both ways and kept
only if the tagged take did not leak and did not cost more than 0.06 CER.

| earcon | tag |
|---|---|
| ok | `[warm]` |
| thinking | `[thoughtful]` |
| repeat | `[apologetic][gentle]` |
| offline | `[flat, matter of fact]` |
| error | `[apologetic]` |

`repeat` and `error` got in on that tolerance rather than outright: their tagged takes are
slightly harder to transcribe. They were kept because those are the two lines where tone
carries the meaning. `make_earcons.py --no-tags` regenerates the plain set.

One real cost, stated plainly: the heavier the tag, the less canonical the delivery, and
the harder it is to transcribe. An open domain phrase took CER from 0.043 to 0.130. That
is not a leak and it does not affect a human listener, but it is why short tags are
preferred and why the allowlist is four words rather than free text.

## Saying its own name

The voice swallows the initial hamza of أوريون and says something closer to "وريون". It is
the voice, not the recognizer: a different Arabic voice saying the same sentence came back
with the alef intact.

The fix is to spell the name with explicit short vowels:

| sent | heard |
|---|---|
| أوريون | وريون |
| اوريون | وريون |
| **أُورْيُون** | **أوريون** |

`cloud_tts.c` substitutes this into the text immediately before the TTS request, so it
applies whatever the source of the text is: the model, an earcon, the `talk` console
command. It is done there rather than in the system prompt because a prompt can only ask
the model to spell it that way.

Worth passing to whoever trains the wake word: a name this voice under articulates is a
name its synthetic positive clips will also under articulate.

## Still open

- The small speaker test. Section 1b asks that each surviving candidate be played through
  the board's own speaker before the voice is final. The board was not available for audio
  playback during this phase. The auditions are committed so this is a five minute job once
  `orion-hardware` can play a WAV from the assets partition.
- Redo this as a designed voice when Fish API credit is restored:
  `python tools/cloud/voice_audition.py --design`.
