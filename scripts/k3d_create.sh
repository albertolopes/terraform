#!/usr/bin/env bash
set -euo pipefail

CLUSTER_CONFIG=${CLUSTER_CONFIG:-"$(pwd)/cluster.yaml"}
DRY_RUN=${DRY_RUN:-0}
WORKDIR=$(pwd)
KUBECONFIG_PATH="$WORKDIR/.k3d_kubeconfig"

if [ ! -f "$CLUSTER_CONFIG" ]; then
  echo "Cluster config not found: $CLUSTER_CONFIG" >&2
  exit 1
fi

# simple YAML parsing
name=$(awk -F":" '/^name:/ {gsub(/"| /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
servers=$(awk -F":" '/^servers:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
agents=$(awk -F":" '/^agents:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
maxpods=$(awk -F":" '/maxPodsPerNode/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)

name=${name:-mycluster}
servers=${servers:-1}
agents=${agents:-0}
maxpods=${maxpods:-110}
name=${K3D_CLUSTER_NAME:-$name}

# If cluster already exists, handle it
if k3d cluster list --no-headers | awk '{print $1}' | grep -xq "$name"; then
  if [ "${FORCE_RECREATE:-0}" = "1" ] || [ "${FORCE_RECREATE:-false}" = "true" ]; then
    echo "FORCE_RECREATE set — deleting existing cluster $name"
    k3d cluster delete "$name" || true
  else
    echo "Cluster $name already exists: skipping creation."
    exit 0
  fi
fi

# Build base command with stable API port, listening on all interfaces
API_PORT=6443
CMD=(k3d cluster create "$name" --wait --servers "$servers" --agents "$agents")
CMD+=(--api-port "0.0.0.0:$API_PORT") # Listen on all interfaces

# Kubelet and Traefik args
CMD+=(--k3s-arg "--kubelet-arg=--max-pods=$maxpods@server:0")
CMD+=(--k3s-arg "--disable=traefik@server:0")

# Expose HTTP/HTTPS ports
CMD+=(--port "80:80@loadbalancer" --port "443:443@loadbalancer")

# Mount volumes
VOLUME_DIRS=("$WORKDIR/volume/postgres" "$WORKDIR/volume/minio" "$WORKDIR/volume/nginx")
for d in "${VOLUME_DIRS[@]}"; do
  mkdir -p "$d" || true
  CMD+=(--volume "$d:$d@all")
done

# Execute and export kubeconfig
echo "Executing: ${CMD[*]}"
"${CMD[@]}"
k3d kubeconfig get "$name" > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"
echo "Wrote kubeconfig to $KUBECONFIG_PATH"

# Wait for the cluster API to be fully ready using the initial kubeconfig
echo "Waiting for Kubernetes API to be ready..."
timeout=120
step=5
elapsed=0
while ! kubectl --kubeconfig "$KUBECONFIG_PATH" get nodes >/dev/null 2>&1; do
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timed out waiting for Kubernetes API." >&2
    exit 1
  fi
  echo "API not ready yet, waiting ${step}s..."
  sleep ${step}
  elapsed=$((elapsed + step))
done

echo "Cluster '$name' created and API is ready."

# --- AUTOMATE KUBECONFIG FIX FOR EXTERNAL ACCESS (THE FINAL, CORRECT WAY) ---
# Get the server's primary non-localhost IP address
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$SERVER_IP" ]; then
  echo "Could not determine server's LAN IP. Kubeconfig will not be modified." >&2
  exit 1
fi

# Get the cluster name from the kubeconfig
CLUSTER_NAME=$(kubectl --kubeconfig "$KUBECONFIG_PATH" config view -o jsonpath='{.clusters[0].name}')

# Use kubectl to set the server address AND skip TLS verification
echo "Updating kubeconfig for external access..."
kubectl --kubeconfig "$KUBECONFIG_PATH" config set-cluster "$CLUSTER_NAME" \
  --server="https://$SERVER_IP:$API_PORT" \
  --insecure-skip-tls-verify=true

echo "Kubeconfig updated to use server IP $SERVER_IP and skip TLS verification."
