#!/usr/bin/env bash
set -euo pipefail

# Recreate k3d cluster with host path mounts so Kubernetes hostPath PVs map to your repo volume/*
# Usage: ./scripts/k3d_recreate_with_mounts.sh [--name mycluster] [--servers 1] [--agents 1] [--wait]

CLUSTER_NAME="mycluster"
SERVERS=1
AGENTS=1
WAIT_FLAG="--wait"

# parse args simple
while [ $# -gt 0 ]; do
  case "$1" in
    --name) CLUSTER_NAME="$2"; shift 2;;
    --servers) SERVERS="$2"; shift 2;;
    --agents) AGENTS="$2"; shift 2;;
    --no-wait) WAIT_FLAG=""; shift ;;
    *) echo "Unknown arg: $1"; exit 1;;
  esac
done

WORKDIR=$(pwd)
VOLUME_DIRS=("$WORKDIR/volume/postgres" "$WORKDIR/volume/minio" "$WORKDIR/volume/nginx")

echo "Cluster: $CLUSTER_NAME servers=$SERVERS agents=$AGENTS"

# Ensure k3d installed
if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d is not installed or not in PATH" >&2
  exit 2
fi

# Delete existing cluster if present
if k3d cluster list | grep -q "^$CLUSTER_NAME\b"; then
  echo "Deleting existing k3d cluster $CLUSTER_NAME"
  k3d cluster delete "$CLUSTER_NAME"
fi

# Build volume args: mount each host dir into the same absolute path inside the nodes, on all nodes
VOLUME_ARGS=()
for d in "${VOLUME_DIRS[@]}"; do
  if [ -d "$d" ] || mkdir -p "$d"; then
    echo "Will mount host dir: $d"
    # mount to same path inside node; use @all to mount into all nodes
    VOLUME_ARGS+=("--volume" "$d:$d@all")
  else
    echo "Warning: could not create or find $d" >&2
  fi
done

# Additional ports: keep 80 and 443 forwarded to loadbalancer
PORT_ARGS=("--port" "80:80@loadbalancer" "--port" "443:443@loadbalancer")

# Compose full create command
CMD=(k3d cluster create "$CLUSTER_NAME" "$WAIT_FLAG" --servers "$SERVERS" --agents "$AGENTS")
# add kubelet max-pods argument as before
CMD+=(--k3s-arg "--kubelet-arg=--max-pods=110@server:0" --k3s-arg "--kubelet-arg=--max-pods=110@agent:0")

# add volume args
for ((i=0;i<${#VOLUME_ARGS[@]};i++)); do
  CMD+=("${VOLUME_ARGS[i]}")
done
# add ports
for ((i=0;i<${#PORT_ARGS[@]};i++)); do
  CMD+=("${PORT_ARGS[i]}")
done

# Print and run
echo "Running: ${CMD[*]}"
"${CMD[@]}"

echo "k3d cluster $CLUSTER_NAME created. Export kubeconfig to ./.k3d_kubeconfig if needed."

# Export kubeconfig for Terraform/scripts
if k3d kubeconfig get "$CLUSTER_NAME" >/dev/null 2>&1; then
  k3d kubeconfig get "$CLUSTER_NAME" > "$WORKDIR/.k3d_kubeconfig"
  chmod 600 "$WORKDIR/.k3d_kubeconfig" || true
  echo "Wrote kubeconfig to $WORKDIR/.k3d_kubeconfig"
fi

# Notes: after recreation you may need to re-import images into the cluster or reapply manifests
