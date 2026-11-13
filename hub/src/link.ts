// Orion Link (docs/ORION_LINK.md): how every node in the Orion ecosystem (boards, hubs, the
// desktop and phone apps) is known by a permanent id, and found again by it when its address
// changes. The hub's part: its id, the identity it answers at /.well-known/orion, and its
// presence beacon on UDP 7332, which nothing reads yet.

import { randomBytes } from 'node:crypto'
import { createSocket } from 'node:dgram'
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export const LINK_VERSION = 1
export const BEACON_PORT = 7332
const BEACON_EVERY_MS = 5000

export interface Identity {
  orion: number
  id: string
  kind: 'hub'
  name: string
  port: number
  version: string
}

const ID_RE = /^hub-[0-9a-f]{12}$/

/// The hub's id, made once and kept with its state, so it survives restarts, rebuilds and
/// address changes. A board stores it when it pairs.
export function hubId(stateDir: string): string {
  const file = join(stateDir, 'identity.json')
  if (existsSync(file)) {
    try {
      const id = (JSON.parse(readFileSync(file, 'utf8')) as { id?: unknown }).id
      if (typeof id === 'string' && ID_RE.test(id)) return id
    } catch {
      // Unreadable: the same as a file without a valid id, below.
    }
    // A broken file gets a new id. Boards paired with the old id no longer recognize this hub by mDNS
    // or a sweep, so after its next address change they must pair again.
    console.warn(`[link] ${file} has no valid id: this hub gets a new one, and paired boards must pair again if its address changes`)
  }
  const id = `hub-${randomBytes(6).toString('hex')}`
  mkdirSync(stateDir, { recursive: true })
  const tmp = `${file}.tmp`
  writeFileSync(tmp, JSON.stringify({ id }, null, 2))
  renameSync(tmp, file)
  return id
}

/// Broadcasts the hub's identity every few seconds for Orion Link listeners (docs/ORION_LINK.md).
/// The boards and the apps do not listen for it yet: a board finds its hub by mDNS on a Linux
/// server, and otherwise by sweeping its network for port 8780.
export function beacon(identity: () => Identity): () => void {
  const sock = createSocket({ type: 'udp4', reuseAddr: true })
  let timer: NodeJS.Timeout | undefined
  sock.on('error', (e) => console.error(`[link] beacon: ${e.message}`))
  sock.bind(() => {
    sock.setBroadcast(true)
    const send = (): void => {
      const msg = Buffer.from(JSON.stringify(identity()))
      sock.send(msg, BEACON_PORT, '255.255.255.255', (e) => {
        if (e) console.error(`[link] beacon: ${e.message}`)
      })
    }
    send()
    timer = setInterval(send, BEACON_EVERY_MS)
  })
  return () => {
    if (timer) clearInterval(timer)
    sock.close()
  }
}
