#!/bin/bash
set -e

echo "[wg-gateway] Starting entrypoint..."

# Create required directories
mkdir -p /data/wireguard /data/mihomo /data/ui /data/logs

# Symlink WireGuard config to persistent storage
if [ ! -L /etc/wireguard ]; then
    if [ -d /etc/wireguard ] && [ -z "$(ls -A /etc/wireguard 2>/dev/null)" ]; then
        rmdir /etc/wireguard
    elif [ -d /etc/wireguard ]; then
        # Migrate existing config
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

# Seed metacubexd UI assets if /data/ui is empty
if [ -z "$(ls -A /data/ui 2>/dev/null)" ]; then
    echo "[wg-gateway] Seeding default UI assets..."
    cp -r /opt/metacubexd/* /data/ui/
fi

# Apply kernel parameters
/scripts/setup-sysctl.sh

echo "[wg-gateway] Starting supervisor..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/wg-gateway.conf
