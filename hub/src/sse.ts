// The answer stream to a board, OpenAI SSE with the board's rules (docs/DEVICE_PROTOCOL.md):
//
// - an empty opening event first, or ESP-IDF's HTTP client loses the first word;
// - the board reads 128 bytes at a time, so a keep-alive is an SSE comment padded to exactly 128 bytes;
// - some bytes at least every 3 s, because the board's 30 s deadline counts from the last read;
// - text events stay well under the board's 1 KB line buffer;
// - "orion_listen": true before [DONE] when the answer asks the user something, so the board listens again
//   without the wake word;
// - a failed turn ends with an error event and no [DONE] while nothing has been said: only then does the
//   board hand the turn to its next brain.

import type { ServerResponse } from 'node:http'

const READ = 128
const KEEPALIVE_MS = 3000
const PIECE_CHARS = 160

export function keepAliveFrame(): string {
  const head = ': working'
  return head + ' '.repeat(READ - head.length - 2) + '\n\n'
}

function event(obj: unknown): string {
  return `data: ${JSON.stringify(obj)}\n\n`
}

export function textEvents(text: string): string[] {
  const out: string[] = []
  // Split at spaces so every event carries whole words.
  let rest = text
  while (rest.length > PIECE_CHARS) {
    let cut = rest.lastIndexOf(' ', PIECE_CHARS)
    if (cut < PIECE_CHARS / 2) cut = PIECE_CHARS
    out.push(rest.slice(0, cut + 1))
    rest = rest.slice(cut + 1)
  }
  if (rest) out.push(rest)
  return out.map((t) => event({ choices: [{ index: 0, delta: { content: t }, finish_reason: null }] }))
}

export class VoiceStream {
  private timer?: NodeJS.Timeout
  private closed = false
  private spoke = false

  constructor(private readonly res: ServerResponse) {}

  open(): void {
    this.res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    })
    this.res.on('close', () => this.stop())
    this.write(event({ choices: [{ index: 0, delta: { role: 'assistant', content: '' }, finish_reason: null }] }))
    this.timer = setInterval(() => this.write(keepAliveFrame()), KEEPALIVE_MS)
  }

  get isClosed(): boolean {
    return this.closed || this.res.destroyed
  }

  private write(s: string): void {
    if (!this.isClosed) this.res.write(s)
  }

  // A filler goes out with a keep-alive right after it, so the board reads it at once instead of
  // holding a short piece back.
  say(text: string): void {
    if (!text) return
    this.spoke = true
    for (const e of textEvents(text.endsWith(' ') ? text : `${text} `)) this.write(e)
    this.write(keepAliveFrame())
  }

  finish(listen: boolean): void {
    if (this.isClosed) return
    this.stop()
    if (listen) this.write(event({ choices: [{ index: 0, delta: {}, finish_reason: null }], orion_listen: true }))
    this.write(event({ choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }))
    this.write('data: [DONE]\n\n')
    this.res.end()
    this.closed = true
  }

  // Ends a turn that failed. Before anything was said, an error event and no [DONE] make the board hand
  // the turn to its next brain. Once the filler is out it can no longer do that, so the user hears the
  // apology instead.
  fail(apology: string, why: string): void {
    if (this.isClosed) return
    if (this.spoke) {
      this.say(apology)
      this.finish(false)
      return
    }
    this.stop()
    this.write(event({ error: { message: why.slice(0, 200) } }))
    this.res.end()
    this.closed = true
  }

  private stop(): void {
    if (this.timer) clearInterval(this.timer)
    this.timer = undefined
  }
}
