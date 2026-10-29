# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The images are tagged by Debian release; these versions describe the image
and the pipeline that builds it.

## [Unreleased]

### Added

- **heyvaldemar/os-shell: Debian 12 and Debian 13, each rebuilt every week.** Tags `12`, `13` and `latest` (the newest line); `linux/amd64` and `linux/arm64`. `bitnami/os-shell` has published only `latest` since August 2025, built on Photon OS, and its versioned Debian tags stopped at `12-debian-12-r51`.
- **A drop-in for bitnami/os-shell, checked on every build** against `bitnamilegacy/os-shell:12-debian-12-r51`: user `1001` in group `0`, no entrypoint and the command `/bin/bash`, `HOME=/`, the same `PATH` and build `SHELL`, the same calls init containers make, and every executable on its `PATH` or a reason in `tests/drop-in-absent*.tsv`.
- **Bitnami's own charts on kind**: PostgreSQL's volume permissions and Redis's sysctl run their init containers on this image before anything is published.
- **No fixable critical or high finding**: `scripts/cve-gate.sh` refuses an image that carries one.
- **The five helpers built from source** at pinned commits with a current Go; `scuttle` and `yq` with current `golang.org/x/net` and `x/text`.
- **A contract with the published image**: nothing an init container used under a tag disappears from it without a line in `tests/contract-removed.tsv`.
- **Every digest signed** with cosign, keyless, with SBOM, SLSA provenance and a GitHub build attestation; Trivy on every published line; CVE counts against the images it replaces after every publish.
- **Every test shown the breaks it exists for**: twelve planted violations in `tests/plants.tsv`, run in CI.
