import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import type { ServerResponse } from 'node:http'
import { test } from 'node:test'

import { VoiceStream } from '../src/sse.js'

// Just enough of a ServerResponse for VoiceStream: it records what the board would read.
class FakeResponse extends EventEmitter {
  body = ''
  ended = false
  destroyed = false
  writeHead(): this {
    return this
  }
  write(s: string): boolean {
    this.body += s
    return true
  }
  end(): void {
    this.ended = true
  }
}

function stream(): { res: FakeResponse; s: VoiceStream } {
  const res = new FakeResponse()
  const s = new VoiceStream(res as unknown as ServerResponse)
  s.open()
  return { res, s }
}

// The data lines, the way the board's parser sees them.
const dataLines = (body: string): string[] => body.split('\n').filter((l) => l.startsWith('data:'))

test('a turn that fails before anything was said ends with an error event and no [DONE]', () => {
  const { res, s } = stream()
  s.fail('Something went wrong on the hub.', 'dsh exited')
  assert.equal(res.ended, true)
  assert.ok(!res.body.includes('[DONE]'))
  assert.ok(!res.body.includes('Something went wrong'))
  const last = dataLines(res.body).at(-1)!
  // cloud_sse.c takes a line whose JSON starts with {"error" as a failed brain
  assert.match(last, /^data: \{"error":/)
  assert.equal(JSON.parse(last.slice(6)).error.message, 'dsh exited')
  // nothing more goes out once the stream is closed
  s.say('late words')
  assert.ok(!res.body.includes('late words'))
})

test('a turn that fails after the filler says the apology and finishes', () => {
  const { res, s } = stream()
  s.say("One moment, I'm working on it.")
  s.fail('Something went wrong on the hub.', 'dsh exited')
  assert.equal(res.ended, true)
  assert.ok(!res.body.includes('"error"'))
  const said = dataLines(res.body)
    .filter((l) => l.startsWith('data: {'))
    .map((l) => (JSON.parse(l.slice(6)) as { choices: { delta: { content?: string } }[] }).choices[0]!.delta.content ?? '')
    .join('')
  assert.match(said, /One moment.*Something went wrong on the hub\./)
  assert.ok(res.body.endsWith('data: [DONE]\n\n'))
})
