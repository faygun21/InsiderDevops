# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v0.1.0] - 2026-05-19

### Added
- Tiny Go HTTP service (/ping, /healthz, /version)
- Multi-stage distroless Docker image (14 MB)
- Helm chart with dev/prod environment overlays
- GitHub Actions CI pipeline (lint, test, Trivy scan, GHCR push)
- Gitleaks secret scanning
- Automated release workflow on version tags
