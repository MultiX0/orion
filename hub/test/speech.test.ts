import assert from 'node:assert/strict'
import { test } from 'node:test'

import { agentPrompt, filler, forSpeech, isArabic, readBoardTurn, wantsReply } from '../src/speech.js'
import { keepAliveFrame, textEvents } from '../src/sse.js'

test('markdown, code and links never reach the voice', () => {
  const s = forSpeech('## Result\n- **Jellyfin** is up\n- `nextcloud` restarted\n```\ndocker ps\n```\nSee [the docs](https://x.y/z) or https://a.b/c')
  assert.equal(s, 'Result Jellyfin is up nextcloud restarted See the docs or')
  assert.equal(forSpeech('Done.<|im_end|>'), 'Done.')
  assert.equal(forSpeech('All good <turn|>'), 'All good')
})

test('long answers are cut at a sentence end', () => {
  const long = 'This is one sentence. '.repeat(80)
  const s = forSpeech(long, 200)
  assert.ok(s.length <= 200)
  assert.ok(s.endsWith('.'))
})

test('a question at the end means listen for the reply', () => {
  assert.equal(wantsReply('I found the Pi at 192.168.1.40. Do you want me to log in?'), true)
  assert.equal(wantsReply('وجدت الجهاز. هل تريد أن أدخل إليه؟'), true)
  assert.equal(wantsReply('What is the password?"'), true)
  assert.equal(wantsReply('Is it on? I checked, it is on.'), false)
  assert.equal(wantsReply('Done.'), false)
})

test('arabic is detected for fillers', () => {
  assert.equal(isArabic('افحص الشبكة'), true)
  assert.equal(isArabic('scan the network'), false)
  // 15 speakable letters or more, or the board holds the filler back
  assert.ok(filler('scan').replace(/[^\p{L}]/gu, '').length >= 15)
  assert.ok(filler('افحص').replace(/[^\p{L}]/gu, '').length >= 15)
})

test('the board turn: last user message, its clock, and a picture', () => {
  const body = {
    messages: [
      { role: 'system', content: 'You are Orion...\n\nCurrent local date and time: Friday 06 November 2026, 09:12 in the morning (09:12).' },
      { role: 'user', content: 'hi' },
      { role: 'assistant', content: 'hello' },
      { role: 'user', content: [{ type: 'text', text: 'what is this' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } }] },
    ],
  }
  const t = readBoardTurn(body)!
  assert.equal(t.text, 'what is this')
  assert.deepEqual(t.image, { mimeType: 'image/jpeg', data: 'AAAA' })
  assert.match(t.localTime!, /^Friday 06 November 2026/)
  assert.match(agentPrompt(t, 'Desk'), /local time Friday/)
  assert.equal(readBoardTurn({ messages: [{ role: 'user', content: '   ' }] }), undefined)
  assert.equal(readBoardTurn({}), undefined)
  assert.equal(readBoardTurn(null), undefined)
})

test('keep-alives fill exactly one board read', () => {
  assert.equal(Buffer.byteLength(keepAliveFrame()), 128)
  assert.ok(keepAliveFrame().startsWith(':'))
})

test('text events stay under the board line buffer and keep words whole', () => {
  const text = 'word '.repeat(300) + 'تمام '.repeat(200)
  const evs = textEvents(text)
  let joined = ''
  for (const e of evs) {
    assert.ok(Buffer.byteLength(e) < 1024)
    assert.ok(e.startsWith('data: {'))
    joined += JSON.parse(e.slice(6)).choices[0].delta.content
  }
  assert.equal(joined, text)
})
