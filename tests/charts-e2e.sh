#!/usr/bin/env bash
# Do Bitnami's own charts run their init containers on this image?
#
#   tests/charts-e2e.sh <image>
#
# The image is loaded into a fresh kind cluster and named as the os-shell
# image of two Bitnami charts, as a user would after bitnami/os-shell stopped
# moving:
#   - postgresql with volumePermissions: the init container runs as root and
#     chowns the data volume to 1001 with find, mkdir, chmod and chown;
#   - redis with sysctl: a privileged init container sets
#     net.core.somaxconn, and redis must see the new value.
# Both releases must become Ready with the init container exited 0 on this
# image. The charts are pinned; their main images are the charts' defaults.
set -euo pipefail
IMAGE="${1:?usage: charts-e2e.sh <image>}"
CLUSTER="${CLUSTER:-os-shell-e2e}"
KIND_NODE="${KIND_NODE:-}"
POSTGRESQL_CHART="${POSTGRESQL_CHART:-18.12.16}"
REDIS_CHART="${REDIS_CHART:-}"
SOMAXCONN=4096
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

repo="${IMAGE%:*}"; tag="${IMAGE##*:}"
[ "$repo" != "$IMAGE" ] || { echo "name the image with a tag, for example os-shell:12" >&2; exit 2; }

cleanup() { [ -n "${KEEP_CLUSTER:-}" ] || kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
# Keep the script's own exit status: the trap must not turn a failure into 0.
on_exit() { local rc=$?; cleanup; exit "$rc"; }
trap on_exit EXIT
kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
node=()
[ -z "$KIND_NODE" ] || node=(--image "$KIND_NODE")
kind create cluster --name "$CLUSTER" ${node[@]+"${node[@]}"} --wait 120s >/dev/null
kind load docker-image "$IMAGE" --name "$CLUSTER" >/dev/null
export KUBECONFIG
KUBECONFIG="$(mktemp)"
kind get kubeconfig --name "$CLUSTER" >"$KUBECONFIG"

# Bitnami's charts refuse an image from outside their catalogue unless told it
# is meant (global.security.allowInsecureImages); that is the switch a user
# flips too.
common=(--set global.security.allowInsecureImages=true --wait --timeout 6m)

if helm install pg oci://registry-1.docker.io/bitnamicharts/postgresql --version "$POSTGRESQL_CHART" \
  --set volumePermissions.enabled=true \
  --set volumePermissions.image.registry=docker.io \
  --set "volumePermissions.image.repository=${repo}" \
  --set "volumePermissions.image.tag=${tag}" \
  --set volumePermissions.image.pullPolicy=Never \
  "${common[@]}" >/dev/null; then ok "postgresql became Ready"; else bad "postgresql did not become Ready"; fi

redis_version=()
[ -z "$REDIS_CHART" ] || redis_version=(--version "$REDIS_CHART")
if helm install cache oci://registry-1.docker.io/bitnamicharts/redis ${redis_version[@]+"${redis_version[@]}"} \
  --set architecture=standalone \
  --set sysctl.enabled=true \
  --set sysctl.image.registry=docker.io \
  --set "sysctl.image.repository=${repo}" \
  --set "sysctl.image.tag=${tag}" \
  --set sysctl.image.pullPolicy=Never \
  --set "sysctl.command={/bin/sh,-c,sysctl -w net.core.somaxconn=${SOMAXCONN}}" \
  "${common[@]}" >/dev/null; then ok "redis became Ready"; else bad "redis did not become Ready"; fi

# Each init container ran this image and exited 0.
check_init() {
  local pod="$1" container="$2" image exit_code
  image="$(kubectl get pod "$pod" -o jsonpath="{.spec.initContainers[?(@.name=='${container}')].image}")"
  exit_code="$(kubectl get pod "$pod" -o jsonpath="{.status.initContainerStatuses[?(@.name=='${container}')].state.terminated.exitCode}")"
  case "$image" in *"${repo}:${tag}") ;; *) bad "$pod/$container ran '$image', not this image"; return ;; esac
  if [ "$exit_code" = 0 ]; then ok "$pod/$container ran this image and exited 0"; else bad "$pod/$container exit code '${exit_code}'"; kubectl logs "$pod" -c "$container" >&2 || true; fi
}
check_init pg-postgresql-0 init-chmod-data
check_init cache-redis-master-0 init-sysctl

# What the init containers were for.
owner="$(kubectl exec pg-postgresql-0 -c postgresql -- stat -c %u /bitnami/postgresql/data 2>/dev/null || true)"
if [ "$owner" = 1001 ]; then ok "the PostgreSQL data directory belongs to 1001"; else bad "the PostgreSQL data directory belongs to '${owner}'"; fi
if kubectl exec pg-postgresql-0 -c postgresql -- env PGPASSWORD="$(kubectl get secret pg-postgresql -o jsonpath='{.data.postgres-password}' | base64 -d)" \
     psql -U postgres -tAc 'select 1' 2>/dev/null | grep -qx 1; then ok "PostgreSQL answers a query"; else bad "PostgreSQL does not answer"; fi
value="$(kubectl exec cache-redis-master-0 -c redis -- cat /proc/sys/net/core/somaxconn 2>/dev/null || true)"
if [ "$value" = "$SOMAXCONN" ]; then ok "redis sees net.core.somaxconn=${SOMAXCONN}"; else bad "redis sees net.core.somaxconn='${value}'"; fi

[ "$fail" -eq 0 ] || { echo "Bitnami's charts do not run on ${IMAGE}." >&2; exit 1; }
echo "Bitnami's postgresql and redis charts run their init containers on ${IMAGE}."
