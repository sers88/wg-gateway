# AGENTS.md

## Project overview

Single Docker image that bundles **wg-easy v15.3.0** (WireGuard management), **Mihomo v1.19.26** (proxy/routing engine), and **metacubexd v1.249.1** (Mihomo UI). No application code — the repo is shell scripts, configs, and a Dockerfile that assembles third-party components.

## Build and run

```bash
# Build locally
docker compose build
# Run (requires .env with WG_HOST set)
cp .env.example .env && docker compose up -d
```

No tests, lint, or typecheck exist. The only validation is whether the Docker image builds and the services start.

## Directory layout

- `Dockerfile` — multi-stage build: copies wg-easy from upstream image, downloads Mihomo binary + metacubexd UI
- `scripts/` — entrypoint and long-running service scripts run by supervisord
- `config/supervisord.conf` — process manager: starts mihomo → wg-easy → setup-routing daemon
- `config/mihomo/config.yaml` — default Mihomo config seeded to `/data/mihomo/config.yaml` on first start
- `templates/wg-gateway.xml` — Unraid Community Applications template

## Key architecture facts

- **Mihomo runs with `auto-route: false`** — routing is managed by `scripts/setup-routing.sh`, which runs as a persistent daemon under supervisord. This script handles policy routing so only WireGuard client traffic goes through the TUN, not all host traffic.
- **Policy routing uses table 666, ip rule priority 200.** Traffic from the WireGuard subnet is matched and directed to that table, which has a default route through Mihomo's TUN device.
- **wg-easy v15 entrypoint** — upstream switched to a Nuxt/Nitro compiled app. Entrypoint is `dumb-init node server/index.mjs` from `/app`. The `libsql` native module is re-installed for Debian/glibc because the upstream image is Alpine/musl-based.
- **wg-easy v15 uses INIT_* env vars for unattended setup** — on first start the container auto-configures the admin user, WG host/port, DNS and Allowed IPs via `INIT_ENABLED=true` so the Web UI wizard is skipped.
- **rp_filter must be 0** (not 2) — WG↔TUN traffic has entirely asymmetric paths, so even loose mode (`2`) drops packets.
- **Both iptables backends are handled** — Unraid Docker uses `iptables-legacy` with FORWARD DROP policy; other systems use `iptables-nft`. All iptables commands in scripts target both.
- **metacubexd UI auto-sync** — metacubexd assets are bundled at `/opt/metacubexd` in the image with a `.version` file. On every container start, the entrypoint reads the `external-ui` path from the user's Mihomo config and syncs the bundled assets there if the version changed. This ensures UI updates are applied automatically when the Docker image is updated, regardless of the user's configured `external-ui` path.

## CI

- `.github/workflows/docker.yml` — builds on push to `main` (`latest` + timestamp) and `feature/arm64-support` (`snapshot` + `snapshot-<sha>`). Smoke tests run on both `linux/amd64` and `linux/arm64` native runners via matrix strategy.
- `.github/workflows/release.yml` — on `v*` tags, builds and pushes semver tags + `latest`, creates GitHub Release with auto-generated notes
- Platforms: `linux/amd64`, `linux/arm64`
- Image: `ksantd/wg-gateway` on Docker Hub, `ghcr.io/sers88/wg-gateway` on GHCR

## Editing scripts

All scripts in `scripts/` are bash and must remain compatible with Debian bookworm-slim. Notable constraint: **`ip rule replace` is not available** on Debian bookworm's iproute2 — use `ip rule add` with existence checks instead (see `setup-routing.sh`).

## Mihomo config changes

After editing `/data/mihomo/config.yaml`, reload without restarting the whole container:
```bash
docker exec wg-gateway supervisorctl restart mihomo
```
The routing daemon automatically re-applies policy routes when the TUN device is recreated.
