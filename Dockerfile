# wg-gateway Dockerfile
# Builds a single image combining wg-easy, Mihomo, and metacubexd.

# --- Stage 1: wg-easy app files ---
FROM ghcr.io/wg-easy/wg-easy:15 AS wg-easy-source

# --- Stage 2: Final image ---
FROM debian:bookworm-slim

ARG MIHOMO_VERSION=v1.19.25
ARG METACUBEXD_VERSION=v1.248.1

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

# wg-easy v15 app — copy built Nuxt output from upstream image.
# Upstream is Alpine/musl-based; we reinstall libsql for Debian/glibc.
COPY --from=wg-easy-source /app /app
RUN cd /app/server && rm -rf node_modules && npm install --no-save --omit=dev libsql \
    && echo "wg-easy dependencies OK"

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
