#!/usr/bin/env bash
set -euo pipefail

CLUSTER_CONFIG=${CLUSTER_CONFIG:-"$(pwd)/cluster.yaml"}
DRY_RUN=${DRY_RUN:-0}
WORKDIR=$(pwd)

if [ ! -f "$CLUSTER_CONFIG" ]; then
  echo "Cluster config not found: $CLUSTER_CONFIG" >&2
  exit 1
fi

# simple YAML parsing (works for the simple structure we have)
name=$(awk -F":" '/^name:/ {gsub(/"| /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
servers=$(awk -F":" '/^servers:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
agents=$(awk -F":" '/^agents:/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)
maxpods=$(awk -F":" '/maxPodsPerNode/ {gsub(/ /, "", $2); print $2; exit}' "$CLUSTER_CONFIG" || true)

name=${name:-mycluster}
servers=${servers:-1}
agents=${agents:-0}
maxpods=${maxpods:-110}

# allow override via env var
name=${K3D_CLUSTER_NAME:-$name}

# Build base command
CMD=(k3d cluster create "$name" --wait --servers "$servers" --agents "$agents")
# kubelet max-pods on server and agent
CMD+=(--k3s-arg "--kubelet-arg=--max-pods=$maxpods@server:0" --k3s-arg "--kubelet-arg=--max-pods=$maxpods@agent:0")

# Optionally mount repo volume directories into all nodes so hostPath PVs map to host
VOLUME_DIRS=("$WORKDIR/volume/postgres" "$WORKDIR/volume/minio" "$WORKDIR/volume/nginx")
for d in "${VOLUME_DIRS[@]}"; do
  # ensure host dir exists
  if [ ! -d "$d" ]; then
    mkdir -p "$d" || true
  fi
  # add mount to all nodes
  CMD+=(--volume "$d:$d@all")
done

# Expose HTTP/HTTPS ports on loadbalancer
CMD+=(--port "80:80@loadbalancer" --port "443:443@loadbalancer")

# Show command
echo "k3d create command to run:"
printf '%s ' "${CMD[@]}"
echo

if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
  echo "DRY_RUN=yes — not executing"
  exit 0
fi

# If cluster already exists, optionally delete/recreate when FORCE_RECREATE is set
if command -v k3d >/dev/null 2>&1; then
  if k3d cluster list --no-headers | awk '{print $1}' | grep -xq "$name"; then
    if [ "${FORCE_RECREATE:-0}" = "1" ] || [ "${FORCE_RECREATE:-false}" = "true" ]; then
      echo "FORCE_RECREATE set — deleting existing cluster $name"
      k3d cluster delete "$name" || true
    else
      echo "Cluster $name already exists: skipping creation"
      # Export kubeconfig for use by other scripts
      if k3d kubeconfig get "$name" >/dev/null 2>&1; then
        k3d kubeconfig get "$name" > "$WORKDIR/.k3d_kubeconfig" || true
        chmod 600 "$WORKDIR/.k3d_kubeconfig" || true
        echo "Wrote kubeconfig to $WORKDIR/.k3d_kubeconfig"
      fi
      echo "Applying docker resource hints (best-effort)"
      SERVER_LB="k3d-${name}-serverlb"
      if docker ps --format '{{.Names}}' | grep -q "^${SERVER_LB}$"; then
        docker update --cpus 1.0 --memory 2g --memory-swap 2g "${SERVER_LB}" || true
      fi
      exit 0
    fi
  fi
fi

# Execute the command
echo "Executing: ${CMD[*]}"
"${CMD[@]}"

# Export kubeconfig
if k3d kubeconfig get "$name" >/dev/null 2>&1; then
  k3d kubeconfig get "$name" > "$WORKDIR/.k3d_kubeconfig"
  chmod 600 "$WORKDIR/.k3d_kubeconfig" || true
  echo "Wrote kubeconfig to $WORKDIR/.k3d_kubeconfig"
fi

echo "Cluster '$name' created"
