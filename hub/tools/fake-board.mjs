// A stand-in for an Orion board, for testing a hub from a PC: pairs like the firmware does and sends
// turns the way the board's cloud_reply.c does, then checks the stream against the board's rules
// (docs/DEVICE_PROTOCOL.md, "Board to brain").
//
//   node tools/fake-board.mjs <hub url> pair [name]           pairs, prints the token file it wrote
//   node tools/fake-board.mjs <hub url> ask "<text>" [...]    one turn per argument, in order
//
// The token is kept in ./fake-board.token (or $FAKE_BOARD_TOKEN_FILE).

import { existsSync, readFileSync, writeFileSync } from 'node:fs'

const [hub, cmd, ...args] = process.argv.slice(2)
const TOKEN_FILE = process.env.FAKE_BOARD_TOKEN_FILE ?? './fake-board.token'
if (!hub || !cmd) {
  console.error('usage: fake-board.mjs <hub url> pair [name] | ask "<text>" ...')
  process.exit(2)
}

async function pair(name) {
  const r = await fetch(`${hub}/api/v1/pair/request`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, kind: 'board' }),
  })
  let j = await r.json()
  if (!r.ok) throw new Error(`pair: HTTP ${r.status} ${JSON.stringify(j)}`)
  if (j.status === 'pending') {
    console.log(`waiting for approval, code ${j.code}`)
    const id = j.request_id
    for (let i = 0; i < 150 && j.status === 'pending'; i++) {
      await new Promise((ok) => setTimeout(ok, 2000))
      j = await (await fetch(`${hub}/api/v1/pair/request/${id}`)).json()
    }
  }
  if (j.status !== 'approved') throw new Error(`pair: ${j.status}`)
  writeFileSync(TOKEN_FILE, j.token, { mode: 0o600 })
  console.log(`paired as ${name}, device ${j.device_id}${j.owner ? ' (owner)' : ''}; token in ${TOKEN_FILE}`)
}

function boardBody(text) {
  const now = new Date()
  const clock = now.toLocaleString('en-GB', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' })
  return {
    model: 'google/gemma-4-31B-it-turbo', stream: true, max_tokens: 200, temperature: 0.6,
    messages: [
      { role: 'system', content: `You are Orion, a voice assistant.\n\nCurrent local date and time: ${clock}.` },
      { role: 'user', content: text },
    ],
    tools: [{ type: 'function', function: { name: 'look', description: 'Take a picture', parameters: { type: 'object', properties: {} } } }],
    tool_choice: 'auto',
  }
}

// Reads the stream 128 bytes at a time, like the board, and checks every frame.
async function ask(text) {
  const token = readFileSync(TOKEN_FILE, 'utf8').trim()
  const t0 = Date.now()
  const r = await fetch(`${hub}/v1/chat/completions`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(boardBody(text)),
  })
  const problems = []
  if (r.status !== 200) {
    console.log(`> ${text}\n  HTTP ${r.status}: ${await r.text()}`)
    return { ok: false, status: r.status }
  }
  const reader = r.body.getReader()
  const dec = new TextDecoder()
  let buf = ''
  let spoken = ''
  let first = 0
  let fillerAt = 0
  let keepAlives = 0
  let listen = false
  let done = false
  let events = 0
  let lastByte = Date.now()
  let maxGap = 0
  for (;;) {
    const { value, done: end } = await reader.read()
    if (end) break
    const now = Date.now()
    maxGap = Math.max(maxGap, now - lastByte)
    lastByte = now
    buf += dec.decode(value, { stream: true })
    let i
    while ((i = buf.indexOf('\n\n')) >= 0) {
      const frame = buf.slice(0, i)
      buf = buf.slice(i + 2)
      if (frame.startsWith(':')) {
        keepAlives++
        if (Buffer.byteLength(frame + '\n\n') !== 128) problems.push(`keep-alive of ${Buffer.byteLength(frame + '\n\n')} bytes`)
        continue
      }
      if (!frame.startsWith('data: ')) { problems.push(`odd frame ${frame.slice(0, 40)}`); continue }
      if (Buffer.byteLength(frame) >= 1024) problems.push('event over the 1 KB line buffer')
      const data = frame.slice(6)
      events++
      if (data === '[DONE]') { done = true; continue }
      const j = JSON.parse(data)
      if (events === 1 && j.choices?.[0]?.delta?.content !== '') problems.push('no empty opener first')
      if (j.orion_listen) listen = true
      const c = j.choices?.[0]?.delta?.content
      if (c) {
        if (!first) first = Date.now() - t0
        if (!spoken && /One moment|لحظة/.test(c)) fillerAt = Date.now() - t0
        spoken += c
      }
    }
  }
  if (!done) problems.push('no [DONE]')
  if (maxGap > 3500) problems.push(`a silence of ${maxGap} ms (the board wants life every 3 s)`)
  const total = Date.now() - t0
  console.log(`> ${text}\n  "${spoken.trim()}"\n  first words ${first} ms, total ${total} ms${fillerAt ? `, filler at ${fillerAt} ms` : ''}, ${keepAlives} keep-alives, max gap ${maxGap} ms${listen ? ', LISTEN' : ''}${problems.length ? `\n  PROBLEMS: ${problems.join('; ')}` : ''}`)
  return { ok: !problems.length, spoken: spoken.trim(), listen, total, first }
}

if (cmd === 'pair') {
  await pair(args[0] ?? 'Fake board')
} else if (cmd === 'ask') {
  if (!existsSync(TOKEN_FILE)) throw new Error('pair first')
  let failed = 0
  for (const text of args) {
    const r = await ask(text)
    if (!r.ok) failed++
  }
  process.exitCode = failed ? 1 : 0
} else {
  console.error(`unknown command ${cmd}`)
  process.exit(2)
}
