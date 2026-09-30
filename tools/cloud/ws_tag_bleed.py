# On Fish's live WebSocket TTS, does a tag on one sentence colour the next?
#
# Two sentences go in as separate text events with a flush between them, so
# the audio for sentence two arrives after the flush and can be measured on its
# own. The first sentence is sent with and without [whispering]; if the second
# sentence also comes out whispered when only the first was tagged, the tag
# bleeds across text events.
#
#   python tools/cloud/ws_tag_bleed.py

import asyncio
import math
import sys
from pathlib import Path

import msgpack
from websockets.asyncio.client import connect

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cloud_api as c

URL = "wss://api.fish.audio/v1/tts/live"
ONE = "هاد سر صغير بيني وبينك."
TWO = "وبكرا الصبح رح نحكي عن الموضوع كله بصراحة."


def rms_db(pcm):
    st = c.pcm_stats(pcm)
    return 20 * math.log10(max(st["rms"], 1) / 32767.0)


async def run(first):
    headers = {"Authorization": "Bearer " + c.env("FISH_API_KEY"),
               "model": c.env("FISH_TTS_MODEL", "s2.1-pro-free")}
    parts = [bytearray(), bytearray()]
    async with connect(URL, additional_headers=headers, max_size=None) as ws:
        await ws.send(msgpack.packb({"event": "start", "request": {
            "text": "", "reference_id": c.env("FISH_VOICE_ID") or None, "format": "pcm",
            "sample_rate": 16000, "latency": "balanced"}}, use_bin_type=True))
        await ws.send(msgpack.packb({"event": "text", "text": first}, use_bin_type=True))
        await ws.send(msgpack.packb({"event": "flush"}, use_bin_type=True))
        # Sentence one is over when the socket has been quiet for 1.5 s. Only
        # then does sentence two go in, so nothing of one is counted as two.
        while True:
            try:
                msg = await asyncio.wait_for(ws.recv(), 1.5 if parts[0] else 15)
            except asyncio.TimeoutError:
                break
            d = msgpack.unpackb(msg, raw=False)
            if d.get("event") == "audio":
                parts[0] += d["audio"]
        await ws.send(msgpack.packb({"event": "text", "text": TWO}, use_bin_type=True))
        await ws.send(msgpack.packb({"event": "stop"}, use_bin_type=True))
        async for msg in ws:
            d = msgpack.unpackb(msg, raw=False)
            if d.get("event") == "audio":
                parts[1] += d["audio"]
            elif d.get("event") == "finish":
                break
    return bytes(parts[0]), bytes(parts[1])


async def main():
    rows = []
    for label, first in (("plain", ONE), ("[whispering]", "[whispering] " + ONE)):
        for _ in range(2):
            a, b = await run(first)
            rows.append((label, rms_db(a), rms_db(b), len(b) / 32000.0))
    print("| sentence one | its rms dBFS | sentence two rms dBFS | two, seconds |")
    print("|---|---|---|---|")
    for label, ra, rb, secs in rows:
        print("| %s | %.1f | %.1f | %.2f |" % (label, ra, rb, secs))


if __name__ == "__main__":
    asyncio.run(main())
