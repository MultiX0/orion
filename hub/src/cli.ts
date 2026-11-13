// orion-hub-cli: manage pairing from the hub itself.
//   docker exec orion-hub orion-hub-cli pending
//   docker exec orion-hub orion-hub-cli approve <code or request id>
//   docker exec orion-hub orion-hub-cli deny <code or request id>
//   docker exec orion-hub orion-hub-cli devices
//   docker exec orion-hub orion-hub-cli remove <device id>

import { readFileSync } from 'node:fs'
import { join } from 'node:path'

import { loadConfig } from './config.js'

const cfg = loadConfig()
const secret = readFileSync(join(cfg.stateDir, 'local.secret'), 'utf8').trim()
const [cmd, arg] = process.argv.slice(2)

async function call(method: string, path: string): Promise<unknown> {
  const r = await fetch(`http://127.0.0.1:${cfg.port}${path}`, { method, headers: { 'X-Orion-Hub-Local': secret } })
  const body = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error((body as { error?: string }).error ?? `HTTP ${r.status}`)
  return body
}

try {
  switch (cmd) {
    case 'pending': {
      const { pending } = (await call('GET', '/api/v1/pair/pending')) as { pending: { code: string; name: string; kind: string; age_s: number }[] }
      if (!pending.length) console.log('No device is waiting.')
      for (const p of pending) console.log(`${p.code}  ${p.name} (${p.kind}), asked ${p.age_s} s ago`)
      break
    }
    case 'approve':
    case 'deny':
      if (!arg) throw new Error(`usage: orion-hub-cli ${cmd} <code>`)
      console.log(JSON.stringify(await call('POST', `/api/v1/pair/pending/${encodeURIComponent(arg)}/${cmd}`)))
      break
    case 'devices': {
      const { devices, claimed } = (await call('GET', '/api/v1/devices')) as {
        devices: { id: string; name: string; kind: string; owner: boolean; last_seen?: string }[]
        claimed?: boolean
      }
      for (const d of devices) console.log(`${d.id}  ${d.name} (${d.kind})${d.owner ? ' owner' : ''}${d.last_seen ? `, last seen ${d.last_seen}` : ''}`)
      if (!devices.length) {
        console.log(claimed
          ? 'Nothing is paired. A device that asks now waits for approval here (pending, then approve <code>).'
          : 'Nothing is paired yet. The first device that asks becomes the owner.')
      }
      break
    }
    case 'remove':
      if (!arg) throw new Error('usage: orion-hub-cli remove <device id>')
      console.log(JSON.stringify(await call('DELETE', `/api/v1/devices/${encodeURIComponent(arg)}`)))
      break
    default:
      console.log('usage: orion-hub-cli pending | approve <code> | deny <code> | devices | remove <device id>')
      process.exit(cmd ? 2 : 0)
  }
} catch (e) {
  console.error((e as Error).message)
  process.exit(1)
}
