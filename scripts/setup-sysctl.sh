#!/bin/bash
set -e

echo "[sysctl] Configuring kernel parameters..."

# Enable IP forwarding (required for routing WG traffic through Mihomo)
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || echo "[sysctl] WARNING: Cannot set net.ipv4.ip_forward (needs NET_ADMIN capability)"
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1 || true

# Disable reverse path filtering — CRITICAL for policy routing.
# WG client traffic arrives on wg0, goes out via Meta TUN. Responses come back
# on Meta with dst=WG subnet. This asymmetric routing causes rp_filter to drop
# packets silently. Must be 0 (not 2) because the return path differs entirely.
sysctl -w net.ipv4.conf.all.rp_filter=0 > /dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.rp_filter=0 > /dev/null 2>&1 || true

# Disable send redirects
sysctl -w net.ipv4.conf.all.send_redirects=0 > /dev/null 2>&1 || true

echo "[sysctl] Done."
