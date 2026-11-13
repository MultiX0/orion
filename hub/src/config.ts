// Everything the hub reads from its environment, in one place. See README.md for each variable.

import { hostname } from 'node:os'
import { join, resolve } from 'node:path'

import { hubId } from './link.js'

export interface HubConfig {
  // Orion Link id, "hub-<12 hex>": made once, kept in the state directory (link.ts).
  id: string
  name: string
  port: number
  stateDir: string
  dshHome: string
  workspace: string
  provider: string
  model: string
  effort: string
  anthropicKey: string
  inContainer: boolean
  mdns: boolean
  // A turn that has not finished in this long is left running in the background and the board is told so.
  turnMaxMs: number
  // The first spoken "one moment" goes out after this long without an answer.
  fillerAfterMs: number
  timeZone: string
}

function int(v: string | undefined, fallback: number): number {
  const n = Number.parseInt(v ?? '', 10)
  return Number.isFinite(n) && n > 0 ? n : fallback
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): HubConfig {
  const stateDir = resolve(env.ORION_HUB_STATE_DIR ?? './state')
  return {
    id: hubId(stateDir),
    name: env.ORION_HUB_NAME?.trim() || `Orion Hub on ${hostname()}`,
    port: int(env.ORION_HUB_PORT, 8780),
    stateDir,
    dshHome: join(stateDir, 'dsh'),
    workspace: resolve(env.ORION_HUB_WORKSPACE ?? join(stateDir, 'workspace')),
    provider: env.ORION_HUB_PROVIDER?.trim() || 'anthropic',
    model: env.ORION_HUB_MODEL?.trim() || 'claude-haiku-5-5',
    effort: env.ORION_HUB_EFFORT?.trim() || 'low',
    anthropicKey: env.ANTHROPIC_API_KEY?.trim() ?? '',
    inContainer: env.ORION_HUB_CONTAINER === '1',
    mdns: env.ORION_HUB_MDNS !== '0',
    turnMaxMs: int(env.ORION_HUB_TURN_MAX_MS, 150_000),
    fillerAfterMs: int(env.ORION_HUB_FILLER_MS, 6_000),
    timeZone: env.TZ?.trim() || Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
  }
}
