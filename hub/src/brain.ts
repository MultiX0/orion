// The agent: one DeepSeek Harness runtime (dsh, over its SDK's stdio JSON-RPC) with Claude as the model,
// and one durable dsh Session per paired device, so every board keeps its own memory across turns and
// restarts. dsh runs the agent loop and its tools (bash, files, web); the hub adds the voice, pairing and
// the instructions in agent/AGENTS.md.

import { appendFileSync, chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { DeepSeekHarness, type HarnessSession, type RunResult, type SdkPromptContentBlock } from '@deepseek-ai/dsh-sdk-client'

import type { HubConfig } from './config.js'

const HERE = dirname(fileURLToPath(import.meta.url))
// dist/src/brain.js -> hub/
const HUB_ROOT = join(HERE, '..', '..')

export type BrainState = 'starting' | 'ready' | 'no-key' | 'failed'

export interface AskResult {
  // Empty when the turn did not complete: what the model said before a failed tool step is no answer.
  text: string
  finishReason: string | null
  // Why the turn did not complete, when it did not.
  error?: string
  sessionId: string
  ms: number
}

type Notification = { method: string; params: Record<string, unknown> }

function sessionIdFor(deviceId: string): string {
  return `orion-${deviceId}`
}

// Hides passwords from the audit log: the password of "orion-ssh login <alias> <user@host> <password>",
// with the rest of that command line, and JSON fields named like a secret. The text can be plain or
// JSON with the command inside an escaped string (a tool call's arguments are JSON inside the event's
// JSON), so quotes may carry backslashes and a line can end in an escaped \n.
export function maskSecrets(text: string): string {
  return text
    .replace(/(orion-ssh\s+login\s+\S+\s+\S+\s+)(?:[^\n\\]|\\(?!\\*n))*/g, '$1***')
    .replace(/(\\*"[\w-]*(?:password|passwd|token|secret|key)\\*"\s*:\s*\\*")[^"\\]*/gi, '$1***')
}

// A short, secret-free line per notable event for the audit log.
export function summarize(n: Notification): string | undefined {
  const p = n.params as Record<string, unknown>
  const ev = (p.event ?? p) as Record<string, unknown>
  const type = String(ev.type ?? n.method)
  if (!/tool|command|approval|subagent/i.test(type + n.method)) return undefined
  return `${type} ${maskSecrets(JSON.stringify(ev)).slice(0, 600)}`
}

// Why a turn did not complete: the finish reason, with the error or abort cause from its turn/end event.
function failureOf(r: RunResult): string {
  const end = r.events.findLast((e) => e.type === 'turn/end') as
    | { data?: { reason?: { kind?: string; error?: { message?: string }; reason?: { kind?: string } } } }
    | undefined
  const reason = end?.data?.reason
  const kind = r.finishReason ?? reason?.kind ?? 'no finish reason'
  const detail = reason?.error?.message ?? reason?.reason?.kind
  return detail ? `${kind}: ${detail}` : kind
}

export class Brain {
  state: BrainState = 'starting'
  lastError = ''
  private harness?: DeepSeekHarness
  private sessions = new Map<string, HarnessSession>()
  private queues = new Map<string, Promise<unknown>>()
  private startPromise?: Promise<void>
  private readonly auditFile: string

  constructor(private readonly cfg: HubConfig) {
    this.auditFile = join(cfg.stateDir, 'logs', 'actions.jsonl')
    // The log holds what people said and every command the agent ran, so only root may read it. Older
    // hubs made it readable by everyone: the modes are set again at every start.
    try {
      const dir = dirname(this.auditFile)
      mkdirSync(dir, { recursive: true, mode: 0o700 })
      chmodSync(dir, 0o700)
      if (existsSync(this.auditFile)) chmodSync(this.auditFile, 0o600)
    } catch {
      // Best effort, like the log itself.
    }
  }

  private audit(entry: Record<string, unknown>): void {
    try {
      mkdirSync(dirname(this.auditFile), { recursive: true, mode: 0o700 })
      appendFileSync(this.auditFile, JSON.stringify({ t: new Date().toISOString(), ...entry }) + '\n', { mode: 0o600 })
    } catch {
      // The log is best effort; a full disk must not stop a turn.
    }
  }

  // The agent's standing instructions: dsh loads $DSH_HOME/AGENTS.md into every Session.
  private installInstructions(): void {
    mkdirSync(this.cfg.dshHome, { recursive: true })
    mkdirSync(this.cfg.workspace, { recursive: true })
    const src = join(HUB_ROOT, 'agent', 'AGENTS.md')
    let text = readFileSync(src, 'utf8')
    text = text
      .replaceAll('{{HUB_NAME}}', this.cfg.name)
      .replaceAll('{{WORKSPACE}}', this.cfg.workspace)
      .replaceAll('{{CONTAINER}}', this.cfg.inContainer ? 'yes' : 'no')
      .replaceAll('{{TIME_ZONE}}', this.cfg.timeZone)
    writeFileSync(join(this.cfg.dshHome, 'AGENTS.md'), text)
    const memory = join(this.cfg.workspace, 'MEMORY.md')
    if (!existsSync(memory)) {
      writeFileSync(memory, '# What Orion remembers about this home\n\nFacts the user asked Orion to remember, one per line.\n')
    }
  }

  start(): Promise<void> {
    this.startPromise ??= this.boot()
    return this.startPromise
  }

  private async boot(): Promise<void> {
    if (this.cfg.provider === 'anthropic' && !this.cfg.anthropicKey) {
      this.state = 'no-key'
      this.lastError = 'ANTHROPIC_API_KEY is not set'
      console.error('[brain] ANTHROPIC_API_KEY is not set; the hub answers 503 until it is')
      return
    }
    // Everything that can fail is inside the try: a start that throws would leave startPromise rejected
    // for good, and nothing would ever try again.
    let harness: DeepSeekHarness | undefined
    try {
      this.installInstructions()
      const env: NodeJS.ProcessEnv = {
        ...process.env,
        DSH_HOME: this.cfg.dshHome,
        DSH_TELEMETRY_MODE: 'DISABLED',
        ANTHROPIC_API_KEY: this.cfg.anthropicKey,
        ORION_HUB_STATE_DIR: this.cfg.stateDir,
      }
      harness = new DeepSeekHarness({
        profile: 'sdk',
        dshHome: this.cfg.dshHome,
        cwd: this.cfg.workspace,
        processCwd: this.cfg.workspace,
        patches: [join(HUB_ROOT, 'config', 'anthropic.cordis.yml')],
        provider: this.cfg.provider,
        model: this.cfg.model,
        reasoningEffort: this.cfg.effort as never,
        maxTokens: 8192,
        env,
        approvalRequests: true,
        initializeTimeoutMs: 60_000,
        // A voice user cannot tick boxes; the agent is told to ask in its spoken answer instead.
        onUserQuestion: async () => ({ cancelled: true }) as never,
      })
      harness.client.start()
      // "Act on your own": every action the agent takes is allowed and written to the audit log.
      harness.client.onRequest(async (method, params) => {
        if (method !== 'approval/request') throw new Error(`unsupported request ${method}`)
        this.audit({ approval: 'allowed', params: maskSecrets(JSON.stringify(params)).slice(0, 800) })
        return { outcome: 'allowed-once' }
      })
      await harness.start()
      this.harness = harness
      this.state = 'ready'
      this.lastError = ''
      console.log(`[brain] dsh ready: ${this.cfg.provider}/${this.cfg.model}, effort ${this.cfg.effort}`)
    } catch (e) {
      this.state = 'failed'
      this.lastError = (e as Error).message
      console.error(`[brain] dsh failed to start: ${this.lastError}`)
      await harness?.close().catch(() => {})
      this.startPromise = undefined
    }
  }

  private async session(deviceId: string): Promise<HarnessSession> {
    const known = this.sessions.get(deviceId)
    if (known) return known
    const h = this.harness!
    const id = sessionIdFor(deviceId)
    let s: HarnessSession
    let fresh = false
    try {
      s = await h.resumeSession(id)
      console.log(`[brain] resumed session ${id}`)
    } catch {
      s = h.session(id)
      fresh = true
    }
    if (fresh) {
      // Full access for this session: the hub is the user's own server and the agent is meant to act.
      const r = await s.run('/permission danger-full-access')
      // On a refusal the session keeps dsh's default preset, and the agent may be stopped from acting.
      if (r.finishReason === 'completed') console.log(`[brain] new session ${id}: ${r.finalResponse.slice(0, 120)}`)
      else console.warn(`[brain] /permission failed for ${id} (${r.finishReason ?? 'no finish reason'}): ${r.finalResponse.slice(0, 120)}`)
    }
    this.sessions.set(deviceId, s)
    return s
  }

  // One turn at a time per device; the next waits for the one before.
  ask(deviceId: string, prompt: string, image?: { data: string; mimeType: string }): Promise<AskResult> {
    const prev = this.queues.get(deviceId) ?? Promise.resolve()
    const next = prev.catch(() => {}).then(() => this.askNow(deviceId, prompt, image))
    this.queues.set(deviceId, next)
    // Cleared only when no newer turn has queued behind this one.
    void next.catch(() => {}).finally(() => {
      if (this.queues.get(deviceId) === next) this.queues.delete(deviceId)
    })
    return next
  }

  private async askNow(deviceId: string, prompt: string, image?: { data: string; mimeType: string }): Promise<AskResult> {
    if (this.state !== 'ready') await this.start()
    if (this.state !== 'ready' || !this.harness) throw new Error(this.lastError || `brain ${this.state}`)
    const t0 = Date.now()
    const input: SdkPromptContentBlock[] = [{ type: 'text', text: prompt }]
    if (image) input.push({ type: 'image', data: image.data, mimeType: image.mimeType as 'image/jpeg' })
    this.audit({ device: deviceId, request: maskSecrets(prompt).slice(0, 500), image: Boolean(image) })
    let result: RunResult
    try {
      const s = await this.session(deviceId)
      result = await s.run(input, {
        onNotification: (n) => {
          const line = summarize(n as Notification)
          if (line) this.audit({ device: deviceId, event: line })
        },
      })
    } catch (e) {
      const msg = (e as Error).message
      this.audit({ device: deviceId, error: maskSecrets(msg).slice(0, 500) })
      // A dead runtime is restarted on the next turn.
      if (/TransportClosed|closed|exited/i.test(`${(e as Error).name} ${msg}`)) await this.restart()
      throw e
    }
    // A turn that failed or was cut off can still end on what the model said before a tool step ("let me
    // check the containers"). That is no answer: the text is left empty and server.ts fails the turn.
    const ok = result.finishReason === 'completed' || result.finishReason === 'max-tokens'
    const error = ok ? undefined : maskSecrets(failureOf(result)).slice(0, 500)
    if (error) console.warn(`[brain] turn for ${deviceId} ended with ${error}`)
    const out: AskResult = {
      text: ok ? result.finalResponse ?? '' : '',
      finishReason: result.finishReason,
      ...(error ? { error } : {}),
      sessionId: result.sessionId,
      ms: Date.now() - t0,
    }
    this.audit({
      device: deviceId,
      answer: out.text.slice(0, 800),
      finish: out.finishReason,
      ...(error ? { error } : {}),
      ms: out.ms,
    })
    return out
  }

  async restart(): Promise<void> {
    console.warn('[brain] restarting dsh')
    const h = this.harness
    this.harness = undefined
    this.sessions.clear()
    this.state = 'starting'
    this.startPromise = undefined
    await h?.close().catch(() => {})
  }

  forget(deviceId: string): void {
    this.sessions.delete(deviceId)
  }

  async close(): Promise<void> {
    await this.harness?.close().catch(() => {})
  }
}
