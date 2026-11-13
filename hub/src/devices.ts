// Paired devices and pairing requests:
//
// - The first device a new hub sees becomes the owner and gets its token at once. The hub is then
//   claimed for good (devices.json keeps "claimed"), so with every device removed it does not hand
//   the owner slot to the next asker: the token drives an agent with root on the server.
// - Every later device waits up to 5 minutes for a paired device (or the CLI on the hub) to approve it.
// - Tokens are random, shown once, and stored only as SHA-256 hashes in devices.json.
// - A devices.json that exists but cannot be read stops all pairing, so a broken file never hands the
//   owner slot to whoever asks first.

import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname } from 'node:path'

export type DeviceKind = 'board' | 'app' | 'cli'

export interface Device {
  id: string
  name: string
  kind: DeviceKind
  token_sha256: string
  created: string
  owner: boolean
  last_seen?: string
  // The device's own stable id ("orion-a1b2"), when it sends one. Pairing
  // again with the same one replaces the old entry instead of adding another.
  hw?: string
}

export interface PendingRequest {
  id: string
  // 4 digits the requesting device shows on its own screen, so the person approving can match them.
  code: string
  name: string
  kind: DeviceKind
  hw?: string
  created: number
  status: 'pending' | 'approved' | 'denied'
  // Handed out once, to the first poll after approval, then forgotten.
  token?: string
  deviceId?: string
}

export const PENDING_TTL_MS = 5 * 60 * 1000
const MAX_PENDING = 8
const NAME_MAX = 48

export class PairingError extends Error {
  constructor(readonly status: number, message: string) {
    super(message)
  }
}

function sha256(s: string): string {
  return createHash('sha256').update(s).digest('hex')
}

function cleanName(name: unknown): string {
  const s = typeof name === 'string' ? name : ''
  const t = s.replace(/[\u0000-\u001f\u007f]/g, '').trim().slice(0, NAME_MAX)
  return t || 'Unnamed device'
}

function cleanHw(hw: unknown): string | undefined {
  return typeof hw === 'string' && /^[A-Za-z0-9_.:-]{1,40}$/.test(hw) ? hw : undefined
}

function cleanKind(kind: unknown): DeviceKind {
  return kind === 'board' || kind === 'app' || kind === 'cli' ? kind : 'app'
}

export class DeviceStore {
  private devices: Device[] = []
  private pending = new Map<string, PendingRequest>()
  private broken = false
  private claimed = false

  constructor(private readonly file: string, private readonly now: () => number = Date.now) {
    this.load()
  }

  private load(): void {
    if (!existsSync(this.file)) return
    try {
      const data = JSON.parse(readFileSync(this.file, 'utf8')) as { claimed?: unknown; devices?: Device[] }
      if (!Array.isArray(data.devices)) throw new Error('no devices list')
      this.devices = data.devices.filter((d) => d && typeof d.token_sha256 === 'string' && typeof d.id === 'string')
      // A file from before the flag counts as claimed when it lists any device.
      this.claimed = data.claimed === true || this.devices.length > 0
    } catch (e) {
      // Refuse pairing rather than treat the hub as unpaired.
      this.broken = true
      console.error(`[devices] ${this.file} cannot be read (${(e as Error).message}); pairing is refused until it is fixed or deleted`)
    }
  }

  private save(): void {
    mkdirSync(dirname(this.file), { recursive: true })
    const tmp = `${this.file}.tmp`
    writeFileSync(tmp, JSON.stringify({ claimed: this.claimed, devices: this.devices }, null, 2), { mode: 0o600 })
    renameSync(tmp, this.file)
  }

  get isBroken(): boolean {
    return this.broken
  }

  get isClaimed(): boolean {
    return this.claimed
  }

  count(): number {
    return this.devices.length
  }

  list(): Omit<Device, 'token_sha256'>[] {
    return this.devices.map(({ token_sha256: _t, ...rest }) => rest)
  }

  authenticate(token: string | undefined): Device | undefined {
    if (!token) return undefined
    const h = Buffer.from(sha256(token), 'hex')
    for (const d of this.devices) {
      const k = Buffer.from(d.token_sha256, 'hex')
      if (k.length === h.length && timingSafeEqual(k, h)) {
        d.last_seen = new Date(this.now()).toISOString()
        return d
      }
    }
    return undefined
  }

  private expire(): void {
    const t = this.now()
    for (const [id, r] of this.pending) {
      // Approved requests are kept until their token is picked up, but not forever.
      if (t - r.created > PENDING_TTL_MS) this.pending.delete(id)
    }
  }

  private addDevice(name: string, kind: DeviceKind, owner: boolean, hw?: string): { device: Device; token: string } {
    const token = randomBytes(32).toString('base64url')
    // The same device pairing again (after a forget or a reset): its old
    // entry and token go, and it keeps ownership if it had it.
    const old = hw ? this.devices.filter((x) => x.hw === hw && x.kind === kind) : []
    if (old.length) {
      owner ||= old.some((x) => x.owner)
      this.devices = this.devices.filter((x) => !old.includes(x))
      console.log(`[devices] ${name} paired again, ${old.length} old entr${old.length === 1 ? 'y' : 'ies'} replaced`)
    }
    // A device approved on a claimed hub that has none left becomes its owner.
    owner ||= !this.devices.some((x) => x.owner)
    this.claimed = true
    const device: Device = {
      id: randomBytes(6).toString('hex'),
      name,
      kind,
      token_sha256: sha256(token),
      created: new Date(this.now()).toISOString(),
      owner,
      ...(hw ? { hw } : {}),
    }
    this.devices.push(device)
    this.save()
    return { device, token }
  }

  // POST /api/v1/pair/request
  request(nameIn: unknown, kindIn: unknown, hwIn?: unknown):
    | { status: 'approved'; token: string; device_id: string; owner: true }
    | { status: 'pending'; request_id: string; code: string; expires_in: number } {
    if (this.broken) throw new PairingError(503, 'devices.json cannot be read; fix or delete it on the hub')
    const name = cleanName(nameIn)
    const kind = cleanKind(kindIn)
    const hw = cleanHw(hwIn)
    if (this.devices.length === 0 && !this.claimed) {
      const { device, token } = this.addDevice(name, kind, true, hw)
      console.log(`[devices] ${name} (${kind}) is the owner`)
      return { status: 'approved', token, device_id: device.id, owner: true }
    }
    this.expire()
    if ([...this.pending.values()].filter((r) => r.status === 'pending').length >= MAX_PENDING) {
      throw new PairingError(429, 'too many pairing requests waiting')
    }
    const req: PendingRequest = {
      id: randomBytes(16).toString('base64url'),
      code: String(randomInt(0, 10000)).padStart(4, '0'),
      name,
      kind,
      ...(hw ? { hw } : {}),
      created: this.now(),
      status: 'pending',
    }
    this.pending.set(req.id, req)
    console.log(`[devices] ${name} (${kind}) asks to pair, code ${req.code}`)
    return { status: 'pending', request_id: req.id, code: req.code, expires_in: Math.round(PENDING_TTL_MS / 1000) }
  }

  // GET /api/v1/pair/request/:id. The request id is the secret here: only the asker knows it.
  poll(id: string): { status: 'pending' | 'denied' | 'expired' } | { status: 'approved'; token: string; device_id: string } {
    this.expire()
    const r = this.pending.get(id)
    if (!r) return { status: 'expired' }
    if (r.status === 'approved' && r.token && r.deviceId) {
      const out = { status: 'approved' as const, token: r.token, device_id: r.deviceId }
      this.pending.delete(id)
      return out
    }
    if (r.status === 'denied') {
      this.pending.delete(id)
      return { status: 'denied' }
    }
    return { status: 'pending' }
  }

  listPending(): { id: string; code: string; name: string; kind: DeviceKind; age_s: number }[] {
    this.expire()
    const t = this.now()
    return [...this.pending.values()]
      .filter((r) => r.status === 'pending')
      .map((r) => ({ id: r.id, code: r.code, name: r.name, kind: r.kind, age_s: Math.round((t - r.created) / 1000) }))
  }

  private findPending(idOrCode: string): PendingRequest {
    this.expire()
    const byId = this.pending.get(idOrCode)
    if (byId && byId.status === 'pending') return byId
    const byCode = [...this.pending.values()].filter((r) => r.status === 'pending' && r.code === idOrCode)
    if (byCode.length === 1) return byCode[0]!
    if (byCode.length > 1) throw new PairingError(409, 'several requests share that code, use the request id')
    throw new PairingError(404, 'no such pairing request')
  }

  approve(idOrCode: string): { device_id: string; name: string } {
    const r = this.findPending(idOrCode)
    const { device, token } = this.addDevice(r.name, r.kind, false, r.hw)
    r.status = 'approved'
    r.token = token
    r.deviceId = device.id
    console.log(`[devices] approved ${r.name} (${r.kind})`)
    return { device_id: device.id, name: device.name }
  }

  deny(idOrCode: string): void {
    const r = this.findPending(idOrCode)
    r.status = 'denied'
    console.log(`[devices] denied ${r.name}`)
  }

  remove(id: string): boolean {
    const before = this.devices.length
    this.devices = this.devices.filter((d) => d.id !== id)
    if (this.devices.length === before) return false
    // The oldest device inherits ownership. With none left the hub stays claimed: the next device
    // needs approval.
    if (this.devices.length && !this.devices.some((d) => d.owner)) this.devices[0]!.owner = true
    this.save()
    return true
  }

  flushLastSeen(): void {
    if (this.devices.length) this.save()
  }
}
