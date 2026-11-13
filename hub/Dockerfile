# Orion Hub, the home server brain for Orion boards. linux/amd64 and linux/arm64 (Raspberry Pi 4 and 5).
# Runs as root on purpose: it manages the machine it runs on (Docker, host commands through nsenter).
FROM node:24-trixie-slim AS build
WORKDIR /src
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci --no-audit --no-fund
COPY src ./src
COPY test ./test
RUN npx tsc -p . && npm prune --omit=dev

FROM node:24-trixie-slim
LABEL org.opencontainers.image.title="Orion Hub" \
      org.opencontainers.image.description="Home server brain for the Orion voice assistant: an agent on DeepSeek Harness with Claude, network, Docker and SSH tools." \
      org.opencontainers.image.version="0.1.1"
# The agent's tools: network (nmap, ip, ping, dig), SSH (ssh, sshpass), Docker (the CLI, talking to the
# host's daemon through its socket), host commands (nsenter from util-linux).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl jq git nmap iproute2 iputils-ping dnsutils net-tools openssh-client sshpass \
      procps util-linux docker-cli tzdata less \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /src/node_modules ./node_modules
COPY --from=build /src/dist ./dist
COPY package.json ./
COPY agent ./agent
COPY config ./config
COPY bin/ /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/host /usr/local/bin/orion-net /usr/local/bin/orion-ssh \
 && chmod 755 /usr/local/bin/host /usr/local/bin/orion-net /usr/local/bin/orion-ssh \
 && printf '#!/bin/sh\nexec node /app/dist/src/cli.js "$@"\n' > /usr/local/bin/orion-hub-cli \
 && chmod 755 /usr/local/bin/orion-hub-cli
ENV ORION_HUB_CONTAINER=1 \
    ORION_HUB_STATE_DIR=/var/lib/orion-hub \
    ORION_HUB_WORKSPACE=/var/lib/orion-hub/workspace \
    ORION_HUB_PORT=8780 \
    NODE_ENV=production
VOLUME ["/var/lib/orion-hub"]
EXPOSE 8780
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${ORION_HUB_PORT}/api/v1/info" >/dev/null || exit 1
ENTRYPOINT ["node", "/app/dist/src/main.js"]
