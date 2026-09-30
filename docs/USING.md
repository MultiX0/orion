# Using Orion

## Talking to it

| You | Orion |
|---|---|
| Say **"Orion"** | Chimes, the star lights up and listens |
| Tap the screen | Same as the wake word |
| Short press on the side button (IO17) | Same as the wake word |
| Tap while it is talking | Stops talking |
| Long press on the side button (0.7 s) | Cancels the turn, back to idle |
| Long press on the screen | Opens the menu |

You can say the question in the same breath as the name: "Orion, what's the weather in Amman?" The recording starts at the wake word, so the first word is not lost. Orion stops listening after about 600 ms of silence, and never records for more than 10 seconds.

To stop Orion listening for its name, turn off **Wake word** in the app under Settings, Device. The idle screen then asks for a touch, and a tap or the side button still starts a turn. The board's clock takes its time zone from the same page: Automatic follows the phone or PC the app runs on, or pick a fixed offset.

If it heard nothing, it says "عذراً، هل يمكنك الإعادة؟" (sorry, could you say that again?). If the network is down, it says there is no internet. Anything else that fails gets a short apology.

There is one microphone and no echo cancellation, so the microphone is muted while Orion speaks. To interrupt, tap the screen.

## Languages

Orion speaks fluent Modern Standard Arabic in the friendly register of a phone assistant, and English. It answers in the language you spoke: any Arabic words in your question make the answer Arabic, an English question gets an English answer. English tech and brand names stay in Latin letters inside Arabic sentences (Spotify, Wi-Fi, YouTube). It speaks as a woman and says its own name the English way, "Orion".

The wake word was trained on both أوريون and Orion, spoken by many Arabic and English voices, including the spellings اورايون and أورايون.

## What it can do

On its own, with only Wi-Fi:

- Answer questions in one or two short sentences, spoken aloud and shown on the screen.
- Tell the date and time. The board keeps its own clock from the internet.
- Look through its camera. Ask "what do you see?", "what is this?", "شو هاد؟" or "ما هذا؟" and it takes a picture before answering. The camera is on the back of the board, facing away from you, so hold the thing up behind it.
- Remember the last six exchanges while it stays on.

It cannot set reminders, alarms or timers, and it says so rather than pretending.

With the **Orion app open on a Windows PC** and PC control on:

- Everything above, plus web search, weather for any city, and a memory of the conversation that survives restarts.
- Work the PC: open and close apps, play and pause music, find a song on Spotify or YouTube, search in Chrome, type into apps, read what an app shows, lock the PC, report CPU, RAM and GPU load, find files, take and describe a screenshot. "Open Spotify", then an hour later "play Lifetime by Chris Grey", goes to Spotify.
- Longer tasks take 10 to 60 seconds. Orion says "One moment, I'm on it." and keeps working until the task is done, then says what happened.

With the **Orion app open on a phone**:

- Web search, weather, the date, a memory of the conversation, and opening links and apps on the phone ("open YouTube", a song in Spotify).
- On Android the phone keeps helping while another app is in front, with a notification "Orion is thinking on this phone". On iOS it helps while the app is open.

If both are linked, the PC answers first. See [HARNESS.md](HARNESS.md) for everything the PC and phone brains do and how to control what they are allowed to do.

## The screen

![Idle](images/board/idle.png) ![Listening](images/board/listening.png) ![Thinking](images/board/thinking.png) ![Speaking](images/board/speaking.png)

- **Idle.** The Orion star over a slow glow, and "قول أوريون، أو المس الشاشة" (say Orion, or touch the screen). Two small dots show which apps are linked right now: the phone and the PC.
- **Listening.** The star with rings rippling out, following your voice.
- **Thinking.** The star turns slowly inside two still rings.
- **Speaking.** Rings that follow Orion's own voice.
- **Error** and **offline** use the plain orb, desaturated.

What you said and Orion's answer appear under the star, in Arabic or English, scrolling when they are long. Voice cues like `[laugh]` or `[sigh]` are performed by the voice and never shown.

### The menu

The round button in the top left corner (or a long press anywhere) opens the menu. It closes itself after 20 seconds without a touch.

| Card | Shows | Button |
|---|---|---|
| الكمبيوتر (PC) | whether a PC brain is set up and answering, its address | تحديث (refresh): checks the PC again |
| الشبكة (Network) | signal, network name, IP address | إعداد الواي فاي (Wi-Fi setup): restarts into Bluetooth setup mode |
| الكاميرا (Camera) | a live preview from the camera, about 11 frames a second | |
| إعادة ضبط (Reset) | "erases the network, the keys and the devices, and goes back to first setup" | امسح كل شي: tap, then tap again within 4 s |

![Menu](images/board/menu-pc.png) ![Camera card](images/board/menu-camera.png)

## The app

| Screen | What it is for |
|---|---|
| Home | The orb, mirroring the board's state live, and the last exchange |
| Talk | Hold to talk, or type a question and send it to the board |
| Camera | Live video from the board, a snapshot you can save, and "Ask about this", which sends a picture with your question |
| Conversation | The turns since the board last started, with their timings |
| Providers | The language model (fast and thinking), speech to text and text to speech, with keys, model lists and a Test for each stage |
| Settings | Board name, volume, Wi-Fi, PC control mode, unpair, pair another Orion, about |
| Harness (Windows) | PC control: the live feed of tool calls, approvals waiting for you, and the state of the PC brain |

Screenshots of each are in the [README](../README.md).

## Everyday settings

- **Volume.** In the app's Settings, or `volume <0..100>` on the serial console. It is stored on the board and survives restarts.
- **Which models answer.** Providers in the app. Changes apply from the next turn, no restart. See [PROVIDERS.md](PROVIDERS.md).
- **PC control.** Settings or the Harness screen, on every platform: Off, Ask me first, Act on your own. The choice lives on the board, so the phone, the PC and the board always agree.
- **The voice and how Orion talks.** Orion Voice and the system prompt; see [VOICE.md](VOICE.md).

## Limits worth knowing

- The conversation list on the board holds the last 40 turns and is cleared on restart. The PC keeps its own longer memory.
- No barge-in by voice: tap to interrupt.
- No reminders, timers or alarms.
- The board is 2.4 GHz only.
- Orion Voice is tuned for Fish Audio. Another text to speech provider works, but emotion tags are dropped and the voice changes.
