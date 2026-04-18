# wg-gateway

[![Build](https://github.com/ksantd/wg-gateway/actions/workflows/docker.yml/badge.svg)](https://github.com/ksantd/wg-gateway/actions/workflows/docker.yml)
[![Release](https://github.com/ksantd/wg-gateway/actions/workflows/release.yml/badge.svg)](https://github.com/ksantd/wg-gateway/actions/workflows/release.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/ksantd/wg-gateway)](https://hub.docker.com/r/ksantd/wg-gateway)
[![MIT License](https://img.shields.io/github/license/ksantd/wg-gateway)](LICENSE)

**WireGuard VPN gateway with rule-based proxy routing.**

A single Docker image that combines WireGuard server management, a proxy/routing engine (Mihomo), and web UIs for both. WireGuard clients connect and all their traffic is routed through the proxy engine, where per-rule decisions determine whether traffic goes through a **proxy** or **direct** to the internet.

## Architecture

```
                      ┌──────────────────────────────────────────┐
                      │          wg-gateway container            │
                      │                                          │
 WireGuard  ──udp──► │  wg0 ──Mihomo auto-route──► Mihomo TUN   │
 Client               │                              │           │
                      │                              ├─► PROXY ──► Proxy Server ──► Internet
                      │                              │           │
                      │                              └─► DIRECT ──► Internet
                      │                                          │
                      │  wg-easy UI (:51821)  Mihomo UI (:51888) │
                      └──────────────────────────────────────────┘
```

### Traffic flow

1. WireGuard client connects to the server on **UDP 51820**.
2. Decrypted traffic appears on the **wg0** interface inside the container.
3. Mihomo's `auto-route` adds policy routing rules that direct traffic through the **TUN device**.
4. Mihomo evaluates rules (domain, IP CIDR, GeoIP, rule-providers, etc.) and decides per connection: **PROXY** or **DIRECT**.
5. Direct traffic exits via the host's real network interface. Proxy traffic exits through the configured proxy server.
6. Mihomo's own outbound connections are fwmark-tagged to bypass the TUN, preventing routing loops.

A background daemon monitors interfaces and re-applies iptables FORWARD rules for wg0 if they get flushed.

### Why host network mode

Host networking is required because:

- **wg-easy** manages the `wg0` WireGuard interface directly on the host.
- **Mihomo TUN** creates a virtual network device that intercepts traffic at the kernel level.
- **Policy routing** (`ip rule`, `ip route`) operates on the host's routing tables.
- Bridged networking would add unnecessary NAT layers and complicate the transparent proxy setup.

## Quick Start

### Docker run

```bash
docker run -d \
  --name wg-gateway \
  --restart unless-stopped \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --device /dev/net/tun:/dev/net/tun \
  -v /path/to/wireguard:/data/wireguard \
  -v /path/to/mihomo:/data/mihomo \
  -v /path/to/ui:/data/ui \
  -v /path/to/logs:/data/logs \
  -e WG_HOST=YOUR_SERVER_PUBLIC_IP \
  ksantd/wg-gateway:latest
```

### Docker Compose

```bash
cp .env.example .env
# Edit .env and set WG_HOST to your server's public IP
docker compose up -d
```

## Required capabilities and sysctls

| Parameter | Value | Why |
|---|---|---|
| `--network host` | Host networking | WG, TUN, and routing all need host-level access |
| `--cap-add NET_ADMIN` | Linux capability | Required to create network interfaces and modify routing tables |
| `--cap-add SYS_MODULE` | Linux capability | Allows loading the `wireguard` kernel module if needed |
| `--sysctl net.ipv4.ip_forward=1` | Kernel param | Enables IP forwarding between interfaces |
| `--sysctl net.ipv6.conf.all.forwarding=1` | Kernel param | Enables IPv6 forwarding |
| `--device /dev/net/tun` | Device access | Required by Mihomo to create its TUN interface |

**Host prerequisites:** The host kernel must have the `wireguard` module available. On most modern Linux distributions it is included. On Unraid, ensure the WireGuard plugin is installed.

## Ports

| Port | Protocol | Service |
|---|---|---|
| 51820 | UDP | WireGuard VPN server |
| 51821 | TCP | wg-easy Web UI (peer management) |
| 51888 | TCP | Proxy engine Web UI (Mihomo dashboard) |

## Volumes

| Mount point | Purpose |
|---|---|
| `/data/wireguard` | WireGuard server config and peer data |
| `/data/mihomo` | Proxy engine configuration |
| `/data/ui` | Optional: custom UI assets (bundled UI is used by default) |
| `/data/logs` | Log files |

## First start

1. Start the container (see Quick Start above).
2. Open the **wg-easy UI** at `http://YOUR_SERVER_IP:51821`.
3. Create a WireGuard client/peer.
4. Download the generated `.conf` file or scan the QR code.
5. Import the config into your WireGuard client (phone, laptop, etc.).
6. Connect — your traffic now flows through the gateway.

By default, **all traffic goes DIRECT** (no proxy). To route traffic through a proxy, edit the Mihomo config (see below).

## Accessing the UIs

- **wg-easy** (WireGuard peer management): `http://YOUR_SERVER_IP:51821`
- **Proxy engine dashboard**: `http://YOUR_SERVER_IP:51888/ui/`

## Configuring proxy rules

### Edit the config

The Mihomo config lives at `/data/mihomo/config.yaml`. Edit it to add proxies and rules.

### Add manual proxy definitions

```yaml
proxies:
  - name: "my-proxy"
    type: ss
    server: server.example.com
    port: 443
    cipher: aes-256-gcm
    password: "secret"
```

Then reference it in the PROXY group:

```yaml
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - my-proxy
      - DIRECT
```

### Use a subscription (proxy-provider)

```yaml
proxy-providers:
  my-sub:
    type: http
    url: "https://your-subscription-url"
    interval: 3600
    path: /data/mihomo/providers/my-sub.yaml
    health-check:
      enable: true
      url: http://www.gstatic.com/generate_204
      interval: 300

proxy-groups:
  - name: PROXY
    type: select
    use:
      - my-sub
    proxies:
      - DIRECT
```

### Change routing behavior

The default `MATCH,DIRECT` rule at the bottom of the rules list means all unmatched traffic goes direct. To route everything through a proxy by default:

```yaml
rules:
  - DOMAIN-SUFFIX,local,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - MATCH,PROXY    # <-- Changed from DIRECT to PROXY
```

### Apply changes

After editing `config.yaml`, reload via the dashboard at `:51888/ui/` or restart Mihomo:

```bash
docker exec wg-gateway supervisorctl restart mihomo
```

The routing daemon automatically re-applies policy routes when the TUN device is recreated.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `WG_HOST` | _(none — required)_ | Public IP or hostname for client configs |
| `WG_PORT` | `51820` | WireGuard server UDP port |
| `WG_DEFAULT_DNS` | `1.1.1.1` | DNS advertised to WireGuard clients |
| `WG_ALLOWED_IPS` | `0.0.0.0/0,::/0` | Routes advertised to clients |
| `WG_PERSISTENT_KEEPALIVE` | `25` | Keepalive interval (seconds) |
| `WG_EASY_PORT` | `51821` | wg-easy Web UI port |
| `WG_EASY_PASSWORD` | _(empty)_ | Bcrypt hash for wg-easy UI auth (not plaintext — generate with `docker run -it ghcr.io/wg-easy/wg-easy wgpw YOUR_PASSWORD`) |
| `MIHOMO_PORT` | `51888` | Proxy engine external controller port |
| `MIHOMO_SECRET` | _(empty)_ | Secret for proxy engine API |
| `TUN_DEV` | `Meta` | Mihomo TUN device name |
| `ROUTE_CHECK_INTERVAL` | `30` | Seconds between iptables rule checks |
| `ROUTE_WAIT` | `90` | Max seconds to wait for interfaces |
| `TZ` | `UTC` | Timezone |

## Unraid deployment

### Prerequisites

- Install the **WireGuard** plugin from the Unraid Community Applications (if not already present).
- Ensure `/dev/net/tun` exists (it usually does on Unraid 6.x+).

### Option A: Docker CLI (recommended)

```bash
docker run -d \
  --name wg-gateway \
  --restart unless-stopped \
  --network host \
  --cap-add NET_ADMIN \
  --cap-add SYS_MODULE \
  --sysctl net.ipv4.ip_forward=1 \
  --sysctl net.ipv6.conf.all.forwarding=1 \
  --device /dev/net/tun:/dev/net/tun \
  -v /mnt/user/appdata/wg-gateway/wireguard:/data/wireguard \
  -v /mnt/user/appdata/wg-gateway/mihomo:/data/mihomo \
  -v /mnt/user/appdata/wg-gateway/ui:/data/ui \
  -v /mnt/user/appdata/wg-gateway/logs:/data/logs \
  -e WG_HOST=YOUR_PUBLIC_IP \
  ksantd/wg-gateway:latest
```

### Option B: Community Applications template

1. In Unraid, go to **Docker** tab → **Add Container**.
2. Set **Repository** to `ksantd/wg-gateway`.
3. Set **Network Type** to **host**.
4. Under **Extra Parameters**, add:
   ```
   --cap-add NET_ADMIN --cap-add SYS_MODULE --device /dev/net/tun:/dev/net/tun
   ```
5. Add the sysctls and volume mounts as shown in the CLI example above.
6. Set `WG_HOST` to your public IP.

### Unraid-specific notes

- **Do not** use Unraid's built-in WireGuard manager alongside this container for the same port — they will conflict.
- If you already have Unraid's WireVPN active, either stop it or use a different port for wg-gateway.
- The container uses Mihomo's `auto-route` to manage policy routing. Mihomo adds `ip rule` and `ip route` entries at the host level, scoped to its own routing table. This will not affect Unraid's normal networking — Mihomo's fwmark bypass ensures its own connections use the main routing table.
- **Forwarding chain**: Docker on Unraid sets `iptables FORWARD` policy to `DROP` by default. The container adds explicit `ACCEPT` rules for the `wg0` interface to handle this. If clients can connect but have no internet, check: `iptables -L FORWARD -n` — you should see `ACCEPT` entries for `wg0`.
- To view logs: `docker exec wg-gateway cat /data/logs/supervisord.log`
- To check routing status: `docker exec wg-gateway ip rule list` and `docker exec wg-gateway ip route show table all`

## Known limitations

- **Linux/amd64 only** — the image is built specifically for x86_64 Linux hosts.
- **No authentication by default** — both wg-easy and the proxy engine UI are accessible without a password. Set `WG_EASY_PASSWORD` (bcrypt hash) and `MIHOMO_SECRET` for production use.
- **Single WireGuard interface** — wg-easy manages one `wg0` interface.
- **No split-tunnel from server side** — all client traffic is routed through the gateway. Clients can manage split-tunneling via the `AllowedIPs` in their WireGuard config.
- **Routing depends on startup order** — the routing daemon waits for both wg0 and the Mihomo TUN device and retries periodically. If either service fails to start, client traffic will not be proxied until it recovers.
- **Kernel module required** — the host must have the `wireguard` kernel module. This is standard on modern kernels but may need manual installation on some minimal distributions.

## Third-party components

This project bundles the following third-party software. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license text.

| Component | License | Upstream |
|---|---|---|
| wg-easy | AGPL-3.0 | https://github.com/wg-easy/wg-easy |
| Mihomo | GPL-3.0 | https://github.com/MetaCubeX/mihomo |
| metacubexd | MIT | https://github.com/MetaCubeX/metacubexd |

This project itself is released under the [MIT License](LICENSE).

## Project license

MIT — see [LICENSE](LICENSE).
