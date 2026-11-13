# Orion Link

How the devices of the Orion ecosystem know each other: boards, Orion Hubs, the desktop app and the phone app. Every device is known by a permanent id. Its address is only where it was last seen. When the address changes (a router's DHCP hands out another one, the device moves to another access point, a hub's container is rebuilt), the others find the same id again and follow it, without anyone re-pairing.

## Ids

| Kind | Id | Made |
|---|---|---|
| `board` | `orion-` and the last four hex digits of the Wi-Fi MAC, `orion-a1b2` | from the hardware, never changes |
| `hub` | `hub-` and 12 hex digits | on first start, kept in the hub's state (`identity.json`) |
| `pc` | `pc-` and 12 hex digits | on first launch of the desktop app, kept in its settings |
| `phone` | `phone-` and 12 hex digits | on first launch of the phone app, kept in its settings |

An id is not a secret. It only says which device to look for. Pairing still goes through each pair's own flow (Bluetooth setup or a code on the board's screen for an app, approval on the hub for a board) and every request still carries its token.

## Who answers here

Every device serves its identity over HTTP, without a token:

```
GET /.well-known/orion

200 { "orion": 1, "id": "hub-3c9e51a07b2d", "kind": "hub", "name": "Orion Hub", "port": 8780, "version": "0.1.0" }
```

| Kind | Port |
|---|---|
| board | 80 |
| hub | 8780 |
| pc | the PC brain's port, 7331 or the next free one |
| phone | the phone brain's port, 7331 or the next free one |

A new address found any way at all (a beacon, mDNS, a sweep) is used only after the device there answers with the id that is wanted: here, or in a board's `GET /api/info`, which is what the apps ask. A device that cannot tell yet (the app at launch, before its id is read) answers 404.

## Presence

- **mDNS.** A board announces `_orion._tcp` and a hub `_orionhub._tcp`, both with TXT `id` and `kind`.
- **Beacon.** A board broadcasts every 2 s, and a hub with the host's network every 5 s, to UDP `255.255.255.255:7332`:

```json
{ "orion": 1, "id": "orion-a1b2", "device_id": "orion-a1b2", "kind": "board", "name": "Orion", "fw": "1.1.0", "ip": "192.168.1.40", "port": 80 }
{ "orion": 1, "id": "hub-3c9e51a07b2d", "kind": "hub", "name": "Orion Hub", "port": 8780, "version": "0.1.0" }
```

The apps read `device_id` and `ip` from a board's beacon and confirm the board with `GET /api/info` at that address before they use it. Boards and apps do not read the hub's beacon.

Many routers drop multicast and some drop broadcast, and a hub under Docker Desktop can send neither onto the LAN. Presence is a fast path, never the only one.

## Finding an id again

A device looking for a known id tries, in order, and stops at the first identity check that matches:

1. **The last address.**
2. **mDNS**, and for a board its beacon, heard for that id.
3. **A sweep:** every address of its own /24 on the port that kind uses, a few connections at a time, then the identity check on the few that answer. It works wherever plain TCP does, Docker Desktop's port mapping included. A board takes about 20 s for a /24.

When the id answers somewhere new, that address replaces the old one where it is kept, and the connection is made again.

## Trust

A device found again at a new address is trusted because it answers with the right id. Ids are public, so a device on the same network that pretends to be one can receive that pairing's token, like anyone who can read plain HTTP there (see [SECURITY.md](../SECURITY.md)). A later version will have devices prove they hold the pairing before they are followed.

## Learning from connections

An authenticated connection says where its sender is right now, so nobody has to look:

- **PC brain.** When the desktop app links to the board (`/ws?client=pc`) with the token the board holds as `pc.token`, and the link comes from another address than `pc.base_url`, the board rewrites `pc.base_url` to that address, same port, before the link counts. The PC brain's health check that follows already goes to the new address.
- **Phone brain.** A phone offers `brain=<host>:<port>` on its link. The board uses the address the link comes from and the port offered: the phone's own guess at its address is often an interface the board cannot reach.
- **The app.** On launch the desktop app also tells the board its address in `pc.base_url`, as before.

## Who finds whom

| Looks for | How |
|---|---|
| The apps, the paired board | the last address first; then beacon, mDNS, the `.local` names and a sweep of the board's last /24, confirmed by the board's `/api/info`. A new address is used only when the old one no longer answers as the board (`BoardLocator`, after 8 s without a connection, then after 45 s, doubling up to 12 minutes while the board stays away) |
| A board, its paired hub | the cloud's health check at the last address; while that fails, mDNS by TXT `id` every two minutes, a new address followed only after its `/.well-known/orion` gives the id; then the last address again and a sweep of the board's /24 on the hub's port, the first within two minutes, then after gaps of 4, 8 and 16 minutes, then every 32 minutes while the hub stays away (`orion_hub.c`) |
| A board, a hub to pair with | mDNS (`_orionhub._tcp`) after boot and every two minutes; a search asked for from the menu, the app or the console also sweeps port 8780 on the board's /24 when mDNS finds nothing |
| A board, the PC brain | the PC's link (above); and the desktop app's own report at launch |
| A board, a phone brain | the phone's link (above) |

A pairing made before Orion Link has no stored id. The board then matches its hub by name, and stores the id the first time the hub answers with one.

## Version

`"orion": 1` in every beacon and identity. The apps skip a beacon with any other version.
