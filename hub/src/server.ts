// The hub's HTTP API. Two halves:
//
//   /api/v1/...                 pairing, devices and status
//   GET /tools, POST /v1/chat/completions
//                               the brain interface a board already speaks to the PC brain
//                               (docs/DEVICE_PROTOCOL.md, "Board to brain"), so a board talks to the hub
//                               exactly the way it talks to a PC.

import { randomBytes, timingSafeEqual } from 'node:crypto'
import { existsSync, readFileSync, writeFileSync } from 'node:fs'
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http'
import { join } from 'node:path'

import type { Brain } from './brain.js'
import type { HubConfig } from './config.js'
import { LINK_VERSION, type Identity } from './link.js'
import { type Device, DeviceStore, PairingError } from './devices.js'
import { agentPrompt, couldNotFinish, filler, forSpeech, readBoardTurn, stillWorking, wantsReply } from './speech.js'
import { VoiceStream } from './sse.js'

export const VERSION = '0.1.1'
const BODY_MAX = 4 * 1024 * 1024   // a board's camera frame is about 70 KB of JSON; this is plenty

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message)
  }
}

function send(res: ServerResponse, status: number, obj: unknown): void {
  const body = JSON.stringify(obj)
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': Buffer.byteLength(body) })
  res.end(body)
}

async function readJson(req: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = []
  let size = 0
  for await (const c of req) {
    size += (c as Buffer).length
    if (size > BODY_MAX) throw new HttpError(413, 'body too large')
    chunks.push(c as Buffer)
  }
  if (!size) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw new HttpError(400, 'body is not JSON')
  }
}

function tokenOf(req: IncomingMessage, url: URL): string | undefined {
  const h = req.headers.authorization
  if (h?.startsWith('Bearer ')) return h.slice(7).trim()
  const x = req.headers['x-orion-token']
  if (typeof x === 'string' && x) return x.trim()
  return url.searchParams.get('token') ?? undefined
}

// The tool list a board's health check reads. The board ignores the contents; this tells a person
// with curl what the hub can do.
const TOOLS = [
  ['shell', 'Run commands on the hub (and on the host when the hub runs in a container).'],
  ['network', 'Scan the local network for devices and open ports.'],
  ['docker', 'List, start, stop and read the logs of Docker containers.'],
  ['ssh', 'Log in to another machine over SSH and run commands there.'],
  ['web', 'Search the web and read pages.'],
  ['memory', 'Remember facts the user asks it to keep.'],
].map(([name, description]) => ({ type: 'function', function: { name, description, parameters: { type: 'object', properties: {} } } }))

export class HubServer {
  readonly devices: DeviceStore
  private server?: Server
  private readonly localSecret: string

  identity(): Identity {
    return { orion: LINK_VERSION, id: this.cfg.id, kind: 'hub', name: this.cfg.name, port: this.cfg.port, version: VERSION }
  }

  constructor(private readonly cfg: HubConfig, private readonly brain: Brain) {
    this.devices = new DeviceStore(join(cfg.stateDir, 'devices.json'))
    // The CLI inside the container authenticates with this file, readable only by root.
    const secretFile = join(cfg.stateDir, 'local.secret')
    if (existsSync(secretFile)) {
      this.localSecret = readFileSync(secretFile, 'utf8').trim()
    } else {
      this.localSecret = randomBytes(24).toString('base64url')
      writeFileSync(secretFile, this.localSecret, { mode: 0o600 })
    }
  }

  private isLocalAdmin(req: IncomingMessage): boolean {
    const given = req.headers['x-orion-hub-local']
    const addr = req.socket.remoteAddress ?? ''
    const loopback = addr === '127.0.0.1' || addr === '::1' || addr === '::ffff:127.0.0.1'
    if (!loopback || typeof given !== 'string') return false
    const a = Buffer.from(given)
    const b = Buffer.from(this.localSecret)
    return a.length === b.length && timingSafeEqual(a, b)
  }

  private auth(req: IncomingMessage, url: URL): Device {
    const d = this.devices.authenticate(tokenOf(req, url))
    if (!d) throw new HttpError(401, 'pair with the hub first')
    return d
  }

  // Paired device or the local CLI.
  private admin(req: IncomingMessage, url: URL): void {
    if (this.isLocalAdmin(req)) return
    this.auth(req, url)
  }

  listen(): Promise<void> {
    this.server = createServer((req, res) => {
      this.route(req, res).catch((e: unknown) => {
        const status = e instanceof HttpError || e instanceof PairingError ? e.status : 500
        if (status === 500) console.error('[http]', e)
        if (!res.headersSent) send(res, status, { error: (e as Error).message })
        else res.end()
      })
    })
    // Long agent turns: the stream stays open while the board hears keep-alives.
    this.server.requestTimeout = 0
    this.server.headersTimeout = 20_000
    this.server.keepAliveTimeout = 65_000
    return new Promise((ok) => this.server!.listen(this.cfg.port, '0.0.0.0', () => ok()))
  }

  close(): Promise<void> {
    this.devices.flushLastSeen()
    return new Promise((ok) => (this.server ? this.server.close(() => ok()) : ok()))
  }

  private async route(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', 'http://hub')
    const path = url.pathname.replace(/\/+$/, '') || '/'
    const m = req.method ?? 'GET'

    // Orion Link (docs/ORION_LINK.md): who answers here, for any node that found this address.
    if (m === 'GET' && path === '/.well-known/orion') return send(res, 200, this.identity())
    if (m === 'GET' && (path === '/' || path === '/api/v1/info')) {
      return send(res, 200, {
        kind: 'orion-hub',
        id: this.cfg.id,
        name: this.cfg.name,
        version: VERSION,
        paired: this.devices.count(),
        brain: this.brain.state,
        model: `${this.cfg.provider}/${this.cfg.model}`,
        port: this.cfg.port,
      })
    }

    if (m === 'POST' && path === '/api/v1/pair/request') {
      const body = (await readJson(req)) as { name?: unknown; kind?: unknown; hw?: unknown }
      return send(res, 200, this.devices.request(body.name, body.kind, body.hw))
    }
    const poll = /^\/api\/v1\/pair\/request\/([A-Za-z0-9_-]{8,64})$/.exec(path)
    if (m === 'GET' && poll) return send(res, 200, this.devices.poll(poll[1]!))

    if (m === 'GET' && path === '/api/v1/pair/pending') {
      this.admin(req, url)
      return send(res, 200, { pending: this.devices.listPending() })
    }
    const decide = /^\/api\/v1\/pair\/pending\/([A-Za-z0-9_-]{4,64})\/(approve|deny)$/.exec(path)
    if (m === 'POST' && decide) {
      this.admin(req, url)
      if (decide[2] === 'approve') return send(res, 200, this.devices.approve(decide[1]!))
      this.devices.deny(decide[1]!)
      return send(res, 200, { ok: true })
    }

    if (m === 'GET' && path === '/api/v1/devices') {
      this.admin(req, url)
      return send(res, 200, { devices: this.devices.list(), claimed: this.devices.isClaimed })
    }
    const del = /^\/api\/v1\/devices\/([a-f0-9]{12})$/.exec(path)
    if (m === 'DELETE' && del) {
      this.admin(req, url)
      if (!this.devices.remove(del[1]!)) throw new HttpError(404, 'no such device')
      this.brain.forget(del[1]!)
      return send(res, 200, { ok: true })
    }

    if (m === 'GET' && path === '/api/v1/status') {
      this.admin(req, url)
      return send(res, 200, { brain: this.brain.state, error: this.brain.lastError || undefined, devices: this.devices.list() })
    }

    if (m === 'GET' && path === '/tools') {
      this.auth(req, url)
      // A dsh that failed to start is tried again at every board health check.
      if (this.brain.state === 'failed') this.brain.start().catch(() => {})
      if (this.brain.state === 'no-key' || this.brain.state === 'failed') throw new HttpError(503, this.brain.lastError || 'brain not ready')
      return send(res, 200, { tools: TOOLS })
    }

    if (m === 'POST' && path === '/v1/chat/completions') {
      const device = this.auth(req, url)
      return this.turn(device, await readJson(req), res)
    }

    throw new HttpError(404, 'not found')
  }

  // One spoken request from a board, answered as SSE.
  private async turn(device: Device, body: unknown, res: ServerResponse): Promise<void> {
    const turn = readBoardTurn(body)
    if (!turn) throw new HttpError(400, 'no user message')
    // A brain that cannot answer at all says so before streaming, so the board answers with its own model.
    if (this.brain.state !== 'ready') await this.brain.start()
    if (this.brain.state !== 'ready') throw new HttpError(503, this.brain.lastError || 'brain not ready')

    const stream = new VoiceStream(res)
    stream.open()
    const t0 = Date.now()
    // Only the length: a request can carry a spoken password, and anyone in the docker group can read
    // docker logs.
    console.log(`[turn] ${device.name} asks (${turn.text.length} characters${turn.image ? ', +picture' : ''})`)

    const fill = setTimeout(() => stream.say(filler(turn.text)), this.cfg.fillerAfterMs)
    let gaveUp: NodeJS.Timeout | undefined
    const giveUp = new Promise<'late'>((ok) => {
      gaveUp = setTimeout(() => ok('late'), this.cfg.turnMaxMs)
    })
    const answer = this.brain.ask(device.id, agentPrompt(turn, device.name), turn.image)
    try {
      const r = await Promise.race([answer, giveUp])
      if (r === 'late') {
        // The work goes on in the dsh Session; its result is in the memory for the next question.
        stream.say(stillWorking(turn.text))
        stream.finish(false)
        answer.then(
          (a) => console.log(`[turn] ${device.name} finished in the background after ${a.ms} ms`),
          (e) => console.error(`[turn] ${device.name} background turn failed: ${(e as Error).message}`),
        )
        return
      }
      const spoken = forSpeech(r.text)
      if (!spoken) {
        console.error(`[turn] ${device.name} got no answer from the agent`)
        stream.fail(couldNotFinish(turn.text), r.error ?? 'the hub agent gave no answer')
        return
      }
      stream.say(spoken)
      const listen = wantsReply(spoken)
      stream.finish(listen)
      console.log(`[turn] ${device.name} answered in ${Date.now() - t0} ms${listen ? ', listening for the reply' : ''}: ${spoken.slice(0, 160)}`)
    } catch (e) {
      console.error(`[turn] ${device.name} failed: ${(e as Error).message}`)
      stream.fail(couldNotFinish(turn.text), (e as Error).message)
    } finally {
      clearTimeout(fill)
      clearTimeout(gaveUp)
    }
  }
}
