import assert from 'node:assert/strict'
import { test } from 'node:test'

import { maskSecrets, summarize } from '../src/brain.js'

test('the password of an orion-ssh login never reaches the audit log', () => {
  assert.equal(maskSecrets('orion-ssh login pi pi@192.168.1.40 hunter2'), 'orion-ssh login pi pi@192.168.1.40 ***')
  // a quoted password with a space, and the rest of that command line, go too
  const quoted = maskSecrets("orion-ssh login nas admin@192.168.1.40:2222 'correct horse' && orion-ssh run nas uptime")
  assert.ok(!/correct|horse/.test(quoted))
  // the next line of a script stays
  assert.equal(maskSecrets('orion-ssh login pi pi@192.168.1.40 hunter2\nuptime'), 'orion-ssh login pi pi@192.168.1.40 ***\nuptime')
  assert.equal(maskSecrets('which containers are running?'), 'which containers are running?')
})

test('a tool call event is masked inside its JSON-escaped arguments', () => {
  const command = `orion-ssh login nas admin@192.168.1.40 'pa ss"word'\necho done`
  const line = summarize({
    method: 'session.event',
    params: {
      sessionId: 'orion-a1b2c3d4e5f6',
      event: { type: 'tool/call', seq: 7, time: 0, data: { turn: 1, step: 1, callId: 'c1', name: 'bash', arguments: JSON.stringify({ command }) } },
    },
  })!
  assert.ok(line.startsWith('tool/call '))
  assert.ok(line.includes('orion-ssh login nas admin@192.168.1.40 ***'))
  assert.ok(!/pa ss|word'/.test(line))
  assert.ok(line.includes('echo done'))
})

test('fields named like a secret are masked, plain or escaped', () => {
  assert.equal(maskSecrets('{"token":"abc","name":"x"}'), '{"token":"***","name":"x"}')
  const escaped = maskSecrets(JSON.stringify({ arguments: JSON.stringify({ password: 'hunter2', apiKey: 'sk-1' }) }))
  assert.ok(!/hunter2|sk-1/.test(escaped))
})
