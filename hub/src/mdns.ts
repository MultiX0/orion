// Announces the hub on the LAN as _orionhub._tcp, so a board (or the app) finds it without an address.
// Needs the host's network: docker-compose.yml runs the hub with network_mode: host.

import { Bonjour, type Service } from 'bonjour-service'

import type { HubConfig } from './config.js'
import { VERSION } from './server.js'

export function announce(cfg: HubConfig): () => void {
  // Without a callback bonjour-service throws a failed send (a network that is down for a moment, a
  // firewall rule) from inside a socket callback, which ends the whole hub. mDNS is a convenience: log
  // it and keep serving.
  const onError = (e: Error): void => console.error(`[mdns] ${e.message}`)
  const bonjour = new Bonjour({}, onError)
  // A failed bind of port 5353 is an 'error' event on the multicast-dns socket wrapper, which the
  // library leaves without a listener. Its field is private in the typings.
  ;(bonjour as unknown as { server?: { mdns?: NodeJS.EventEmitter } }).server?.mdns?.on('error', onError)
  let service: Service | undefined
  try {
    service = bonjour.publish({
      name: cfg.name,
      type: 'orionhub',
      protocol: 'tcp',
      port: cfg.port,
      txt: { version: VERSION, api: '1', id: cfg.id, kind: 'hub' },
    })
    service.on('error', (e: Error) => console.error(`[mdns] ${e.message}`))
    console.log(`[mdns] announcing "${cfg.name}" as _orionhub._tcp on port ${cfg.port}`)
  } catch (e) {
    console.error(`[mdns] could not announce: ${(e as Error).message}`)
  }
  return () => {
    service?.stop?.()
    bonjour.destroy()
  }
}
