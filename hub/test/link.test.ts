import assert from 'node:assert/strict'
import { mkdtempSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { hubId } from '../src/link.js'

const dir = () => mkdtempSync(join(tmpdir(), 'hub-link-'))

test('the hub id is made once and kept across restarts', () => {
  const d = dir()
  const a = hubId(d)
  assert.match(a, /^hub-[0-9a-f]{12}$/)
  assert.equal(hubId(d), a)
})

test('two hubs get different ids', () => {
  assert.notEqual(hubId(dir()), hubId(dir()))
})

test('a broken identity file gets a new, valid id instead of crashing', () => {
  const d = dir()
  writeFileSync(join(d, 'identity.json'), '{ not json')
  assert.match(hubId(d), /^hub-[0-9a-f]{12}$/)
  writeFileSync(join(d, 'identity.json'), JSON.stringify({ id: '../../etc' }))
  assert.match(hubId(d), /^hub-[0-9a-f]{12}$/)
})
