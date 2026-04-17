#!/bin/bash
set -e

echo "[sysctl] Configuring kernel parameters..."

# Enable IP forwarding (required for routing WG traffic through Mihomo)
sysctl -w net.ipv4.ip_forward=1 > /dev/null 2>&1 || echo "[sysctl] WARNING: Cannot set net.ipv4.ip_forward (needs NET_ADMIN capability)"
sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null 2>&1 || true

# Disable send redirects
sysctl -w net.ipv4.conf.all.send_redirects=0 > /dev/null 2>&1 || true

echo "[sysctl] Done."
