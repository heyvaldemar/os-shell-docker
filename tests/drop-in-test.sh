#!/usr/bin/env bash
# Is this image a drop-in for bitnami/os-shell?
#
#   tests/drop-in-test.sh <image> [<bitnami-image>]
#
# A chart written for bitnami/os-shell depends on how that image runs: the
# user (1001, group 0), no entrypoint and the command /bin/bash, HOME=/, the
# PATH with /opt/bitnami/common/bin first, the build SHELL an image built FROM
# it inherits, and the tools its init containers call. The last versioned
# Debian image (bitnamilegacy/os-shell:12-debian-12-r51, August 2025) is the
# reference. Every executable on its PATH must be on this image's PATH, unless
# tests/drop-in-absent.tsv names it with the reason.
# The checks below are single-quoted on purpose: each runs inside a container,
# and its variables expand there, not here.
# shellcheck disable=SC2016
set -euo pipefail
IMAGE="${1:?usage: drop-in-test.sh <image> [<bitnami-image>]}"
REF="${2:-bitnamilegacy/os-shell:12-debian-12-r51}"
TESTS="$(dirname "$0")"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

# Compare on one architecture. Docker Desktop's containerd store needs
# --platform to read an amd64 image's config on an arm64 host; older engines
# (GitHub's runners) do not know the flag.
docker pull -q --platform linux/amd64 "$REF" >/dev/null
ref_inspect() { docker image inspect --platform linux/amd64 "$@" 2>/dev/null || docker image inspect "$@"; }
for field in User Entrypoint Cmd WorkingDir Shell; do
  a="$(ref_inspect -f "{{json .Config.$field}}" "$REF")"
  b="$(docker image inspect -f "{{json .Config.$field}}" "$IMAGE")"
  if [ "$a" = "$b" ]; then ok "$field as bitnami/os-shell ($b)"; else bad "$field: bitnami/os-shell $a, this image $b"; fi
done
for var in HOME PATH OS_NAME BITNAMI_APP_NAME; do
  a="$(ref_inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$REF" | sed -n "s/^${var}=//p")"
  b="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | sed -n "s/^${var}=//p")"
  if [ "$a" = "$b" ]; then ok "$var as bitnami/os-shell ($b)"; else bad "$var: bitnami/os-shell '$a', this image '$b'"; fi
done

executables() {
  docker run --rm --platform "$2" --entrypoint sh "$1" -c '
    IFS=:
    for d in $PATH; do
      [ -d "$d" ] || continue
      for f in "$d"/*; do [ -f "$f" ] && [ -x "$f" ] && echo "${f##*/}"; done
    done' | sort -u
}
platform="$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$IMAGE")"
# The Debian line, for that line's own list of tools Debian no longer ships.
line="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | sed -n 's/^APP_VERSION=//p')"
unexplained=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  matched=false
  while IFS=$'\t' read -r pattern _; do
    case "$pattern" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    if [[ "$name" == $pattern ]]; then matched=true; break; fi
  done < <(cat "$TESTS/drop-in-absent.tsv" "$TESTS/drop-in-absent-debian-${line}.tsv" 2>/dev/null)
  $matched || unexplained="$unexplained $name"
done < <(comm -23 <(executables "$REF" linux/amd64) <(executables "$IMAGE" "$platform"))
if [ -z "$unexplained" ]; then
  ok "every executable on bitnami/os-shell's PATH is here, or named in tests/drop-in-absent*.tsv with its reason"
else
  bad "on bitnami/os-shell's PATH and not here, with no reason given:$unexplained"
fi

# The calls init containers make, on both images, as the users they run as.
as_both() {
  local user="$1" c="$2"
  if docker run --rm --platform linux/amd64 --user "$user" "$REF" bash -c "$c" >/dev/null 2>&1; then
    if docker run --rm --user "$user" "$IMAGE" bash -c "$c" >/dev/null 2>&1; then ok "'$c' as $user runs on both"; else bad "'$c' as $user runs on bitnami/os-shell and not here"; fi
  else
    bad "'$c' as $user does not run on bitnami/os-shell either; the test is wrong"
  fi
}
as_both 0 'mkdir -p /bitnami/data && chown -R 1001:1001 /bitnami && [ "$(stat -c %u:%g /bitnami/data)" = 1001:1001 ]'
as_both 0 'chmod 700 /tmp && stat -c %a /tmp | grep -qx 700'
as_both 1001 'sysctl -n kernel.ostype | grep -qx Linux'
as_both 1001 'ulimit -n >/dev/null'
as_both 1001 'curl --version >/dev/null && jq -n 1 >/dev/null && openssl version >/dev/null && perl -e 1 && ps -p 1 >/dev/null'
as_both 1001 'printf "x: {{x}}\n" | x=1 render-template | grep -qx "x: 1"'
as_both 1001 'ini-file set --section s --key k --value v /tmp/t.ini && ini-file get --section s --key k /tmp/t.ini | grep -qx v'
as_both 1001 'command -v wait-for-port >/dev/null && ! wait-for-port --timeout 1 --host 127.0.0.1 1'
as_both 1001 'perl -MIO::Socket::INET -e "my \$s = IO::Socket::INET->new(LocalAddr => q(127.0.0.1), LocalPort => 18080, Listen => 1, ReuseAddr => 1) or die; sleep 6" & wait-for-port --timeout 5 --host 127.0.0.1 18080'
as_both 1001 'printf "a: 1\n" | yq .a | grep -qx 1'
as_both 1001 'id -u | grep -qx 1001 && id -g | grep -qx 0'

[ "$fail" -eq 0 ] || { echo "Not a drop-in for bitnami/os-shell." >&2; exit 1; }
echo "A drop-in for bitnami/os-shell."
