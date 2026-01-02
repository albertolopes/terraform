#!/usr/bin/env bash
set -euo pipefail
MODULE_DIR=${MODULE_DIR:-$(pwd)}
# ensure ~/.local/bin exists and is in PATH for this script
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Install k3d locally if not present
if ! command -v k3d >/dev/null 2>&1; then
  echo "k3d not found — downloading latest k3d into $HOME/.local/bin/k3d"
  curl -sL "https://github.com/k3d-io/k3d/releases/latest/download/k3d-linux-amd64" -o "$HOME/.local/bin/k3d"
  chmod +x "$HOME/.local/bin/k3d"
fi

# Allow overriding the host port for Postgres LB mapping
K3D_POSTGRES_HOST_PORT=${K3D_POSTGRES_HOST_PORT:-15432}
# MinIO host ports (hostPort:containerPort mapping)
K3D_MINIO_HOST_PORT=${K3D_MINIO_HOST_PORT:-19000}
K3D_MINIO_CONSOLE_HOST_PORT=${K3D_MINIO_CONSOLE_HOST_PORT:-19001}

if ! k3d cluster list | grep -q "^mycluster\b"; then
  echo "Creating k3d cluster 'mycluster' with port mapping 80:80@loadbalancer, 443:443@loadbalancer, 30080:30080@loadbalancer, ${K3D_POSTGRES_HOST_PORT}:5432@loadbalancer"
  k3d cluster create mycluster --wait --k3s-arg "--disable=traefik@server:0" \
    --port "80:80@loadbalancer" --port "443:443@loadbalancer" --port "30080:30080@loadbalancer" \
    --port "${K3D_POSTGRES_HOST_PORT}:5432@loadbalancer" --port "${K3D_MINIO_HOST_PORT}:9000@loadbalancer" --port "${K3D_MINIO_CONSOLE_HOST_PORT}:9001@loadbalancer"
else
  echo "Cluster 'mycluster' exists — recreating to ensure correct port mappings and Traefik disabled"
  k3d cluster delete mycluster || true
  k3d cluster create mycluster --wait --k3s-arg "--disable=traefik@server:0" \
    --port "80:80@loadbalancer" --port "443:443@loadbalancer" --port "30080:30080@loadbalancer" \
    --port "${K3D_POSTGRES_HOST_PORT}:5432@loadbalancer" --port "${K3D_MINIO_HOST_PORT}:9000@loadbalancer" --port "${K3D_MINIO_CONSOLE_HOST_PORT}:9001@loadbalancer"
fi

# export kubeconfig for this cluster to module path so other steps can read it
k3d kubeconfig get mycluster > "$MODULE_DIR/.k3d_kubeconfig"
# Replace 0.0.0.0 endpoints with 127.0.0.1 to avoid kubectl trying to connect to 0.0.0.0
if command -v sed >/dev/null 2>&1; then
  sed -i.bak -e 's/0.0.0.0/127.0.0.1/g' "$MODULE_DIR/.k3d_kubeconfig" || true
fi
chmod 600 "$MODULE_DIR/.k3d_kubeconfig"
