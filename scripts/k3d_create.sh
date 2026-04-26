#!/usr/bin/env bash
set -euo pipefail

CLUSTER_CONFIG=${CLUSTER_CONFIG:-"$(pwd)/cluster.yaml"}
DRY_RUN=${DRY_RUN:-0}
WORKDIR=$(pwd)
KUBECONFIG_PATH="$WORKDIR/.k3d_kubeconfig"

# ==============================
# Validate dependencies
# ==============================

if ! command -v k3d >/dev/null 2>&1; then
  echo "ERROR: k3d is not installed or not in PATH" >&2
  exit 127
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is not installed or not in PATH" >&2
  exit 127
fi

# Resolve full paths (important for Terraform environment)
K3D_BIN=$(command -v k3d)
KUBECTL_BIN=$(command -v kubectl)

echo "Using k3d: $K3D_BIN"
echo "Using kubectl: $KUBECTL_BIN"

# ==============================
# Validate config
# ==============================

if [ ! -f "$CLUSTER_CONFIG" ]; then
  echo "Cluster config not found: $CLUSTER_CONFIG" >&2
  exit 1
fi

# ==============================
# Parse YAML (simple)
# ==============================

name=$(awk -F":" '/^name:/ {gsub(/"| /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
servers=$(awk -F":" '/^servers:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
agents=$(awk -F":" '/^agents:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
maxpods=$(awk -F":" '/maxPodsPerNode/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)

name=${name:-mycluster}
servers=${servers:-1}
agents=${agents:-0}
maxpods=${maxpods:-110}
name=${K3D_CLUSTER_NAME:-$name}

# ==============================
# Check existing cluster
# ==============================

if $K3D_BIN cluster list --no-headers | awk '{print $1}' | grep -xq "$name"; then
  if [ "${FORCE_RECREATE:-0}" = "1" ] || [ "${FORCE_RECREATE:-false}" = "true" ]; then
    echo "FORCE_RECREATE set — deleting existing cluster $name"
    $K3D_BIN cluster delete "$name" || true
  else
    echo "Cluster $name already exists: skipping creation."
    exit 0
  fi
fi

# ==============================
# Build command
# ==============================

API_PORT=6443

CMD=(
  "$K3D_BIN" cluster create "$name"
  --wait
  --servers "$servers"
  --agents "$agents"
  --api-port "0.0.0.0:$API_PORT"
  --dns 1.1.1.1
  --dns 1.0.0.1
)

CMD+=(--k3s-arg "--kubelet-arg=--max-pods=$maxpods@server:0")
CMD+=(--k3s-arg "--disable=traefik@server:0")

CMD+=(--port "80:80@loadbalancer" --port "8443:443@loadbalancer")

VOLUME_DIRS=(
  "$WORKDIR/volume/postgres"
  "$WORKDIR/volume/minio"
  "$WORKDIR/volume/nginx"
)

for d in "${VOLUME_DIRS[@]}"; do
  mkdir -p "$d" || true
  CMD+=(--volume "$d:$d@all")
done

# ==============================
# Execute
# ==============================

echo "Executing: ${CMD[*]}"

if [ "$DRY_RUN" = "1" ]; then
  echo "Dry run enabled, skipping execution"
else
  "${CMD[@]}"
fi

# ==============================
# Export kubeconfig
# ==============================

$K3D_BIN kubeconfig get "$name" > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

echo "Wrote kubeconfig to $KUBECONFIG_PATH"

# ==============================
# Wait for API
# ==============================

echo "Waiting for Kubernetes API to be ready..."

timeout=120
step=5
elapsed=0

while ! $KUBECTL_BIN --kubeconfig "$KUBECONFIG_PATH" get nodes >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timed out waiting for Kubernetes API." >&2
    exit 1
  fi
  echo "API not ready yet, waiting ${step}s..."
  sleep $step
  elapsed=$((elapsed + step))
done

echo "Cluster '$name' created and API is ready."

# ==============================
# Fix kubeconfig (external access)
# ==============================

SERVER_IP=$(hostname -I | awk '{print $1}')

if [ -z "$SERVER_IP" ]; then
  echo "Could not determine server IP" >&2
  exit 1
fi

CLUSTER_NAME=$($KUBECTL_BIN --kubeconfig "$KUBECONFIG_PATH" config view -o jsonpath='{.clusters[0].name}')

echo "Updating kubeconfig for external access..."

$KUBECTL_BIN --kubeconfig "$KUBECONFIG_PATH" config set-cluster "$CLUSTER_NAME" \
  --server="https://$SERVER_IP:$API_PORT" \
  --insecure-skip-tls-verify=true

echo "Kubeconfig updated to use $SERVER_IP"