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

# Sync bundled metacubexd UI assets to the external-ui path configured by the user.
# Reads the actual external-ui directory from /data/mihomo/config.yaml so that
# assets are updated at whichever path Mihomo will serve them from — whether the
# user kept the default (/data/ui) or set a custom path.
sync_ui_assets() {
    local bundled_dir="/opt/metacubexd"
    local config_file="/data/mihomo/config.yaml"

    if [ ! -f "$bundled_dir/.version" ]; then
        return
    fi

    local bundled_version
    bundled_version=$(cat "$bundled_dir/.version")

    local ui_dir="/data/ui"
    if [ -f "$config_file" ]; then
        local parsed
        parsed=$(grep -E '^external-ui:' "$config_file" | head -1 | sed 's/^external-ui:[[:space:]]*//' | tr -d '"' | tr -d "'")
        if [ -n "$parsed" ] && [ "$parsed" != "$bundled_dir" ]; then
            ui_dir="$parsed"
        fi
    fi

    local persisted_version=""
    if [ -f "$ui_dir/.version" ]; then
        persisted_version=$(cat "$ui_dir/.version")
    fi

    if [ "$bundled_version" != "$persisted_version" ]; then
        echo "[wg-gateway] Updating UI assets at ${ui_dir} (${persisted_version:-none} -> ${bundled_version})..."
        mkdir -p "$ui_dir"
        rm -rf "${ui_dir:?}"/*
        cp -a "$bundled_dir/." "$ui_dir/"
        echo "[wg-gateway] UI assets updated to ${bundled_version}."
    fi
}

sync_ui_assets

# Apply kernel parameters
/scripts/setup-sysctl.sh

echo "[wg-gateway] Starting supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/wg-gateway.conf
