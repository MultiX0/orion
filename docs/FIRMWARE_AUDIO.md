# Audio on the board

`firmware/components/orion_audio`. One microphone in, one small speaker out, and no echo cancellation.

## The hardware

| Part | Bus | Pins |
|---|---|---|
| MP34DT05-A PDM microphone | I2S0, PDM RX (only port 0 can receive PDM on the ESP32-S3) | clock 40, data 38 |
| MAX98357A amplifier | I2S1, standard TX | BCLK 41, LRCLK 42, data 39 |
| Shared enable | GPIO 18, **active low**, gates both the mic and the amp | |
| Speaker | "Audio" socket on the back | FUET FS2112, 8 ohm, 1 W |

The amplifier's gain is fixed at 9 dB by resistors on the board, and it tops out near 3.2 W into 4 ohms; the small speaker is the part that can be hurt by sustained power. The amplifier mixes the two I2S slots as (L+R)/2.

## Microphone

- A task on core 1 at priority 10 reads 10 ms chunks (160 samples at 16 kHz) into a **4 s ring in PSRAM**. The wake word, the recorder and the level meter each open their own reader; a reader starts at "now", never blocks another, and skips ahead if it falls more than half the ring behind.
- **DC blocker first.** The PDM path has a DC offset that drifts for minutes after boot, and the first thresholds were all measuring it: "silence" read RMS 230 with an AC part of 13. A one-pole tracker (about a 10 Hz corner) now removes it before anything else sees the chunk. After it, silence in a room reads **RMS 4 to 13**, and speech from a metre away **40 to 180**, peaking around 430.
- **Noise floor.** Measured as the median of the first second after boot (after 30 chunks of PDM filter settling), then it falls fast and rises slowly, so speech does not drag it up. It never goes below 20.
- **Muted while the speaker plays**, and for 100 ms after, because the microphone hears the speaker loud and clear. The wake chime is the exception: it plays with the microphone open, so a question said over it is kept.
- `orion_audio_level()` is a smoothed 0 to 1 level for the listening animation; `orion_audio_out_level()` is the same for what the speaker is playing, for the speaking animation.

## End of speech

`audio_vad.c`, on 20 ms frames:

| | |
|---|---|
| Speech starts | two frames above 4x the noise floor, and at least RMS 100 |
| Speech ends | 600 ms below 2x the floor (at least RMS 50) |
| Kept before speech | 300 ms |
| Kept after speech | 400 ms |
| Longest recording | 10 s |
| Nobody spoke | 4 s with no speech: the turn ends with the "repeat" earcon |

- The recording can start from a **mark**: `orion_audio_mark_utterance()` is called at the wake word, so "Orion, what time is it" in one breath keeps its first word. Without it "إدش الساعة" came back as "دش الساعة".
- Frames heard while the speaker plays, and for 150 ms after, can never start speech, so the chime and its echo in the room are not taken for the user. Speech that began under the chime is still kept from the mark.
- 600 ms is where the end sits: every millisecond here is added to every answer. 800 was the first value.
- The fixed minimums (100 and 50) were lowered from 250 once the DC blocker made the floor honest. With 250, speech from PC speakers at RMS 207 was never detected.
- `orion_audio_record_utterance_stream` hands the audio to a sink while recording, which is how speech to text starts before the user finishes.

## Speaker

- The I2S clock **never stops** (the DMA auto-clears to silence), the first and last 10 ms of every stream are ramped, and the amp enable is raised about 30 ms after the clock starts. Together that is what keeps the MAX98357A from popping. Measured through the board's own mic, the onset of a tone never exceeded the steady tone by more than 3 percent.
- **Both I2S slots are filled** in mono. The ESP-IDF mono default fills only the left slot; with the amp mixing (L+R)/2, that plays at half amplitude. Filling both was worth +6.4 dB for free (the mic heard the board's own 1 kHz tone at RMS 500 with one slot, 1044 with both).
- The playback rate follows the source: 16 kHz for earcons, 32 kHz for Fish Audio. The MAX98357A cannot lock to 11.025, 12, 22.05 or 24 kHz (its datasheet lists them as unsupported), so a stream at one of those rates, such as an OpenAI compatible server's fixed 24 kHz, is clocked at twice the rate with each sample followed by its midpoint to the next. `orion_audio_play_begin(rate)` retunes the clock.
- The DMA holds 8 descriptors of 480 frames: 120 ms at 32 kHz.
- **Volume** is 0 to 100 on a square law, 100 is unity. `volume <n>` on the console and the app store it in NVS; the plain `vol` command changes it until the next restart only.
- **A pause** (`play_write` with 0 bytes) fades to silence and the next write fades in.

### The amplifier and why the voice is shaped

The MAX98357A runs off the board's 3.3 V rail, the same rail as the ESP32-S3, with its gain pin left open (9 dB). At that gain a full scale sample asks for about 5 V peak, and the amp can only give about 3.1 V on 3.3 V, so it clips its own output above roughly -4 dBFS in, and lower when the rail sags under load. Fish Audio peaks reach -0.5 dBFS. Clipping in the amp is heard as crackle on loud syllables, and the current behind it pulls the shared rail down; on a laptop's USB port, dense loud phrases were enough to reset the board.

The speaker is 8 ohm, 0.7 W, with its resonance near 950 Hz. It makes little sound below that, yet most of a voice's electrical power sits there: bass only heats the amp and draws the rail down.

### Voice modes

`spk mode clean|raw|boost` picks the chain. Clean is the default.

| Mode | Chain |
|---|---|
| clean | -3 dB trim, 4th order high pass at 350 Hz (two Butterworth stages), look-ahead limiter at -6 dBFS with 3 ms of look-ahead, 0.5 ms attack, 120 ms release. The top is left alone. |
| raw | The voice as it comes, times the volume. Loud syllables clip in the amp. |
| boost | The old loudness chain: 300 Hz high pass, -4 dB at 400 Hz, presence at 3 kHz, -6 dB shelf above 5 kHz, +5 dB make-up, limiter at -1 dBFS, power guard. For a strong wall supply in a loud room only. |

Clean keeps every peak under -6 dBFS, so the amp never clips and never drags the rail with it. Over eight replies checked on the board (English and Arabic, including counting and the alphabet backwards), peaks were -6.0 to -8.9 dBFS, no sample clipped, nothing dropped out, and the energy below 150 Hz was about 20 dB lower than raw. It plays a few dB quieter than raw, most of the difference being bass the speaker could not reproduce anyway. Cutting the treble as well is what makes a voice sound like a radio, so clean does not.

`spk hpf <hz>` moves the high pass live (in clean and boost); `spk gain`, `spk mud`, `spk presence` and `spk treble` tune the boost chain; `spk stats` prints peak and RMS in and out, the limiter's deepest reduction, clipped samples and guard trips. Everything is float until the limiter, so the only place a sample can hit the rails is the conversion after it, and `clipped` counts exactly that.

### Checking the voice without playing it

`spk silent on` runs the whole pipeline at the real volume but sends zeros to the amp. `spk capture on` records every sample the amp would get, for the latest stream, and `spk dump` prints it as numbered base64 lines. `tools/audio/voice_check.py` reads a console log with dumps, saves each reply as a WAV and measures clicks, abrupt dropouts, clipping, level and band balance; with `--reference` it fetches the same sentence from Fish directly and measures that too, so the board's output can be told apart from the voice model's.

```
python tools/cloud/console_session.py --out logs/voice.txt "spk silent on" "spk capture on" "vol 100" "ask Tell me a story." "spk dump"
python tools/audio/voice_check.py logs/voice.txt --reference
```

The guard also has a history: set at 2 s and -6 dBFS for the first voice, it tripped on the denser Orion Voice with emotion tags and cut the speaker to near silence mid sentence. It now needs 4 s above -5 dBFS, which speech does not reach and a stuck tone does after about 7 s, and it only ever turns the sound down by 12 dB, never off.

### Earcons

Played from `/assets/earcons/`. All spoken ones are Orion Voice in Modern Standard Arabic, peak normalised to -1 dBFS; the chime is generated.

| File | When | Says | Length |
|---|---|---|---|
| `wake.wav` | the wake word, a tap, the button | a two tone chime | 0.40 s |
| `repeat.wav` | nothing heard, or an empty transcript | "عذراً، هل يمكنك الإعادة؟" | 2.1 s |
| `offline.wav` | a wake with no network | "لا يوجد اتصال بالإنترنت حالياً." | 2.3 s |
| `error.wav` | anything else that failed, or the 30 s deadline | "عذراً، حدث خطأ ما. حاول مرة أخرى." | 3.0 s |
| `thinking.wav` | not used by the state machine today | "لحظة من فضلك." | 1.2 s |

The chime is two tones a fifth apart (E5, then B5 entering 90 ms later so they ring together), 6 ms attack and an exponential settle over 400 ms, the brand's motion curve written as sound. It is generated locally because waking up must not depend on the network, cost credit, or take time. It peaks at -1.5 dBFS.

There is no spoken "ok" after the user stops talking. It added half a second of speech before every answer and was removed.

The spoken earcons were chosen by measurement: each line was generated twice plain and twice with an emotion tag, every take transcribed, and the tagged take kept only if it did not leak the tag and cost no more than 0.06 in character error rate. `tools/cloud/make_earcons.py` regenerates them.

## Testing audio from the console

| Command | What it proves |
|---|---|
| `tone 1000 500` | the speaker path, a sine |
| `selftest` | speaker to mic: plays a 1 kHz tone and checks the mic hears it (quiet RMS, RMS during the tone, share of energy at 1 kHz). A healthy board reads about 98 percent at 1 kHz and a 19x ratio. |
| `wav speaker_check.wav` | a 4.9 s speech clip through the playback path |
| `mic` | floor, last RMS, level, chunk and drop counters |
| `micmon 8` | RMS every 250 ms for 8 s |
| `loopback 3` | records 3 s and plays it back |
| `record` | one utterance with the end of speech detector, played back |
| `spk stats` | loudness numbers for the last stream |

See [FIRMWARE_CONSOLE.md](FIRMWARE_CONSOLE.md) for all of them.
