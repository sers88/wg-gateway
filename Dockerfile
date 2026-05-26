# wg-gateway Dockerfile
# Builds a single image combining wg-easy, Mihomo, and metacubexd.

# --- Stage 1: wg-easy app files ---
FROM ghcr.io/wg-easy/wg-easy:15.3.0 AS wg-easy-source

# --- Stage 2: Build native modules for Debian/glibc ---
FROM debian:bookworm-slim AS native-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    build-essential \
    python3 \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN npm install --no-save --omit=dev libsql argon2 \
    && echo "native modules build OK"

# --- Stage 3: Final image ---
FROM debian:bookworm-slim

ARG MIHOMO_VERSION=v1.19.25
ARG METACUBEXD_VERSION=v1.248.5

# Runtime dependencies + Node.js 24.x (required by wg-easy v15)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iptables \
    iproute2 \
    kmod \
    curl \
    ca-certificates \
    supervisor \
    procps \
    dumb-init \
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# wg-easy v15.3.0 app — copy built Nuxt output from upstream image.
# Upstream is Alpine/musl-based; we replace the node_modules with
# Debian/glibc-compatible native modules (libsql, argon2) from Stage 2.
COPY --from=wg-easy-source /app /app
COPY --from=native-build /app/node_modules /app/server/node_modules

# Mihomo core binary
# Asset naming: mihomo-linux-amd64-<tag>.gz (adjust build arg if upstream changes)
RUN curl -L -o /tmp/mihomo.gz \
    "https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-amd64-${MIHOMO_VERSION}.gz" \
    && gunzip -f /tmp/mihomo.gz \
    && mv /tmp/mihomo /usr/local/bin/mihomo \
    && chmod +x /usr/local/bin/mihomo

# metacubexd UI assets
RUN mkdir -p /opt/metacubexd \
    && curl -L "https://github.com/MetaCubeX/metacubexd/releases/download/${METACUBEXD_VERSION}/compressed-dist.tgz" \
    | tar -xz -C /opt/metacubexd

# Config files and scripts
COPY config/supervisord.conf /etc/supervisor/conf.d/wg-gateway.conf
COPY config/mihomo/config.yaml /defaults/mihomo/config.yaml
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

# Data directories
RUN mkdir -p /data/wireguard /data/mihomo /data/ui /data/logs /defaults/mihomo

VOLUME ["/data/wireguard", "/data/mihomo", "/data/ui", "/data/logs"]

# WireGuard:      51820/udp
# wg-easy UI:     51821/tcp
# Mihomo UI/API:  51888/tcp
EXPOSE 51820/udp 51821/tcp 51888/tcp

ENTRYPOINT ["/scripts/entrypoint.sh"]
