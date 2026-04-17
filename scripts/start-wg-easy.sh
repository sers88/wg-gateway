#!/bin/bash
set -e

# Configure wg-easy environment
export WG_PATH="${WG_PATH:-/data/wireguard}"
export WG_PORT="${WG_PORT:-51820}"
export WG_DEFAULT_DNS="${WG_DEFAULT_DNS:-1.1.1.1}"
export WG_ALLOWED_IPS="${WG_ALLOWED_IPS:-0.0.0.0/0,::/0}"
export WG_PERSISTENT_KEEPALIVE="${WG_PERSISTENT_KEEPALIVE:-25}"
export PORT="${WG_EASY_PORT:-51821}"

if [ -z "${WG_HOST}" ]; then
    echo "[wg-easy] WARNING: WG_HOST is not set. Client configs will not have the correct server address."
    echo "[wg-easy] Set WG_HOST to your server's public IP or hostname."
fi
export WG_HOST="${WG_HOST:-0.0.0.0}"

# Override wg-easy's default POST_UP to exclude MASQUERADE.
# Gateway mode routes traffic through Mihomo TUN instead of direct NAT.
# wg-easy uses JS || for defaults, so empty string falls through — use a real command.
if [ -z "${WG_POST_UP+x}" ]; then
    export WG_POST_UP="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT"
fi
if [ -z "${WG_POST_DOWN+x}" ]; then
    export WG_POST_DOWN="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT"
fi

# Optional password protection
if [ -n "$WG_EASY_PASSWORD" ]; then
    export PASSWORD_HASH="${WG_EASY_PASSWORD}"
fi

echo "[wg-easy] Starting on port ${PORT}..."
echo "[wg-easy] WG_HOST=${WG_HOST}, WG_PORT=${WG_PORT}"

cd /app
exec node server.js
