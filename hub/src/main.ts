// Orion Hub: the home server brain for Orion boards. See README.md.

import { mkdirSync } from 'node:fs'

import { Brain } from './brain.js'
import { loadConfig } from './config.js'
import { beacon } from './link.js'
import { announce } from './mdns.js'
import { HubServer, VERSION } from './server.js'

const cfg = loadConfig()
mkdirSync(cfg.stateDir, { recursive: true })

const brain = new Brain(cfg)
const server = new HubServer(cfg, brain)
await server.listen()
console.log(`[hub] Orion Hub ${VERSION} "${cfg.name}" (${cfg.id}) on port ${cfg.port}, state in ${cfg.stateDir}, ${server.devices.count()} paired`)
const stopMdns = cfg.mdns ? announce(cfg) : () => {}
// The beacon needs the host's network too, like mDNS.
const stopBeacon = cfg.mdns ? beacon(() => server.identity()) : () => {}

// dsh starts in the background so the first spoken turn does not pay for it.
void brain.start()

let stopping = false
async function stop(sig: string): Promise<void> {
  if (stopping) return
  stopping = true
  console.log(`[hub] ${sig}, stopping`)
  stopMdns()
  stopBeacon()
  await server.close()
  await brain.close()
  process.exit(0)
}
process.on('SIGTERM', () => void stop('SIGTERM'))
process.on('SIGINT', () => void stop('SIGINT'))
