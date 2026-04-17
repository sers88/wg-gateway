#!/bin/bash
# Policy routing daemon: routes WireGuard client traffic through Mihomo TUN.
# Runs as a long-lived supervisord service so routing is re-applied
# automatically if Mihomo or wg-easy restart and interfaces are recreated.

TUN_DEV="${TUN_DEV:-Meta}"
TABLE="${ROUTE_TABLE:-666}"
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

apply_routing() {
    # Get WG subnet from the wg0 interface
    WG_SUBNET=$(ip -4 addr show wg0 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -1) || true
    if [ -z "$WG_SUBNET" ]; then
        echo "[routing] Could not determine WireGuard subnet from wg0. Retrying later."
        return 1
    fi

    local changed=false

    # Default route through Mihomo TUN in custom table
    if ! ip route show table "${TABLE}" 2>/dev/null | grep -q "dev ${TUN_DEV}"; then
        ip route replace default dev "${TUN_DEV}" table "${TABLE}" 2>/dev/null && changed=true
    fi

    # Priority 9000: traffic TO private/local networks uses main table (bypass Mihomo)
    ip rule replace to 10.0.0.0/8 table main priority 9000 2>/dev/null || true
    ip rule replace to 172.16.0.0/12 table main priority 9000 2>/dev/null || true
    ip rule replace to 192.168.0.0/16 table main priority 9000 2>/dev/null || true
    ip rule replace to 169.254.0.0/16 table main priority 9000 2>/dev/null || true
    ip rule replace to 127.0.0.0/8 table main priority 9000 2>/dev/null || true

    # Priority 10000: traffic FROM WireGuard clients goes through Mihomo
    if ! ip rule show table "${TABLE}" 2>/dev/null | grep -q "from ${WG_SUBNET}"; then
        ip rule replace from "${WG_SUBNET}" table "${TABLE}" priority 10000 2>/dev/null && changed=true
    fi

    # Allow forwarding between wg0 and TUN (survives Docker's FORWARD DROP policy)
    iptables -C FORWARD -i wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -i wg0 -j ACCEPT
    iptables -C FORWARD -o wg0 -j ACCEPT 2>/dev/null || iptables -A FORWARD -o wg0 -j ACCEPT

    if [ "$changed" = true ]; then
        echo "[routing] Policy routing configured: ${WG_SUBNET} -> table ${TABLE} -> ${TUN_DEV} -> Mihomo"
    fi
    return 0
}

# Initial apply
apply_routing

# Monitor loop: re-apply routing if interfaces are recreated (e.g. Mihomo restart)
echo "[routing] Monitoring active (interval: ${CHECK_INTERVAL}s)..."
while true; do
    sleep "${CHECK_INTERVAL}"
    if [ -d "/sys/class/net/wg0" ] && [ -d "/sys/class/net/${TUN_DEV}" ]; then
        apply_routing
    fi
done
