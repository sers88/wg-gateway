#!/bin/bash
set -e

# Configure wg-easy v15 minimal environment variables.
# v15 no longer accepts WG_HOST, WG_PORT, PASSWORD_HASH, WG_POST_UP, etc.
# Those settings are managed via the Web UI or INIT_* variables for unattended setup.
export PORT="${WG_EASY_PORT:-51821}"
export HOST="${HOST:-0.0.0.0}"
export INSECURE="${INSECURE:-true}"

# Unattended setup — skip the Web UI wizard on first start by providing
# all mandatory INIT_* variables. Group 1 (username, password, host, port)
# is required to bypass the wizard.
if [ -n "$WG_HOST" ]; then
    export INIT_ENABLED="true"
    export INIT_USERNAME="${WG_EASY_INIT_USERNAME:-admin}"

    if [ -z "$WG_EASY_INIT_PASSWORD" ]; then
        echo "[wg-easy] ERROR: WG_EASY_INIT_PASSWORD must be set for v15 unattended setup."
        echo "[wg-easy] This is a plaintext password (not a bcrypt hash) used to create the admin account."
        exit 1
    fi
    export INIT_PASSWORD="$WG_EASY_INIT_PASSWORD"

    export INIT_HOST="$WG_HOST"
    export INIT_PORT="${WG_PORT:-51820}"
    export INIT_DNS="${WG_DEFAULT_DNS:-1.1.1.1}"
    export INIT_IPV4_CIDR="${INIT_IPV4_CIDR:-10.8.0.0/24}"
    export INIT_IPV6_CIDR="${INIT_IPV6_CIDR:-2001:0DB8::/32}"
    export INIT_ALLOWED_IPS="${WG_ALLOWED_IPS:-0.0.0.0/0,::/0}"

    echo "[wg-easy] Unattended setup enabled."
    echo "[wg-easy]   Admin user: ${INIT_USERNAME}"
    echo "[wg-easy]   WG host:    ${INIT_HOST}:${INIT_PORT}"
    echo "[wg-easy]   Allowed IPs: ${INIT_ALLOWED_IPS}"
else
    echo "[wg-easy] WARNING: WG_HOST is not set. Unattended setup disabled — the Web UI setup wizard will run on first start."
    export INIT_ENABLED="false"
fi

echo "[wg-easy] Starting on port ${PORT}..."

cd /app
exec dumb-init node server/index.mjs
