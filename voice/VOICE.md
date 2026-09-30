# The Orion voice

Orion speaks fluent Modern Standard Arabic in the conversational register of a phone
assistant: warm, clear, confident, a woman's voice, neutral pan-Arab pronunciation, no
dialect and not a newsreader. English tech words stay English inside the Arabic sentence,
and an English question gets an English answer in the same voice.

The id lives in `.env` as `FISH_VOICE_ID`, never in git. This file records which voice was
chosen, how, and the settings that go with it. The first voice, a young Jordanian man
speaking Levantine, is kept at the bottom as history.

## The voice, v2

| | |
|---|---|
| Name in the project | Orion |
| Source | Fish Audio public Voice Library, `صوت أنثوي` ("a female voice") |
| Reference id | `81c63e6a5ff141d38367fcb009c570d6`, in `.env` as `FISH_VOICE_ID` |
| Library description | صوت أنثوي واضح ومهذب، مثالي للمحتوى التعليمي والإرشادي بأسلوب ودود ومطمئن |
| Library tags | female, young, crisp, warm, friendly, professional, confident, calm, measured, clear |
| Visibility | public, `licensed: false`, `dmca_taken_down: false`, not a named real person |
| TTS model | `s2.1-pro-free` today (`FISH_TTS_MODEL`), `s2.1-pro` once API credit exists |
| Audition folder | `voice/auditions_v2/unthawi/` |

### How it was made

1. **Voice design.** `POST /v1/voice-design` was tried again with a female
   MSA assistant brief. Still `402 Insufficient API credit`; the developer API balance is
   `0.000000` USD. Closed for now, same as v1.
2. **Clone.** `voice/reference/` still holds only a README. Nothing to clone.
3. **Library.** What shipped. `search_voices` over the queries `فصحى`, `arabic female`,
   `MSA`, `Modern Standard Arabic`, `مذيعة`, `صوت انثى`, `امرأة`, `مساعد`, `راوية` and the
   top Arabic voices by score and by use, then `get_voice` on each plausible female voice to
   read the description and demo text. Left out on purpose: every voice titled after a
   real person (`ريم بنت الوليد` is the name of a real Saudi princess, so it was dropped
   even though it is tagged MSA and scores well on paper), dialect voices whose demo text
   is Egyptian or Gulf colloquial, anime and character voices, and news anchors except one
   kept as a control.

### The audition

Fourteen female voices were screened on three lines, eight went through the full set. All
generation is REST `/v1/tts` on `s2.1-pro-free`, `format: pcm`, 16 kHz, `latency:
balanced`, no prosody object, which is what the board sends.

The lines, sent verbatim:

```
line1   مرحباً، أنا أوريون. كيف يمكنني مساعدتك اليوم؟
line1v  مرحباً، أنا أُورْيُون. كيف يمكنني مساعدتك اليوم؟      (what cloud_tts.c actually sends)
line2   لحظة من فضلك، دعني أتحقق من ذلك.
line3   الطقس في عمّان اليوم معتدل، حوالي خمس وعشرين درجة.
line4   فتحتُ لك Spotify على الكمبيوتر.
line5   عذراً، لم أسمعك جيداً. هل يمكنك الإعادة؟
line6   Hi, I'm Orion. I opened Spotify on your PC and the Wi-Fi is back.
```

Two independent ears. Every clip went through whisper-large-v3 on DeepInfra with the right
language hint. Each candidate's clips were also joined with 0.8 s gaps and transcribed once
by Fish's own recognizer (`speech_to_text`, model pro, no hint, 1453 to 1843 credits per
candidate). Both are scored as character error rate on the Arabic lines after folding alef
forms, ta marbuta, diacritics and punctuation. A spelled number written back as a numeral,
and Fish writing سبوتيفاي for Spotify (it never writes Latin inside Arabic), are folded back
before scoring; `سباتيفاي`, which is a different vowel, still counts as wrong.

| candidate | library title | whisper CER | Fish CER | name, whisper | name, Fish | name in English | English kept, whisper | ch/s | peak dBFS | rms dBFS | clipped | ttfb ms |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| mutasil | مساعد المتصل الآلي | **0.004** | **0.000** | 2/2 | 2/2 | yes | 14/14 | 10.6 | -0.5 | -17.0 | 0 | 520 |
| **unthawi** | **صوت أنثوي** | 0.053 | **0.000** | 2/2 | 2/2 | yes | 13/14 | **12.1** | -0.5 | **-13.5** | 0 | 468 |
| arabic-narr | arabic | 0.009 | 0.048 | 1/2 | 1/2 | no | 13/14 | 10.4 | -18.4 | -34.8 | 0 | 485 |
| musaida | مساعدة صوتية عربية | 0.031 | 0.011 | 1/2 | 0/2 | yes | 14/14 | 9.9 | -0.4 | -18.4 | 0 | 464 |
| emily | ايميلي | 0.068 | **0.000** | 1/2 | 2/2 | yes | 13/14 | 10.6 | -6.2 | -18.5 | 0 | 438 |
| qamboul | قامبول | 0.071 | 0.011 | 1/2 | 0/2 | yes | 13/14 | 11.0 | -2.2 | -18.8 | 0 | 453 |
| unthawi-arabi | صوت أنثوي عربي | 0.095 | 0.011 | 1/2 | 0/2 | yes | 13/14 | 12.8 | -0.7 | -16.9 | 0 | 532 |
| young-female | Young Arabic Female | 0.243 | 0.027 | 0/2 | 0/2 | no | 12/14 | 11.3 | -0.5 | -18.0 | 0 | 449 |

Out on the evidence:

- `young-female` hallucinated line1 outright ("ورحمة الله. ونحن نريد أن نتعرف على
  المستحيلات") and slurred line2 and line5. Its demo text is colloquial Homs Syrian, and it
  shows.
- `musaida`, `qamboul`, `unthawi-arabi` lose the name: أوريو, أورين, وريون.
- `arabic-narr` is the most accurate on whisper but comes out at -34.8 dBFS RMS, 21 dB below
  the winner. On a one inch speaker that is not a trade anyone should make.
- `emily` is clean on Fish but peaks around -6 dBFS and loses the name on whisper once.

That left `mutasil` and `unthawi`, both perfect on Fish, both holding the name four times out
of four. They went to a tiebreak.

### The tiebreak

Eight lines shaped like real replies, heavier on English tech words (YouTube, Wi-Fi, email,
Bluetooth), the name vowelled the way the firmware sends it, two takes each, plus `emily`
for reference. WAVs in `voice/auditions_v2/tiebreak/`, take 1 committed, take 2 in `logs/`.

| voice | mean CER | CER Arabic | CER English | name | worst peak dBFS | mean rms dBFS | clipped |
|---|---|---|---|---|---|---|---|
| mutasil | 0.086 | 0.115 | 0.000 | 2/2 | -0.5 | -17.1 | 0 |
| **unthawi** | 0.086 | 0.114 | 0.000 | 2/2 | -0.5 | **-13.6** | 0 |
| emily | 0.082 | 0.109 | 0.000 | 2/2 | -4.8 | -17.9 | 0 |

A dead heat on intelligibility. The Arabic CER is the same 0.11 for all three because
whisper with an Arabic hint writes every English word in Arabic letters (يوتيوب, الواي فاي,
الإيميل), whoever says it. That is the transcriber, not the voice, so the English-word
column cannot separate them; both English lines came back character perfect for all three.

So the decision rests on what does differ, measured:

- **Loudness.** `unthawi` sits 3.5 dB hotter in RMS at the same -0.5 dBFS peak, across 16
  takes. That is free headroom for the FUET 2112 speaker, and it is denser speech, not
  clipping: zero clipped samples anywhere.
- **Pace.** 12.1 characters a second against 10.6. A reply of forty characters ends about
  half a second sooner, every turn.
- **Register.** `mutasil` is published as "صوت آلي ... لأنظمة الرد الآلي", an automated
  phone menu voice, tagged neutral-tone and authoritative. `unthawi` is published as clear,
  polite, friendly and reassuring, tagged warm, friendly, confident, calm. The brief is
  Siri, not a call centre.

**Chosen: `unthawi`, `81c63e6a5ff141d38367fcb009c570d6`.**

### Saying its own name

This voice says the name cleanly both ways. `أوريون` and the vowelled `أُورْيُون` that
`cloud_tts.c` substitutes both came back as أوريون from both recognizers, in the audition,
the tiebreak and the English "I'm Orion". The substitution stays in the firmware: it costs
nothing with this voice and still protects any future voice that swallows the hamza.

### Still open

- A listen through the board's own speaker. The numbers pick the voice; they do not replace
  the user hearing it on the FUET 2112 before the video.
- Voice design when API credit exists: a designed voice would be ours outright, and could
  be named Orion inside Fish Audio.

## Emotion tags with this voice

Rules taken from Fish's Emotion Control page (`/developer-guide/core-features/emotions`),
not from memory: on the S2 family a `[bracket]` cue is free natural language, performed
and never read; sentence-level cues work best at the start of the sentence they control
and should not sit far from it; tone and sound markers may go anywhere; one primary
emotion per sentence; pairs like `[sad][whispering]` and intensity modifiers like
`[slightly sad]` are allowed; do not overuse tags in short text or mix conflicting ones.
Arabic is on the list of languages where sentence-start placement is recommended.

Every candidate was then measured with this voice, because a tag the voice ignores is
wasted bytes and a tag it reads aloud is a bug. `tools/cloud/tag_audition.py`: one neutral
sentence per language, six plain takes and four takes per tag, five features per take
(duration, RMS, pause ratio, median pitch, pitch range). A tag counts as changing the
delivery only when a Welch t test against the plain takes reaches 3 on some feature.
Every take was transcribed by whisper, and the kept candidates again by Fish
`speech_to_text` pro with a language hint.

Pass 1 screened 31 tags and pairs with two takes each. Pass 2 re-ran the 14 plausible
ones with more takes. Kept:

| tag | Arabic, mean change against plain | English | Fish ASR heard | why kept |
|---|---|---|---|---|
| `[laughing]` | +23% duration, +0.06 pause, t 5.9 | +20% duration, t 4.7 | `[ضحك]` 2/2, `[laughing]` 2/2 | a real laugh, labelled by an independent ear |
| `[chuckling]` | +15% duration | +12% duration, t 3.8 | `[ضحك]` 2/2, `[chuckle]` 1/2 | a lighter laugh, same evidence |
| `[confident]` | +1.0 dB, +0.9 st pitch, +1.7 st range, t 3.7 and 3.9 | nothing tag specific | words only | the expected direction, in Arabic |
| `[apologetic]` | pitch range -1.6 st, t -3.7 | nothing tag specific | words only | flatter, subdued, in Arabic |

Fish's recognizer writes `[ضحك]` and `[laughing]` as event labels for the sound itself.
Across 236 tagged takes whisper did the same twice, `*sigh*` on an English `[sighing]` and
`laughs` on an English `[laughing]`: labels for a performed sound, not the tag being read.
No take in either language had a tag word spoken as speech.

Dropped, with the reason:

- `[happy] [excited] [calm] [warm] [empathetic] [curious] [whispering] [soft tone]
  [in a hurry tone] [sad]`, and in pass 1 `[confident]`'s cousins `[satisfied]
  [delighted] [grateful] [sympathetic] [regretful] [surprised] [relieved] [encouraging]
  [friendly] [playful] [thoughtful] [sighing] [slightly sad] [very excited]`, the pairs
  `[happy][chuckling]` and `[empathetic][soft tone]`, and mid-sentence `[emphasis]` and
  `[break]`: no change in Arabic beyond take to take noise. In English almost every tag,
  `[calm]` and `[confident]` included, narrows the pitch range by 1.2 to 2.9 semitones
  against a wide-ranged plain take, so an English range shift is not evidence that a
  particular tag worked.
- `[whispering]` in particular does not whisper with this voice: voiced ratio unchanged.

The honest summary: with library voices on `s2.1-pro-free`, emotion tags are subtle.
`tools/cloud/tag_response.py` ran five strong tags on six voices, including the v1 voice;
only `[laughing]` moved every one of them (+12% to +27% duration). The v1 voice's
`[whispering]` measured +19% and +7% now. The voice's own reference delivery
dominates; tags season it.

The system prompt allows exactly these four, one per sentence at most, at the start of
the sentence, and says most replies carry none. Over 15 questions the model tagged six:
`[apologetic]` on all three refusals, `[chuckling]` on both jokes, `[confident]` once on a
recommendation, nothing on facts, names or definitions.

## Earcons, v2

Spoken in the new voice, fluent MSA, `tools/cloud/make_earcons.py`: two plain and two
tagged takes per line, the tagged take kept if it costs no more than 0.06 CER, then peak
normalized to -1.0 dBFS. The spoken "ok" (تمام) is removed from the loop and `ok.wav` is
deleted. The wake chime is untouched, byte for byte (sha1 `90171389`).

| earcon | says | tag | seconds | peak dBFS | rms dBFS | clipped | CER |
|---|---|---|---|---|---|---|---|
| wake | two tone chime, generated locally | - | 0.40 | -1.5 | -12.0 | 0 | - |
| thinking | لحظة من فضلك. | - | 1.16 | -1.0 | -13.7 | 0 | 0.000 |
| repeat | عذراً، هل يمكنك الإعادة؟ | `[apologetic]` | 2.13 | -1.0 | -14.2 | 0 | 0.000 |
| offline | لا يوجد اتصال بالإنترنت حالياً. | `[apologetic]` | 2.32 | -1.0 | -11.7 | 0 | 0.000 |
| error | عذراً، حدث خطأ ما. حاول مرة أخرى. | `[apologetic]` | 3.02 | -1.0 | -15.7 | 0 | 0.000 |

`repeat` went through three phrasings for length, since it plays mid turn: "عذراً، لم
أسمعك جيداً. هل يمكنك الإعادة؟" 3.71 s, "عذراً، لم أسمعك. هل يمكنك الإعادة؟" 3.20 s,
"عذراً، هل يمكنك الإعادة؟" 2.13 s, which is also what an assistant says ("Sorry, could you
say that again?"). None of them had silence padding to trim (at most 0.23 s of tail); this
voice simply takes a full pause at every full stop.

## TTS settings

Unchanged from v1 and still true: `format: "pcm"` with `sample_rate: 16000` (the `wav`
format returns a placeholder RIFF header), `latency: "balanced"` (the API default `normal`
is about four times slower to first audio), and **no `prosody` object** (sending one costs
about 9 dB of loudness). Model in the `model` HTTP header. The measurements are in
`VOICE_v1.md` and `docs/FIRMWARE_CLOUD.md`.

## History

v1 was `صوت شب اردني`, a young Jordanian man speaking Levantine, id prefix `ec69015c`,
chosen from six Levantine library voices. It was replaced by a woman's voice without the
Jordanian accent, speaking fluent Arabic the way Siri and Alexa do. The full v1 record, with its audition, tiebreak, emotion tag tests and the name
fix, is kept verbatim in [`VOICE_v1.md`](VOICE_v1.md), and its clips in `voice/auditions/`.
