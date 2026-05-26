# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Environment variable validation in `entrypoint.sh` (ports, IPs, password length, etc.)
- SHA256 checksum verification for Mihomo binary during Docker build
- OCI image labels in Dockerfile (`org.opencontainers.image.*`)
- `HEALTHCHECK` instruction in Dockerfile as fallback for non-compose deployments
- WireGuard interface check (`wg show wg0`) in `healthcheck.sh`
- Background process monitoring with automatic restart in `setup-routing.sh`
- `shellcheck` linting step in CI for all shell scripts
- Smoke test in CI (`docker run` + service verification + healthcheck)
- Weekly version-check workflow that creates GitHub issues for component updates
- `CHANGELOG.md` and `CONTRIBUTING.md`

### Changed

- Consolidated `RUN` layers in Dockerfile (scripts + data dirs merged into single layer)
- CI workflow restructured: `shellcheck` → `smoke-test` → `build-and-push` (gated)
- Updated `.dockerignore` to exclude docs, templates, and project metadata

## [1.0.0] - 2025-05-27

_Initial release._

### Components

- wg-easy v15.3.0
- Mihomo v1.19.25
- metacubexd v1.248.5

[Unreleased]: https://github.com/ksantd/wg-gateway/compare/v1.0.0...main
[1.0.0]: https://github.com/ksantd/wg-gateway/releases/tag/v1.0.0
