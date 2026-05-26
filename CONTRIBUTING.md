# Contributing to wg-gateway

Thank you for your interest in contributing! This project is a Docker image that bundles third-party components (wg-easy, Mihomo, metacubexd), so contributions are typically shell scripts, Dockerfile changes, config defaults, or documentation.

## How to contribute

1. Fork the repository.
2. Create a feature branch from `main`.
3. Make your changes.
4. Test by building and running the image locally (see below).
5. Open a pull request against `main`.

## Local testing

```bash
# Build the image
docker compose build

# Run with test configuration
cp .env.example .env
# Edit .env and set WG_HOST to your server's public IP
docker compose up -d

# Check that all services are running
docker exec wg-gateway supervisorctl status

# Run the healthcheck manually
docker exec wg-gateway /scripts/healthcheck.sh
```

## What you can contribute

- **Shell scripts** (`scripts/`) — bug fixes, improved error handling, new features.
- **Dockerfile** — build optimizations, security improvements, new build arguments.
- **Default configs** (`config/`) — better defaults, new configuration options.
- **CI/CD** (`.github/workflows/`) — new checks, multi-arch builds, improved pipelines.
- **Documentation** — README improvements, new guides, translations.

## Guidelines

### Shell scripts

- All scripts must be compatible with **Debian bookworm-slim** (bash).
- Use `set -e` at the top of every script.
- Use `shellcheck` to validate your changes before submitting:
  ```bash
  shellcheck scripts/*.sh
  ```
- Note: Debian bookworm's `iproute2` does **not** support `ip rule replace` — use `ip rule add` with existence checks.
- All `iptables` commands must target **both** `iptables-legacy` and `iptables-nft` backends (Unraid uses legacy).

### Dockerfile

- Use multi-stage builds to keep the final image small.
- Pin versions with `ARG` and include `SHA256` verification for downloaded binaries.
- Combine related `RUN` commands into a single layer where possible.

### Commit messages

- Use short, descriptive commit messages.
- Prefix with the area of change when helpful: `scripts:`, `ci:`, `docs:`, `dockerfile:`.

### Pull requests

- Describe what the change does and why.
- Reference any related issues.
- Ensure CI passes (shellcheck + smoke test + build).

## Reporting issues

- Use [GitHub Issues](https://github.com/ksantd/wg-gateway/issues).
- Include the image version, Docker version, and host OS.
- Attach relevant logs from `/data/logs/` or `docker logs`.

## Component version updates

A weekly CI workflow checks for new versions of wg-easy, Mihomo, and metacubexd. If an update is available, it creates a GitHub issue. To manually update:

1. Update the `ARG` in `Dockerfile` (`MIHOMO_VERSION`, etc.).
2. Update `MIHOMO_SHA256` if Mihomo changed — download the new binary and run `sha256sum`.
3. Update `AGENTS.md` to reflect the new version.
4. Test the build locally.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
