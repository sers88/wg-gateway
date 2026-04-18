#!/bin/bash
# Policy routing daemon: routes WireGuard client traffic through Mihomo TUN.
# Runs as a long-lived supervisord service so routing is re-applied
# automatically if Mihomo or wg-easy restart and interfaces are recreated.
#
# Mihomo runs with auto-route: false — we manage routing ourselves so ONLY
# WG client traffic goes through the TUN (not all host traffic).
#
# NOTE: Debian bookworm iproute2 does NOT support "ip rule replace".
# Use "ip rule add" with existence checks instead.

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

# Add iptables rule to all available backends (iptables-nft AND iptables-legacy).
# Docker on Unraid uses iptables-legacy; other systems may use iptables-nft.
ipt_add() {
    local chain="$1"; shift
    local match="$1"; shift
    for ipt in iptables-legacy iptables; do
        command -v "$ipt" >/dev/null 2>&1 || continue
        $ipt -C "$chain" $match -j ACCEPT 2>/dev/null || $ipt -I "$chain" 1 $match -j ACCEPT 2>/dev/null || true
    done
}

apply_routing() {
    # Disable rp_filter on TUN and wg0 — prevents kernel from dropping
    # packets with asymmetric routing paths (WG <-> TUN).
    sysctl -w net.ipv4.conf.${TUN_DEV}.rp_filter=0 > /dev/null 2>&1 || true
    sysctl -w net.ipv4.conf.wg0.rp_filter=0 > /dev/null 2>&1 || true

    # Get WG subnet from the wg0 interface
    WG_SUBNET=$(ip -4 addr show wg0 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -1) || true
    if [ -z "$WG_SUBNET" ]; then
        echo "[routing] Could not determine WireGuard subnet from wg0. Retrying later."
        return 1
    fi

    local changed=false

    # Default route through Mihomo TUN in our custom table
    if ! ip route show table "${TABLE}" 2>/dev/null | grep -q "dev ${TUN_DEV}"; then
        if ip route replace default dev "${TUN_DEV}" table "${TABLE}"; then
            changed=true
        else
            echo "[routing] ERROR: Failed to add route dev ${TUN_DEV} table ${TABLE}"
        fi
    fi

    # Priority 100: bypass Mihomo for traffic TO private/local networks.
    for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16 127.0.0.0/8; do
        if ! ip rule show | grep -q "to ${net} lookup main"; then
            if ip rule add to "${net}" table main pref 100; then
                changed=true
            else
                echo "[routing] WARNING: Failed to add bypass rule for ${net}"
            fi
        fi
    done

    # Priority 200: traffic FROM WireGuard clients goes through Mihomo TUN.
    if ! ip rule show | grep -q "from ${WG_SUBNET} lookup ${TABLE}"; then
        if ip rule add from "${WG_SUBNET}" table "${TABLE}" pref 200; then
            changed=true
        else
            echo "[routing] ERROR: Failed to add policy rule for ${WG_SUBNET}"
        fi
    fi

    # Allow forwarding between wg0 and TUN in ALL iptables backends.
    # Docker on Unraid uses iptables-legacy with FORWARD DROP policy.
    ipt_add FORWARD "-i wg0"
    ipt_add FORWARD "-o wg0"

    if [ "$changed" = true ]; then
        echo "[routing] Policy routing configured: ${WG_SUBNET} -> table ${TABLE} -> ${TUN_DEV} -> Mihomo"
    fi

    # Debug: show current state
    local legacy_fwd="N/A"
    if command -v iptables-legacy >/dev/null 2>&1; then
        legacy_fwd=$(iptables-legacy -L FORWARD -n 2>/dev/null | grep -c "wg0" || echo "0")
    fi
    echo "[routing] State: rules=$(ip rule show | grep -c "lookup ${TABLE}"), route=$(ip route show table "${TABLE}" 2>/dev/null | head -1), rp_filter_Meta=$(sysctl -n net.ipv4.conf.${TUN_DEV}.rp_filter 2>/dev/null || echo '?'), rp_filter_wg0=$(sysctl -n net.ipv4.conf.wg0.rp_filter 2>/dev/null || echo '?'), legacy_wg0_rules=${legacy_fwd}"

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
