#!/bin/bash
# iptables FORWARD daemon: ensures wg0 forwarding rules survive restarts.
# Runs as a long-lived supervisord service.
#
# With Mihomo auto-route: true, Mihomo manages all ip rule/ip route entries.
# This script only handles iptables FORWARD rules that Docker's default DROP
# policy would otherwise block.

TUN_DEV="${TUN_DEV:-Meta}"
CHECK_INTERVAL="${ROUTE_CHECK_INTERVAL:-30}"
MAX_WAIT="${ROUTE_WAIT:-90}"

echo "[routing] Waiting for wg0 and ${TUN_DEV} interfaces..."

WAITED=0
while [ ! -d "/sys/class/net/wg0" ] || [ ! -d "/sys/class/net/${TUN_DEV}" ]; do
    sleep 2
    WAITED=$((WAITED + 2))
    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        WG_STATE="MISSING"; TUN_STATE="MISSING"
        [ -d "/sys/class/net/wg0" ] && WG_STATE="UP"
        [ -d "/sys/class/net/${TUN_DEV}" ] && TUN_STATE="UP"
        echo "[routing] Timed out waiting for interfaces (wg0=${WG_STATE}, ${TUN_DEV}=${TUN_STATE}). Will keep retrying."
    fi
done

echo "[routing] Both interfaces are up."

apply_iptables() {
    local changed=false

    # Allow forwarding between wg0 and TUN (survives Docker's FORWARD DROP policy)
    iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || { iptables -A FORWARD -i wg0 -j ACCEPT; changed=true; }
    iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || { iptables -A FORWARD -o wg0 -j ACCEPT; changed=true; }

    if [ "$changed" = true ]; then
        echo "[routing] iptables FORWARD rules applied for wg0"
    fi
}

# Initial apply
apply_iptables

# Monitor loop: re-apply iptables rules if they get flushed
echo "[routing] Monitoring active (interval: ${CHECK_INTERVAL}s)..."
while true; do
    sleep "${CHECK_INTERVAL}"
    apply_iptables
done
