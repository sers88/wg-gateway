# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-06-06

### Changed

- **Mihomo** v1.19.26 → v1.19.27
- **metacubexd** v1.251.1 → v1.251.3

### Components

- wg-easy v15.3.0
- Mihomo v1.19.27
- metacubexd v1.251.3

## [1.1.1] - 2026-06-02

### Changed

- **metacubexd** v1.249.1 → v1.249.2

### Fixed

- Russian locale accuracy and terminology in metacubexd UI

### Components

- wg-easy v15.3.0
- Mihomo v1.19.26
- metacubexd v1.249.2

## [1.1.0] - 2026-06-02

### Added

- **linux/arm64 support** — multi-platform builds for both amd64 and arm64
- ARM64 smoke tests in CI via matrix strategy with native runners
- Environment variable validation in `entrypoint.sh` (ports, IPs, password length, etc.)
- SHA256 checksum verification for Mihomo binary during Docker build (amd64 + arm64)
- OCI image labels in Dockerfile (`org.opencontainers.image.*`)
- `HEALTHCHECK` instruction in Dockerfile as fallback for non-compose deployments
- WireGuard interface check (`wg show wg0`) in `healthcheck.sh`
- Background process monitoring with automatic restart in `setup-routing.sh`
- Auto-sync metacubexd UI assets to user's `external-ui` path on startup
- `shellcheck` linting step in CI for all shell scripts
- Smoke test in CI (`docker run` + service verification + healthcheck)
- Weekly version-check workflow that creates GitHub issues for component updates
- `CHANGELOG.md` and `CONTRIBUTING.md`

### Changed

- **Mihomo** v1.19.25 → v1.19.26
- **metacubexd** v1.248.5 → v1.249.1
- GitHub Actions bumped to latest major versions (Node.js 24 compatible)
- CI workflow restructured: `shellcheck` → `smoke-test` → `build-and-push` (gated)
- Consolidated `RUN` layers in Dockerfile (scripts + data dirs merged into single layer)
- Updated `.dockerignore` to exclude docs, templates, and project metadata

### Fixed

- Corrected Mihomo SHA256 hashes for uncompressed binaries
- Fixed shellcheck SC2086 warnings in CI scripts
- Fixed smoke test grep regex and CI environment adaptation
- Fixed entrypoint override in CI verify step to prevent supervisord startup

### Components

- wg-easy v15.3.0
- Mihomo v1.19.26
- metacubexd v1.249.1

## [1.0.0] - 2025-05-27

_Initial release._

### Components

- wg-easy v15.3.0
- Mihomo v1.19.25
- metacubexd v1.248.5

[1.2.0]: https://github.com/ksantd/wg-gateway/releases/tag/v1.2.0
[1.1.1]: https://github.com/ksantd/wg-gateway/releases/tag/v1.1.1
[1.1.0]: https://github.com/ksantd/wg-gateway/releases/tag/v1.1.0
[1.0.0]: https://github.com/ksantd/wg-gateway/releases/tag/v1.0.0
