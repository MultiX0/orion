# Orion Hub

A voice agent on your own home server. An Orion board finds the hub on the network, pairs with it once, and from then on every question goes to the hub first. The hub runs a DeepSeek harness (dsh) agent on Claude Haiku 5.5 (low effort) with real control of the machine: it can check the time, list and restart Docker containers, scan the home network, log in to other machines over SSH, and remember what you ask it to.

It is one Docker Compose service. The first device that pairs with a new hub is its owner, and every later device needs approval.

## Run it

The image is on Docker Hub as [`multix00/orion-hub`](https://hub.docker.com/r/multix00/orion-hub), for `linux/amd64` (PCs, mini PCs, servers) and `linux/arm64` (Raspberry Pi 4 and 5). Nothing to build: make a folder with these two files on a Linux server or Raspberry Pi with Docker.

`.env`, with your own Anthropic key and your time zone:

```sh
ANTHROPIC_API_KEY=sk-ant-...
# Your time zone (UTC when left out)
TZ=Europe/Berlin
# Optional: a DeepSeek API key lets the agent search the web
# DEEPSEEK_API_KEY=sk-...
```

`docker-compose.yml`:

```yaml
services:
  orion-hub:
    image: multix00/orion-hub:latest
    container_name: orion-hub
    restart: unless-stopped
    network_mode: host
    pid: host
    privileged: true
    env_file: .env
    volumes:
      - /DATA/AppData/orion-hub:/var/lib/orion-hub
      - /var/run/docker.sock:/var/run/docker.sock
```

Then:

```sh
sudo mkdir -p /DATA/AppData/orion-hub
sudo docker compose up -d
sudo docker logs -f orion-hub
```

To update: `sudo docker compose pull && sudo docker compose up -d`. To stay on one version, use `multix00/orion-hub:0.1.1` instead of `latest`. The `docker-compose.yml` in this folder is the same service and pulls the same image; `docker compose up -d --build` builds it from source instead.

The service uses host networking (mDNS and real LAN scans), the host's PID namespace and privileged mode (so `host <command>` can run on the server itself), and the Docker socket. State lives in `/DATA/AppData/orion-hub`: paired devices, the hub's id, the agent's memory, its sessions and an audit log of every request and action (`logs/actions.jsonl`, readable only by root).

To try it on a Windows or Mac desktop, use `docker compose -f docker-compose.desktop.yml up -d`. Docker Desktop cannot announce the hub on the LAN. When you search from the board's menu or the app and mDNS finds nothing, the board sweeps its network for port 8780, which takes about 20 seconds. You can also pair by address with `hub connect http://<pc ip>:8780` on the board's serial console. After that the board finds the hub again by its id when the PC's address changes. Set `ORION_HUB_LAN_CIDR` in `.env` to your network (for example `192.168.1.0/24`) so the agent's scans look at the right place.

## Finding the hub again

The hub has a permanent id (`hub-` and 12 hex digits, in `identity.json` in its state), answers `GET /.well-known/orion` with it, and puts it in its mDNS record. A board stores the id when it pairs. When the hub's address changes, the board finds the same id again: by mDNS on a Linux server, and otherwise by sweeping its network for port 8780, which is the only way under Docker Desktop. Keep `identity.json` with the rest of the state: a hub that gets a new id must be paired again once its address changes. See [docs/ORION_LINK.md](../docs/ORION_LINK.md).

## Pairing

1. On the board: the menu's first card ("الخادم") shows a hub it found; press connect. The app's Settings has the same card.
2. The first device a new hub sees becomes its owner at once. After that every device needs approval, even once all of them are removed.
3. Any later device shows a four digit code. Approve it on the hub:

```sh
docker exec orion-hub orion-hub-cli pending
docker exec orion-hub orion-hub-cli approve 4821
docker exec orion-hub orion-hub-cli devices
docker exec orion-hub orion-hub-cli remove <device id>
```

Tokens are stored only as SHA-256 hashes. A board that pairs again replaces its old entry. Forgetting the hub on the board removes it on the hub too.

## Talking to it

Say "Orion" and ask. When the hub needs something from you (which container, a password, a yes before deleting), it ends with a question and the board listens for your answer without the wake word.

A password you say is saved for SSH in the hub's vault (`ssh/vault.json` in its state, mode 0600), never in its memory notes. Like everything you say, it also passes through your board's speech-to-text service and the model (Anthropic), and it stays in the agent's session history and the audit log, which only root can read. The audit log hides the password in the agent's login command, and docker logs show only the length of each request.

## Settings

| Variable | Default | |
|---|---|---|
| `ANTHROPIC_API_KEY` | | required |
| `DEEPSEEK_API_KEY` | | optional: web search (dsh searches through DeepSeek). Without it the agent still reads web pages |
| `ORION_HUB_NAME` | `Orion Hub on <hostname>` | the name boards show |
| `ORION_HUB_PORT` | `8780` | |
| `ORION_HUB_MODEL` | `claude-haiku-5-5` | |
| `ORION_HUB_EFFORT` | `low` | |
| `ORION_HUB_PROVIDER` | `anthropic` | the dsh provider route |
| `ORION_HUB_MDNS` | on | `0` turns off the `_orionhub._tcp` announcement and the UDP beacon |
| `ORION_HUB_LAN_CIDR` | the server's own network | what `orion-net scan` looks at |
| `ORION_HUB_TURN_MAX_MS` | `150000` | after this the board hears "still working" and the task carries on |
| `ORION_HUB_FILLER_MS` | `6000` | when the board hears "one moment" |
| `ORION_HUB_STATE_DIR` | `/var/lib/orion-hub` in the image | paired devices, the hub's id, memory, sessions and logs |
| `ORION_HUB_WORKSPACE` | `<state dir>/workspace` | the agent's working folder and its `MEMORY.md` |
| `ORION_HUB_CONTAINER` | `1` in the image | `1` makes `host <command>` enter the host; the desktop compose file sets `0` |
| `TZ` | `UTC` | the hub's clock. A board that sends its own local time wins |

## API

| | |
|---|---|
| `GET /.well-known/orion` | the hub's Orion Link identity. No token. |
| `GET /api/v1/info` | id, name, version, whether the brain is ready. No token. |
| `POST /api/v1/pair/request` | `{name, kind, hw}`: on a new hub the owner's token at once, otherwise a request id and code |
| `GET /api/v1/pair/request/:id` | pending, approved (the token, once), denied or expired |
| `GET /api/v1/pair/pending`, `POST /api/v1/pair/pending/:id/approve\|deny` | for paired devices and the CLI |
| `GET`, `DELETE /api/v1/devices[/:id]` | |
| `GET /api/v1/status` | brain state, last error and devices, for paired devices and the CLI |
| `GET /tools`, `POST /v1/chat/completions` | the board's brain interface, [docs/DEVICE_PROTOCOL.md](../docs/DEVICE_PROTOCOL.md) "Board to brain" |

## Develop

```sh
npm ci && npm run build && npm test
node tools/fake-board.mjs http://localhost:8780 pair "Test bench"
node tools/fake-board.mjs http://localhost:8780 ask "what time is it?" "which containers are running?"
```

`tools/fake-board.mjs` pairs and sends turns the way the firmware does, and checks the stream against the board's rules.
