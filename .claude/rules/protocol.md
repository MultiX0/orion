---
paths:
  - "docs/DEVICE_PROTOCOL.md"
  - "docs/HARNESS.md"
  - "tool/mock_device/**"
  - "firmware/components/orion_api/**"
  - "firmware/components/orion_prov/**"
  - "firmware/components/orion_settings/**"
  - "lib/core/network/**"
  - "lib/features/device/**"
  - "lib/features/onboarding/data/**"
  - "lib/features/providers/data/**"
---

# Protocol rules

`docs/DEVICE_PROTOCOL.md` is the contract between the app and the board; `docs/HARNESS.md` is the one between the board and a PC or phone brain.

- Change the doc first, then the firmware, the app and `tool/mock_device` in the same piece of work. If one side cannot be done now, say so in the commit and the summary. The mock must implement everything the doc says so the app works with no board.
- Every endpoint but `GET /api/info` and `POST /api/pair` requires `X-Orion-Token` (`?token=` on `/ws` and `/stream`); a bad token is 401.
- `POST /api/config` merges partially. `api_key` omitted keeps the stored key, `""` clears it, anything else replaces it. Responses mask keys to the last four characters. The board refuses values with quotes, backslashes or control characters. Busy boards answer 409 and the app retries.
- Config version 2 has `llm`, `stt` and `tts` blocks; version 1 fields are still accepted so older apps keep working. Do not remove a fallback without a version bump in `/api/info`.
- Bluetooth: `orion-pair` is the first custom endpoint (0xFF54), `orion-config` the second (0xFF55), by creation order in `orion_prov`. Long `orion-config` bodies go in parts of 150 characters.
- WebSocket events all carry `type` and `ts`. The board sends a full `state` on connect, then deltas. Adding an event means adding it to `test/fixtures/ws_events.jsonl` and its parser test.
- Brain streams: 128 byte reads, padded keep-alives every 3 s, a 15 letter first piece, an empty `role` event first, control tokens dropped, a 30 s deadline counted from the last read.
- On the board, HTTP handlers run on a PSRAM stack: they never touch NVS; settings writes are posted to the event loop.
