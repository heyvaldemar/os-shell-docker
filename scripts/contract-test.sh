#!/usr/bin/env bash
# Contract test: does a new build keep every promise the published image made?
#
#   scripts/contract-test.sh <new-image> <published-image> <debian-major>
#
# The drop-in test asks whether this image still matches bitnami/os-shell.
# This asks the question an init container cares about next: is anything it
# used yesterday gone today? A base image update that drops a binary nobody
# advertised passes every other check and breaks a chart on Monday morning.
# So the published image is the baseline, and the new build must keep:
#
#   - every executable on PATH (a removal must be listed, with its reason, in
#     tests/contract-removed.tsv, which the changelog then has to explain);
#   - the user, working directory, entrypoint, command, build SHELL, PATH and
#     HOME;
#   - the Debian line the tag promises.
#
# With nothing published under the tag yet, there is no contract to keep and
# the test says so.
set -euo pipefail

NEW="${1:?usage: contract-test.sh <new-image> <published-image> <debian-major>}"
BASE="${2:?usage: contract-test.sh <new-image> <published-image> <debian-major>}"
MAJOR="${3:?usage: contract-test.sh <new-image> <published-image> <debian-major>}"
REMOVED_FILE="$(dirname "$0")/../tests/contract-removed.tsv"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

if ! docker pull -q "$BASE" >/dev/null 2>&1; then
  echo "nothing is published as $BASE yet: no contract to keep"
  exit 0
fi
echo "new:       $NEW"
echo "published: $BASE ($(docker image inspect -f '{{index .RepoDigests 0}}' "$BASE" 2>/dev/null || echo local))"

executables() {
  docker run --rm --entrypoint sh "$1" -c '
    IFS=:
    for d in $PATH; do
      [ -d "$d" ] || continue
      for f in "$d"/*; do
        [ -f "$f" ] && [ -x "$f" ] && echo "${f##*/}"
      done
    done' | sort -u
}
allowed="$(grep -vE '^\s*(#|$)' "$REMOVED_FILE" 2>/dev/null | awk '{print $1}' | sort -u || true)"
missing="$(comm -23 <(executables "$BASE") <(executables "$NEW"))"
unexplained="$(comm -23 <(printf '%s\n' "$missing" | sed '/^$/d') <(printf '%s\n' "$allowed" | sed '/^$/d'))"
if [ -n "$unexplained" ]; then
  bad "executables the published image has and this build does not: $(echo "$unexplained" | tr '\n' ' ')(list each in tests/contract-removed.tsv with its reason if the removal is meant)"
else
  ok "every executable on the published image's PATH is still there ($(executables "$NEW" | grep -c .) on PATH)"
fi

for field in User WorkingDir Entrypoint Cmd Shell; do
  a="$(docker image inspect -f "{{json .Config.$field}}" "$BASE")"
  b="$(docker image inspect -f "{{json .Config.$field}}" "$NEW")"
  if [ "$a" = "$b" ]; then ok "$field unchanged ($b)"; else bad "$field changed: published $a, this build $b"; fi
done
for var in PATH HOME; do
  a="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$BASE" | sed -n "s/^$var=//p")"
  b="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$NEW" | sed -n "s/^$var=//p")"
  if [ "$a" = "$b" ]; then ok "$var unchanged (${b:-unset})"; else bad "$var changed: published '${a}', this build '${b}'"; fi
done

debian() { docker run --rm --entrypoint cat "$1" /etc/debian_version | cut -d. -f1; }
b="$(debian "$NEW")"
if [ "$b" = "$MAJOR" ]; then ok "the build stays on Debian $MAJOR"; else bad "the build is Debian $b, not the Debian $MAJOR this tag promises"; fi

if [ "$fail" -ne 0 ]; then echo "The contract is broken; nothing is published." >&2; exit 1; fi
echo "The contract holds."
