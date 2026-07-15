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

ARG TARGETARCH
ARG MIHOMO_VERSION=v1.19.28
ARG MIHOMO_SHA256_AMD64=08df1464bde7d16936ad086a29b12c435fc6b1cf6554d3b7669433fc13f6fc68
ARG MIHOMO_SHA256_ARM64=6c08572c7115549ea51cb0f94b0d9ff08073a901bf2347d908c7209c4621e96a
ARG METACUBEXD_VERSION=v1.268.4

LABEL org.opencontainers.image.title="wg-gateway" \
      org.opencontainers.image.description="WireGuard VPN gateway with rule-based proxy routing" \
      org.opencontainers.image.source="https://github.com/ksantd/wg-gateway" \
      org.opencontainers.image.licenses="MIT"

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

RUN MIHOMO_ARCH="amd64" \
    && MIHOMO_SHA="${MIHOMO_SHA256_AMD64}" \
    && if [ "$TARGETARCH" = "arm64" ]; then MIHOMO_ARCH="arm64"; MIHOMO_SHA="${MIHOMO_SHA256_ARM64}"; fi \
    && MIHOMO_URL="https://github.com/MetaCubeX/mihomo/releases/download/${MIHOMO_VERSION}/mihomo-linux-${MIHOMO_ARCH}-${MIHOMO_VERSION}.gz" \
    && curl -L -o /tmp/mihomo.gz "$MIHOMO_URL" \
    && gunzip -f /tmp/mihomo.gz \
    && echo "${MIHOMO_SHA}  /tmp/mihomo" | sha256sum -c \
    && mv /tmp/mihomo /usr/local/bin/mihomo \
    && chmod +x /usr/local/bin/mihomo

# metacubexd UI assets
RUN mkdir -p /opt/metacubexd \
    && curl -L "https://github.com/MetaCubeX/metacubexd/releases/download/${METACUBEXD_VERSION}/compressed-dist.tgz" \
    | tar -xz -C /opt/metacubexd \
    && echo "${METACUBEXD_VERSION}" > /opt/metacubexd/.version

# Config files, scripts, and data directories — single layer
COPY config/supervisord.conf /etc/supervisor/conf.d/wg-gateway.conf
COPY config/mihomo/config.yaml /defaults/mihomo/config.yaml
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh \
    && mkdir -p /data/wireguard /data/mihomo /data/ui /data/logs /defaults/mihomo

VOLUME ["/data/wireguard", "/data/mihomo", "/data/ui", "/data/logs"]

# WireGuard:      51820/udp
# wg-easy UI:     51821/tcp
# Mihomo UI/API:  51888/tcp
EXPOSE 51820/udp 51821/tcp 51888/tcp

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD ["/scripts/healthcheck.sh"]

ENTRYPOINT ["/scripts/entrypoint.sh"]
