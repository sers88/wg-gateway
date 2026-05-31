#!/bin/bash
set -e

echo "[wg-gateway] Starting entrypoint..."

# --- Validate environment variables ---

# Helper: check a port is a valid number in range 1-65535
validate_port() {
    local name="$1" value="$2"
    if ! echo "$value" | grep -qE '^[0-9]+$' || [ "$value" -lt 1 ] || [ "$value" -gt 65535 ]; then
        echo "[wg-gateway] ERROR: $name must be a number between 1 and 65535, got: '$value'"
        exit 1
    fi
}

# WG_HOST: if set, must be non-empty and look like an IP or hostname
if [ -n "${WG_HOST:-}" ]; then
    if echo "$WG_HOST" | grep -qE '[^a-zA-Z0-9.:\-]'; then
        echo "[wg-gateway] ERROR: WG_HOST contains invalid characters: '$WG_HOST'"
        exit 1
    fi
fi

# WG_PORT
validate_port "WG_PORT" "${WG_PORT:-51820}"

# WG_EASY_PORT
validate_port "WG_EASY_PORT" "${WG_EASY_PORT:-51821}"

# MIHOMO_PORT
validate_port "MIHOMO_PORT" "${MIHOMO_PORT:-51888}"

# WG_DEFAULT_DNS: if set, must contain at least one valid IP or DNS address
if [ -n "${WG_DEFAULT_DNS:-}" ]; then
    echo "$WG_DEFAULT_DNS" | grep -qE '^[0-9a-fA-F.:,]+$' || {
        echo "[wg-gateway] ERROR: WG_DEFAULT_DNS must be IP addresses separated by commas, got: '$WG_DEFAULT_DNS'"
        exit 1
    }
fi

# WG_ALLOWED_IPS: if set, basic format check
if [ -n "${WG_ALLOWED_IPS:-}" ]; then
    echo "$WG_ALLOWED_IPS" | grep -qE '[0-9a-fA-F.:,/]' || {
        echo "[wg-gateway] ERROR: WG_ALLOWED_IPS must be CIDR ranges separated by commas, got: '$WG_ALLOWED_IPS'"
        exit 1
    }
fi

# WG_EASY_INIT_PASSWORD: required when WG_HOST is set (unattended mode)
if [ -n "${WG_HOST:-}" ] && [ -z "${WG_EASY_INIT_PASSWORD:-}" ]; then
    echo "[wg-gateway] ERROR: WG_EASY_INIT_PASSWORD is required when WG_HOST is set (unattended setup mode)."
    echo "[wg-gateway] Set WG_EASY_INIT_PASSWORD or remove WG_HOST to use the Web UI wizard."
    exit 1
fi

# WG_EASY_INIT_PASSWORD minimum length
if [ -n "${WG_EASY_INIT_PASSWORD:-}" ] && [ "${#WG_EASY_INIT_PASSWORD}" -lt 6 ]; then
    echo "[wg-gateway] ERROR: WG_EASY_INIT_PASSWORD must be at least 6 characters."
    exit 1
fi

# INSECURE must be true or false
case "${INSECURE:-true}" in
    true|false) ;;
    *)
        echo "[wg-gateway] ERROR: INSECURE must be 'true' or 'false', got: '$INSECURE'"
        exit 1
        ;;
esac

echo "[wg-gateway] Environment validation passed."

# Create required directories
mkdir -p /data/wireguard /data/mihomo /data/ui /data/logs

# Symlink WireGuard config to persistent storage
if [ ! -L /etc/wireguard ]; then
    if [ -d /etc/wireguard ] && [ -z "$(ls -A /etc/wireguard 2>/dev/null)" ]; then
        rmdir /etc/wireguard
    elif [ -d /etc/wireguard ]; then
        cp -a /etc/wireguard/* /data/wireguard/ 2>/dev/null || true
        rm -rf /etc/wireguard
    fi
    ln -sf /data/wireguard /etc/wireguard
fi

# Seed default Mihomo config if none exists
if [ ! -f /data/mihomo/config.yaml ]; then
    echo "[wg-gateway] Seeding default Mihomo config..."
    cp /defaults/mihomo/config.yaml /data/mihomo/config.yaml
fi

# Sync bundled UI assets to persistent volume if version changed.
# This ensures /data/ui always has the latest metacubexd from the image,
# so users who set external-ui: /data/ui in config.yaml get updated assets
# after pulling a new Docker image.
BUNDLED_VERSION=""
PERSISTED_VERSION=""
if [ -f /opt/metacubexd/.version ]; then
    BUNDLED_VERSION=$(cat /opt/metacubexd/.version)
fi
if [ -f /data/ui/.version ]; then
    PERSISTED_VERSION=$(cat /data/ui/.version)
fi
if [ "$BUNDLED_VERSION" != "$PERSISTED_VERSION" ]; then
    echo "[wg-gateway] Updating UI assets (${PERSISTED_VERSION:-none} -> ${BUNDLED_VERSION})..."
    rm -rf /data/ui/*
    cp -a /opt/metacubexd/. /data/ui/
    echo "[wg-gateway] UI assets updated to ${BUNDLED_VERSION}."
fi

# Apply kernel parameters
/scripts/setup-sysctl.sh

echo "[wg-gateway] Starting supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/wg-gateway.conf
