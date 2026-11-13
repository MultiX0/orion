import assert from 'node:assert/strict'
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

import { DeviceStore, PENDING_TTL_MS, PairingError } from '../src/devices.js'

const file = () => join(mkdtempSync(join(tmpdir(), 'hub-')), 'devices.json')

test('the first device becomes the owner at once', () => {
  const s = new DeviceStore(file())
  const r = s.request('Desk board', 'board')
  assert.equal(r.status, 'approved')
  if (r.status !== 'approved') return
  assert.ok(r.token.length > 30)
  assert.equal(s.authenticate(r.token)?.owner, true)
  assert.equal(s.authenticate('wrong'), undefined)
  assert.equal(s.authenticate(undefined), undefined)
})

test('tokens are stored only as hashes', () => {
  const f = file()
  const s = new DeviceStore(f)
  const r = s.request('Board', 'board')
  assert.equal(r.status, 'approved')
  if (r.status !== 'approved') return
  assert.ok(!readFileSync(f, 'utf8').includes(r.token))
  // and they survive a restart
  assert.ok(new DeviceStore(f).authenticate(r.token))
})

test('a later device waits for approval, then picks up its token once', () => {
  const s = new DeviceStore(file())
  s.request('Owner', 'app')
  const p = s.request('Kitchen board', 'board')
  assert.equal(p.status, 'pending')
  if (p.status !== 'pending') return
  assert.match(p.code, /^\d{4}$/)
  assert.deepEqual(s.poll(p.request_id), { status: 'pending' })
  assert.equal(s.listPending().length, 1)
  s.approve(p.code)
  const got = s.poll(p.request_id)
  assert.equal(got.status, 'approved')
  if (got.status !== 'approved') return
  assert.equal(s.authenticate(got.token)?.name, 'Kitchen board')
  // the token is handed out only once
  assert.equal(s.poll(p.request_id).status, 'expired')
})

test('a denied device is told so, and an old request expires', () => {
  let now = 1_000_000
  const s = new DeviceStore(file(), () => now)
  s.request('Owner', 'app')
  const a = s.request('Stranger', 'board')
  const b = s.request('Late', 'board')
  if (a.status !== 'pending' || b.status !== 'pending') throw new Error('expected pending')
  s.deny(a.request_id)
  assert.equal(s.poll(a.request_id).status, 'denied')
  now += PENDING_TTL_MS + 1
  assert.equal(s.poll(b.request_id).status, 'expired')
  assert.throws(() => s.approve(b.code), (e: unknown) => e instanceof PairingError && e.status === 404)
})

test('a broken devices.json refuses pairing instead of handing out the owner slot', () => {
  const f = file()
  writeFileSync(f, '{ not json')
  const s = new DeviceStore(f)
  assert.equal(s.isBroken, true)
  assert.throws(() => s.request('Anyone', 'board'), (e: unknown) => e instanceof PairingError && e.status === 503)
})

test('removing the owner passes ownership on', () => {
  const s = new DeviceStore(file())
  const o = s.request('Owner', 'app')
  const p = s.request('Board', 'board')
  if (o.status !== 'approved' || p.status !== 'pending') throw new Error('setup')
  const { device_id } = s.approve(p.request_id)
  assert.equal(s.remove(o.device_id), true)
  assert.equal(s.list().find((d) => d.id === device_id)?.owner, true)
  assert.equal(s.remove('000000000000'), false)
})

test('names are cleaned and kinds are checked', () => {
  const s = new DeviceStore(file())
  s.request('  \u0000Bad\u0007 name ' + 'x'.repeat(100), 'toaster')
  const d = s.list()[0]!
  assert.equal(d.kind, 'app')
  assert.ok(d.name.length <= 48 && !/[\u0000-\u001f]/.test(d.name))
})

test('too many waiting requests are refused', () => {
  const s = new DeviceStore(file())
  s.request('Owner', 'app')
  for (let i = 0; i < 8; i++) s.request(`B${i}`, 'board')
  assert.throws(() => s.request('One more', 'board'), (e: unknown) => e instanceof PairingError && e.status === 429)
})

test('the same board pairing again replaces its old entry, and keeps ownership', () => {
  const s = new DeviceStore(file())
  const first = s.request('Orion A1B2', 'board', 'orion-a1b2')
  assert.equal(first.status, 'approved')
  if (first.status !== 'approved') return
  const other = s.request('Phone', 'app')
  assert.equal(other.status, 'pending')
  if (other.status !== 'pending') return
  s.approve(other.request_id)
  // forgot the hub, pairs again: a pending request, approved
  const again = s.request('Orion A1B2', 'board', 'orion-a1b2')
  assert.equal(again.status, 'pending')
  if (again.status !== 'pending') return
  s.approve(again.code)
  const got = s.poll(again.request_id)
  assert.equal(got.status, 'approved')
  if (got.status !== 'approved') return
  const boards = s.list().filter((d) => d.kind === 'board')
  assert.equal(boards.length, 1)
  assert.equal(boards[0]!.owner, true)
  assert.equal(s.authenticate(first.token), undefined)
  assert.ok(s.authenticate(got.token))
  // a bad hardware id is ignored, not stored
  const bad = s.request('X', 'board', 'has spaces and / slashes')
  assert.equal(bad.status, 'pending')
  if (bad.status !== 'pending') return
  s.approve(bad.request_id)
  assert.equal(s.list().find((d) => d.name === 'X')?.hw, undefined)
  // an app with the same hw as a board does not replace the board
  const app = s.request('Same id app', 'app', 'orion-a1b2')
  if (app.status !== 'pending') return
  s.approve(app.request_id)
  assert.equal(s.list().filter((d) => d.kind === 'board' && d.hw === 'orion-a1b2').length, 1)
})

test('a hub stays claimed after its last device is removed, also across a restart', () => {
  const f = file()
  const s = new DeviceStore(f)
  const o = s.request('Desk board', 'board')
  if (o.status !== 'approved') throw new Error('setup')
  assert.equal(s.isClaimed, true)
  assert.equal(JSON.parse(readFileSync(f, 'utf8')).claimed, true)
  assert.equal(s.remove(o.device_id), true)
  assert.equal(s.count(), 0)
  // nobody gets the owner slot by asking
  assert.equal(s.request('Stranger', 'board').status, 'pending')
  const again = new DeviceStore(f)
  assert.equal(again.isClaimed, true)
  const p = again.request('Kitchen board', 'board')
  assert.equal(p.status, 'pending')
  if (p.status !== 'pending') return
  // approved on the hub, it becomes the owner of the empty hub
  again.approve(p.code)
  assert.equal(again.list()[0]?.owner, true)
})

test('a devices.json from before the claimed flag counts as claimed when it lists devices', () => {
  const f = file()
  const old = { devices: [{ id: 'a1b2c3d4e5f6', name: 'Old board', kind: 'board', token_sha256: '00'.repeat(32), created: '2026-10-01T00:00:00.000Z', owner: true }] }
  writeFileSync(f, JSON.stringify(old))
  const s = new DeviceStore(f)
  assert.equal(s.isClaimed, true)
  s.remove('a1b2c3d4e5f6')
  assert.equal(s.request('Anyone', 'board').status, 'pending')
  // an old file with no devices is a new hub
  const g = file()
  writeFileSync(g, JSON.stringify({ devices: [] }))
  const t = new DeviceStore(g)
  assert.equal(t.isClaimed, false)
  assert.equal(t.request('First', 'board').status, 'approved')
})
