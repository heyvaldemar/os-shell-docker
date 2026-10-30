# os-shell Docker Image

[![Publish Docker Image](https://github.com/heyvaldemar/os-shell-docker/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/os-shell-docker/actions/workflows/publish.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/heyvaldemar/os-shell.svg)](https://hub.docker.com/r/heyvaldemar/os-shell)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/heyvaldemar/os-shell-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/heyvaldemar/os-shell-docker)
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/16090/badge)](https://www.bestpractices.dev/projects/16090)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A Debian shell for the init containers Helm charts run before their application: fixing the owner of a data volume, setting a kernel parameter, waiting for a port. Rebuilt every week, signed, and laid out like `bitnami/os-shell`, so a chart written for that image runs on this one unchanged.

`bitnami/os-shell` has published one tag since August 2025: `latest`, and it is no longer Debian. It is built on VMware Photon OS 5.0. The versioned Debian tags stopped at `12-debian-12-r51` on 2025-08-19 and live on, unmaintained, as `bitnamilegacy/os-shell`, pulled 2.96 million times by 2026-10-28. A chart that pinned one of those tags stopped receiving fixes that day: on 2026-10-30 Trivy found 19 critical and 171 high findings in `12-debian-12-r51`, and 119 of them have a fix that image will never get.

```bash
docker run --rm heyvaldemar/os-shell:12 bash -c 'id; cat /etc/debian_version'
```

In a Bitnami chart, name this image wherever the chart takes its os-shell, for example PostgreSQL's volume permissions:

```yaml
global:
  security:
    allowInsecureImages: true   # Bitnami's charts refuse images from outside their catalogue without it
volumePermissions:
  enabled: true
  image:
    registry: docker.io
    repository: heyvaldemar/os-shell
    tag: "12"
```

## Tags

| Tag | What it is | Moves |
|---|---|---|
| `12` | Debian 12 (bookworm), the line `bitnami/os-shell:12` was | every week and on every change here, with Debian's security updates; never to another Debian release |
| `13` | Debian 13 (trixie) | the same, on Debian 13 |
| `latest` | the newest line, `13` | as `13`, and to the next Debian release when this image adds it |

Every tag moves, so a pinned tag keeps receiving security fixes. For an image that never changes, pin its digest:

```bash
docker buildx imagetools inspect heyvaldemar/os-shell:12 --format '{{.Manifest.Digest}}'
```

Images are `linux/amd64` and `linux/arm64`. Debian 12's security updates come from Debian LTS until 30 June 2028.

## A drop-in for bitnami/os-shell

Charts depend on how the image runs, not only on its shell. This one keeps what `bitnami/os-shell:12` did:

- the user, `1001` with group `0`, so it also runs under an arbitrary UID in group 0 (OpenShift), and as root where the chart asks for root;
- no entrypoint and the command `/bin/bash`, so `command: ["/bin/bash", "-ec", "..."]` works as it did;
- `HOME=/`, and `PATH` with `/opt/bitnami/common/bin` first;
- the tools init containers call: bash, coreutils (`chown`, `chmod`, `mkdir`), `find`, `sysctl`, `ulimit`, `curl`, `jq`, `openssl`, `perl`, the procps tools, and Bitnami's helpers `wait-for-port`, `render-template`, `ini-file`, plus `scuttle` and `yq`, all under `/opt/bitnami/common/bin`;
- the build `SHELL` an image built `FROM` it inherits: bash with `errexit`, `nounset` and `pipefail`.

**It is checked, not claimed.** Two tests run on every build, and nothing is published unless both pass:

- `tests/drop-in-test.sh` compares the image with the last versioned Bitnami one, `bitnamilegacy/os-shell:12-debian-12-r51`: the same user, command, working directory, build `SHELL`, `HOME` and `PATH`; every executable on its `PATH` on this one's; and the same calls an init container makes, run on both images as the users they run as (`chown -R 1001:1001` as root, `sysctl`, `wait-for-port` against a listening and a closed port, `render-template`, `ini-file`, `yq`). The executables that are not here are named in [`tests/drop-in-absent.tsv`](tests/drop-in-absent.tsv) and, for the Debian 13 line, [`tests/drop-in-absent-debian-13.tsv`](tests/drop-in-absent-debian-13.tsv), each with its reason: Bitnami's own package scripts, minideb's `initctl` stub, and tools Debian 13 no longer ships. The test fails on any absence without a reason.
- `tests/charts-e2e.sh` installs Bitnami's own charts on a fresh kind cluster with this image as their os-shell: PostgreSQL with `volumePermissions` (an init container as root chowns the data volume) and Redis with `sysctl` (a privileged init container sets `net.core.somaxconn`). Both must become Ready, each init container must have run this image and exited 0, the data directory must belong to 1001, PostgreSQL must answer a query, and Redis must see the new value.

## CVE counts

Counted by Trivy 0.76.1 on 2026-10-30 in [run 40994910781](https://github.com/heyvaldemar/os-shell-docker/actions/runs/40994910781), on the images as published, on `linux/amd64`, once per CVE and package, with no vendor statements applied:

| Image | What it is | OS | Critical | High | Medium | Low | Critical and high with a fix |
|---|---|---|---|---|---|---|---|
| `bitnamilegacy/os-shell:12-debian-12-r51` | the last versioned `bitnami/os-shell`, frozen 2025-08-19 | Debian 12.11 | 19 | 171 | 289 | 217 | 119 |
| `bitnami/os-shell:latest` | what `bitnami/os-shell` publishes now | Photon OS 5.0 | 0 | 5 | 13 | 1 | 5 |
| `heyvaldemar/os-shell:12` | this image, Debian 12 line | Debian 12.15 | 1 | 71 | 125 | 166 | 0 |
| `heyvaldemar/os-shell:13` | this image, Debian 13 line | Debian 13.7 | 0 | 56 | 95 | 156 | 0 |

- **The last column is the one a rebuild controls.** Every critical and high finding left in this image is one Debian has not fixed yet: Trivy lists no fixed version for it. `scripts/cve-gate.sh` refuses to publish an image that carries one with a fix, so the week Debian ships a fix, the next build carries it or nothing is published.
- **`bitnami/os-shell:latest` has fewer findings in total, and it is a different operating system.** A chart that switched from a pinned Debian tag to `latest` now runs its init containers on Photon OS, with five high findings that already have a fix.
- **The frozen image only gets worse.** Its 119 fixable findings are fixed in Debian and in Go, and none of those fixes will reach it.

The `Publish Docker Image` workflow counts again after every publish, on the images it has just published, and keeps the table as a run artifact.

## Nothing you used yesterday disappears today

Before anything is published, each build is compared with the image already published under its tag (`scripts/contract-test.sh`): every executable on its `PATH`, its user, working directory, entrypoint, command, build `SHELL`, `HOME` and `PATH`, and the Debian release the tag promises. A removal has to be named in `tests/contract-removed.tsv` and in the changelog.

Each test is shown the breaks it exists for (`tests/plants.tsv`, run in CI): the image running as root, the build `SHELL` lost, another command, `curl` or the procps tools left out, Bitnami's helpers left out or no longer first on `PATH`, `HOME` moved, the Debian 12 init-script tools dropped, a helper or `yq` built from a commit other than the pinned one, and `scuttle` built with its 2020 `golang.org/x` libraries again.

## Supply chain

- Debian 12 and 13 slim, and the Go toolchain image, each pinned by digest; Dependabot moves the digests by pull request, gated by the full build and tests.
- Every package brought to the newest version Debian's security archive has at build time, the base's own included.
- The five helpers built from source with Go 1.27.3, each cloned at its release tag and refused unless the tag names the commit pinned in the `Dockerfile`; `go.sum` and the Go checksum database verify every dependency. `scuttle`'s last release (2022) pins `golang.org/x/net` and `x/text` from 2020, and `yq`'s pins an `x/net` one release behind; both are built with the versions pinned in the `Dockerfile`, which removes the findings against the old ones. The helpers' licences are in `/opt/bitnami/common/licenses`, and `/opt/bitnami/common/helpers.txt` lists each one's tag and commit.
- Every published digest is signed with cosign, keyless, by this repository's workflow; SBOM (SPDX) and SLSA provenance are attached, and build provenance is attested in [GitHub Attestations](https://github.com/heyvaldemar/os-shell-docker/attestations).
- Trivy scans every published line and reports critical and high fixable findings to the Security tab.
- Every GitHub Action is pinned to a commit SHA, except the SLSA generator `release-assets.yml` calls by tag (`@v2.1.0`), because it verifies its own reference at run time and refuses a SHA.

```bash
cosign verify heyvaldemar/os-shell:12 \
  --certificate-identity-regexp "https://github.com/heyvaldemar/os-shell-docker/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Build it yourself

```bash
docker build --build-arg DEBIAN_MAJOR=12 -t os-shell:12 .
./tests/drop-in-test.sh os-shell:12
./scripts/cve-gate.sh os-shell:12
./tests/charts-e2e.sh os-shell:12        # needs kind and helm
```

`tests/drop-in-test.sh` compares on `linux/amd64`, the platform of the reference image; on an arm64 host, build with `--platform linux/amd64`.

## Bugs, changes and vulnerabilities

Report a bug or ask for a change in [issues](https://github.com/heyvaldemar/os-shell-docker/issues). Pull requests are welcome: every test above runs on them before anything can merge. Report a vulnerability privately, as [SECURITY.md](SECURITY.md) describes.

## Related

[heyvaldemar/kubectl](https://hub.docker.com/r/heyvaldemar/kubectl) does the same for `bitnami/kubectl`: one Kubernetes minor per tag, rebuilt weekly, signed, and checked against the last versioned Bitnami image.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
