# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The images are tagged by Debian release; these versions describe the image
and the pipeline that builds it.

## [Unreleased]

## [1.0.3] - 2026-11-12

### Changed

- **yq v4.54.3**, built from its release commit `f2944b8` with the modules its release names.

### Upgrading

yq v4.54.3 changes three things a script may rely on:

- **`yq -i` refuses a read-only file**, and on a symbolic link it writes the edited file in the link's place instead of changing the file the link points to (yq #2973). A ConfigMap or Secret volume is mounted read-only, so `yq -i` on its files failed before as well. A script that writes its own file into an emptyDir and edits that in place, as Bitnami's milvus chart does, works as before.
- **`--split-exp` writes only inside the current directory** unless `--security-allow-write-any-path` is given, which restores the old behaviour for trusted input (yq #2965).
- **YAML aliases are kept across the documents of one input stream**, without leaking anchors between files (yq #2956).

The drop-in test now runs `yq e -i` on a file the script wrote itself, on both images, and checks each of the three changes on this one; each of those checks fails on yq v4.54.2.

### Fixed

- **The daily pin check no longer reports an index pushed again over the same builds as drift.** `freshness.yml` compared each pinned base digest with the digest its tag names now and failed on any difference, so a publisher pushing the index again over the very same images (a platform added, an attestation rewritten) turned it red for an image that had not changed. It now also compares the builds this image is made from under both digests: linux/amd64 alone when every stage from that base is built on the runner (`--platform=$BUILDPLATFORM` or `${BUILDPLATFORM}`), linux/amd64 and linux/arm64 when any stage is built for each published platform, as the fleet's triage judges a re-pushed base. The same builds pass with a notice naming both digests; a new build, or one that cannot be read, still fails. The `golang:1.27-bookworm` move in 1.0.2 was one of these: `sha256:b08bc994…` and `sha256:dc0963f3…` carry the same linux/amd64 and linux/arm64 builds, so the helpers were built in the same Go image as in 1.0.1.

### Security

- **Go 1.27.4 builds the helpers.** `golang:1.27-bookworm` moved from `sha256:dc0963f3…` to `sha256:4fa7c968…`, Go 1.27.3 to Go 1.27.4, a security release: CVE-2026-97054 in the standard library's net/http server, and eleven in how the go command, the compiler and the linker handle cgo and linker flags.

## [1.0.2] - 2026-11-07

### Changed

- **yq v4.54.2**, built from the commit its tag names. It quotes unsafe values in `-o=shell -r` output (GHSA-h2cv-65fq-jgrp) and fixes `map_values`, `ireduce` and comment handling; the rest is in its release notes. Its release already names `golang.org/x/net` v0.62.0 and `x/text` v0.43.0, the versions this build used to raise it to, so yq is now built with the modules it names; only `scuttle` still gets newer ones.
- **The repushed `golang:1.27-bookworm`** builds the helpers: `sha256:b08bc994…` to `sha256:dc0963f3…`, still Go 1.27.3.

## [1.0.1] - 2026-11-05

### Changed

- **Debian's 2026-11-04 repush of `debian:bookworm-slim` and `debian:trixie-slim` is the base of the `12` and `13` lines**, and the helpers are built in the rebuilt `golang:1.27-bookworm`, still Go 1.27.3. The pins move: bookworm-slim `sha256:99c0b25c…` to `sha256:734a72b3…`, trixie-slim `sha256:f6b08b09…` to `sha256:a72b4433…`, golang `sha256:d9b6a1be…` to `sha256:b08bc994…`. The helpers' commits and modules stay as they were.

## [1.0.0] - 2026-10-30

### Added

- **heyvaldemar/os-shell: Debian 12 and Debian 13, each rebuilt every week.** Tags `12`, `13` and `latest` (the newest line); `linux/amd64` and `linux/arm64`. `bitnami/os-shell` has published only `latest` since August 2025, built on Photon OS, and its versioned Debian tags stopped at `12-debian-12-r51`.
- **A drop-in for bitnami/os-shell, checked on every build** against `bitnamilegacy/os-shell:12-debian-12-r51`: user `1001` in group `0`, no entrypoint and the command `/bin/bash`, `HOME=/`, the same `PATH` and build `SHELL`, the same calls init containers make, and every executable on its `PATH` or a reason in `tests/drop-in-absent*.tsv`.
- **Bitnami's own charts on kind**: PostgreSQL's volume permissions and Redis's sysctl run their init containers on this image before anything is published.
- **No fixable critical or high finding**: `scripts/cve-gate.sh` refuses an image that carries one.
- **The five helpers built from source** at pinned commits with a current Go; `scuttle` and `yq` with current `golang.org/x/net` and `x/text`.
- **A contract with the published image**: nothing an init container used under a tag disappears from it without a line in `tests/contract-removed.tsv`.
- **Every digest signed** with cosign, keyless, with SBOM, SLSA provenance and a GitHub build attestation; Trivy on every published line; CVE counts against the images it replaces after every publish.
- **Every test shown the breaks it exists for**: twelve planted violations in `tests/plants.tsv`, run in CI.

https://github.com/heyvaldemar/os-shell-docker/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/heyvaldemar/os-shell-docker/releases/tag/v1.0.3
[1.0.2]: https://github.com/heyvaldemar/os-shell-docker/releases/tag/v1.0.2
[1.0.1]: https://github.com/heyvaldemar/os-shell-docker/releases/tag/v1.0.1
[1.0.0]: https://github.com/heyvaldemar/os-shell-docker/releases/tag/v1.0.0
