# syntax=docker/dockerfile:1.7

# ──────────────────────────────────────────────────────────────────────────────
# heyvaldemar/os-shell: the small Debian shell image Helm charts run as an init
# container (volume permissions, sysctl, waiting for a port), rebuilt every
# week, signed, and laid out like bitnami/os-shell, so a chart written for that
# image runs on this one unchanged: the same user (1001, group 0), no
# entrypoint and the command /bin/bash, HOME=/, the same PATH, the same tools,
# Bitnami's four helpers under /opt/bitnami/common/bin, and the same build
# SHELL for images built FROM it.
#
# One Dockerfile, two lines: DEBIAN_MAJOR=12 (bookworm, the line
# bitnami/os-shell:12 was) and DEBIAN_MAJOR=13 (trixie).
# ──────────────────────────────────────────────────────────────────────────────
ARG DEBIAN_MAJOR=12

# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: the helpers bitnami/os-shell carried in /opt/bitnami/common/bin,
# every one built from source with a current Go: Bitnami's wait-for-port,
# render-template and ini-file, scuttle, and yq. Each is cloned at a release
# tag and refused unless the tag names the commit pinned here; go.sum and the
# checksum database verify every dependency. Built on the build platform and
# cross-compiled, so no emulation runs Go.
#
# Two of them name golang.org/x libraries with fixed vulnerabilities: scuttle's
# last release (2022) pins x/net and x/text from 2020, and yq's release pins an
# x/net one release behind. Those two get the versions pinned below, the
# smallest change that removes the findings; the build and the tests are what
# say it still works.
# ──────────────────────────────────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM golang:1.27-bookworm@sha256:d9b6a1beb9474adc2a1ce842573639b44b2a0dd49b6669f51d3821baf9ec37c9 AS tools

ARG TARGETOS
ARG TARGETARCH
ARG WAIT_FOR_PORT=v1.0.11:7874547cb49ec88b92a5fbf3dfee28bd6694cfc4
ARG RENDER_TEMPLATE=v1.0.10:bc9a6df0be359c708fdc675c7e2d3e5a92a4ab40
ARG INI_FILE=v1.4.10:e7032a7f1f507af21709946d0d2a440124d1488b
ARG SCUTTLE=v1.3.7:1c2b697935c10ef4b3e5e0dc0cf573a4d8766269
ARG YQ=v4.54.1:504fc38780cc46be8444ea1b72fb55919fc0bfb0
ARG X_NET=v0.62.0
ARG X_TEXT=v0.43.0

ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /src

# DL3062 reads `go get` as unpinned; both modules are pinned, by X_NET and X_TEXT.
# hadolint ignore=DL3062
RUN set -euo pipefail; \
    build() { \
      local name="$1" repo="$2" pin="$3" ldflags="$4" lift="$5" tag sha; \
      tag="${pin%%:*}"; sha="${pin#*:}"; \
      git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" "https://github.com/${repo}.git" "$name"; \
      [ "$(git -C "$name" rev-parse HEAD)" = "$sha" ] || { echo "${repo} ${tag} is not commit ${sha}" >&2; exit 1; }; \
      if [ "$lift" = lift ]; then \
        go -C "$name" get "golang.org/x/net@${X_NET}" "golang.org/x/text@${X_TEXT}" && go -C "$name" mod tidy; \
      fi; \
      GOOS="$TARGETOS" GOARCH="$TARGETARCH" go -C "$name" build -mod=readonly -trimpath -ldflags "-s -w ${ldflags}" -o "/out/bin/${name}" .; \
      mkdir -p "/out/licenses/${name}" && cp "${name}/LICENSE"* "/out/licenses/${name}/"; \
      printf '%s %s %s%s\n' "$name" "$tag" "$sha" "$([ "$lift" = lift ] && echo " with golang.org/x/net ${X_NET}, x/text ${X_TEXT}")" >> /out/helpers.txt; \
    }; \
    build wait-for-port bitnami/wait-for-port "$WAIT_FOR_PORT" "" ""; \
    build render-template bitnami/render-template "$RENDER_TEMPLATE" "" ""; \
    build ini-file bitnami/ini-file "$INI_FILE" "" ""; \
    build scuttle redboxllc/scuttle "$SCUTTLE" "-X main.Version=${SCUTTLE%%:*}" lift; \
    build yq mikefarah/yq "$YQ" "" lift; \
    printf "built with %s\n" "$(go env GOVERSION)" >> /out/helpers.txt

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: the image. Both bases are pinned by digest; DEBIAN_MAJOR picks one.
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3 AS base-12
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS base-13

# hadolint ignore=DL3006
FROM base-${DEBIAN_MAJOR} AS final

ARG DEBIAN_MAJOR
ARG TARGETARCH
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# THE TOOLS INIT CONTAINERS CALL. bitnami/os-shell:12 was Bitnami's minideb
# with curl, jq, procps, openssl and perl on top; charts call chown, chmod,
# find, mkdir, sysctl, ulimit, curl and jq by name. The rest of its package set
# is installed too, so tests/drop-in-test.sh finds every executable the last
# versioned Bitnami image had on its PATH. Debian 13 no longer ships the old
# init-script tools, so the 13 line leaves them out (tests/drop-in-absent.tsv).
# hadolint ignore=DL3008
# Every package is brought to the newest version the suite's security archive
# has at build time, the base's own included: the weekly rebuild is how a fix
# Debian has published reaches this image, and scripts/cve-gate.sh refuses to
# publish one that still carries a fixed critical or high finding.
RUN apt-get update \
 && apt-get -y upgrade \
 && packages="ca-certificates curl jq libfile-find-rule-perl openssl perl procps tzdata util-linux-extra" \
 && if [ "$DEBIAN_MAJOR" = 12 ]; then packages="$packages insserv lsb-base startpar sysv-rc"; else packages="$packages adduser gpgv insserv startpar"; fi \
 && read -r -a list <<<"$packages" \
 && apt-get install -y --no-install-recommends "${list[@]}" \
 && rm -rf /var/lib/apt/lists/*

COPY --from=tools /out/bin/ /opt/bitnami/common/bin/
COPY --from=tools /out/licenses/ /opt/bitnami/common/licenses/
COPY --from=tools /out/helpers.txt /opt/bitnami/common/helpers.txt

ENV HOME=/ \
    PATH=/opt/bitnami/common/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OS_ARCH=${TARGETARCH} \
    OS_FLAVOUR=debian-${DEBIAN_MAJOR} \
    OS_NAME=linux \
    APP_VERSION=${DEBIAN_MAJOR} \
    BITNAMI_APP_NAME=os-shell

LABEL org.opencontainers.image.title="os-shell" \
      org.opencontainers.image.description="A Debian shell for init containers, rebuilt weekly, signed; a drop-in for bitnami/os-shell." \
      org.opencontainers.image.authors="Vladimir Mikhalev <v@valdemar.ai>" \
      org.opencontainers.image.vendor="heyvaldemar" \
      org.opencontainers.image.source="https://github.com/heyvaldemar/os-shell-docker" \
      org.opencontainers.image.documentation="https://github.com/heyvaldemar/os-shell-docker#readme" \
      org.opencontainers.image.url="https://hub.docker.com/r/heyvaldemar/os-shell" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.heyvaldemar.os-shell.debian="${DEBIAN_MAJOR}"

# What an image built FROM this one inherits for its RUN lines, as
# bitnami/os-shell set it: a failing command, an unset variable or a failing
# pipe stops the build.
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]

USER 1001
CMD ["/bin/bash"]
