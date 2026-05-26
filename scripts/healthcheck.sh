#!/bin/bash
set -e

# Check Mihomo external controller (supports /version and /configs endpoints)
curl -sf "http://localhost:${MIHOMO_PORT:-51888}/version" > /dev/null 2>&1 \
    || curl -sf "http://localhost:${MIHOMO_PORT:-51888}/configs" > /dev/null 2>&1 \
    || exit 1

# Check wg-easy web UI
curl -sf "http://localhost:${WG_EASY_PORT:-51821}" > /dev/null 2>&1 || exit 1

# Check WireGuard interface is operational.
# wg tool requires the wireguard kernel module — skip if unavailable
# (e.g. CI environments, module not loaded yet on first boot).
if [ -d "/sys/class/net/wg0" ] && command -v wg >/dev/null 2>&1; then
    wg show wg0 listening-port > /dev/null 2>&1 || true
fi

exit 0
