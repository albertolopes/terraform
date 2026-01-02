#!/usr/bin/env bash
set -euo pipefail

# run_deploy.sh
# Runs the full flow: ensure scripts executable, pre-pull/import images (ingress + nginx),
# run terraform init/apply and collect diagnostics if needed.
# Usage: run from the Terraform module directory:
#   cd /home/beto/Documentos/aaa-pessoal/terraform
#   ./run_deploy.sh 2>&1 | tee run_deploy.log

PROJECT_DIR="$(pwd)"
K3D_CLUSTER_NAME="mycluster"
COMPOSE_SRC="./docker-compose.test.yml"
COMPOSE_DEST="./docker-compose.yml"

# Ensure k3d cluster exists (create if missing) and export kubeconfig
ensure_k3d_cluster() {
  if ! command -v k3d >/dev/null 2>&1; then
    echo "k3d not found in PATH; skipping cluster ensure" >&2
    return 2
  fi

  if k3d cluster list | awk '{print $1}' | grep -qw "$K3D_CLUSTER_NAME"; then
    echo "k3d cluster '$K3D_CLUSTER_NAME' exists"
  else
    echo "k3d cluster '$K3D_CLUSTER_NAME' not found — creating"
    k3d cluster create "$K3D_CLUSTER_NAME" --wait || {
      echo "k3d cluster create failed" >&2
      return 1
    }
  fi

  # regenerate kubeconfig for the cluster
  k3d kubeconfig get "$K3D_CLUSTER_NAME" > "$PROJECT_DIR/.k3d_kubeconfig" 2>/dev/null || true
  chmod 600 "$PROJECT_DIR/.k3d_kubeconfig" || true
}

merge_kubeconfig() {
  # Merge the generated .k3d_kubeconfig into the user's default kubeconfig (~/.kube/config)
  SRC="$PROJECT_DIR/.k3d_kubeconfig"
  DEST_DIR="$HOME/.kube"
  DEST="$DEST_DIR/config"

  if [ ! -f "$SRC" ]; then
    echo "No $SRC to merge; skipping" >&2
    return 1
  fi

  mkdir -p "$DEST_DIR"
  # If no existing config, just copy
  if [ ! -f "$DEST" ]; then
    cp "$SRC" "$DEST" && chmod 600 "$DEST" && echo "Installed kubeconfig to $DEST"
    return 0
  fi

  # Try to merge using kubectl if available
  if command -v kubectl >/dev/null 2>&1; then
    BACKUP="$DEST.$(date +%s).bak"
    cp -p "$DEST" "$BACKUP" || true
    echo "Backed up existing kubeconfig to $BACKUP"
    KUBECONFIG="$DEST:$SRC" kubectl config view --flatten > "$DEST.tmp" && mv "$DEST.tmp" "$DEST" && chmod 600 "$DEST" && echo "Merged $SRC into $DEST"
    return $?
  else
    # fallback: append contexts/users/clusters by concatenation (best effort)
    BACKUP="$DEST.$(date +%s).bak"
    cp -p "$DEST" "$BACKUP" || true
    echo "Backed up existing kubeconfig to $BACKUP"
    # naive append: put new config as a separate file and leave it to user to merge
    cp "$SRC" "$DEST_DIR/config.$(date +%s)" && echo "Saved extra kubeconfig to $DEST_DIR (please merge manually)"
    return 0
  fi
}

# Import an image into k3d cluster using the CLI variant available
k3d_import() {
  src="$1"
  if ! command -v k3d >/dev/null 2>&1; then
    echo "k3d not found; cannot import $src" >&2
    return 2
  fi

  # try variants in order
  if k3d image import -c "$K3D_CLUSTER_NAME" "$src" >/dev/null 2>&1; then
    echo "k3d import succeeded (variant: -c) for $src"
    return 0
  fi
  if k3d image import --cluster "$K3D_CLUSTER_NAME" "$src" >/dev/null 2>&1; then
    echo "k3d import succeeded (variant: --cluster) for $src"
    return 0
  fi
  if k3d image import "$src" >/dev/null 2>&1; then
    echo "k3d import succeeded (variant: plain) for $src"
    return 0
  fi

  # fallback: return non-zero so caller can try tar-based import
  echo "k3d image import failed for $src with all tested variants" >&2
  return 1
}

echo "Working dir: $PROJECT_DIR"

# make scripts executable
chmod +x ./scripts/*.sh || true

# ensure docker-compose.yml present
if [ -f "$COMPOSE_SRC" ] && [ ! -f "$COMPOSE_DEST" ]; then
  cp -f "$COMPOSE_SRC" "$COMPOSE_DEST"
  echo "Copied $COMPOSE_SRC -> $COMPOSE_DEST"
fi

# Ensure k3d cluster exists so imports and kubectl can work
ensure_k3d_cluster || true
merge_kubeconfig || true

# retry helper (POSIX-safe)
retry() {
  max="$1"; shift
  i=0
  sleep_for=2
  until "$@"; do
    i=$((i+1))
    if [ "$i" -ge "$max" ]; then
      echo "Command failed after $i attempts: $*" >&2
      return 1
    fi
    echo "Retry $i/$max for: $*" >&2
    sleep "$sleep_for"
    sleep_for=$((sleep_for * 2))
  done
}

# Pre-pull/import common ingress images to avoid ImagePullBackOff
INGRESS_IMAGES=(
  "registry.k8s.io/ingress-nginx/controller:v1.14.1"
  "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.6.5"
)

echo "Pre-pulling/importing ingress images into k3d ($K3D_CLUSTER_NAME)"
for img in "${INGRESS_IMAGES[@]}"; do
  echo "--> processing $img"
  if retry 2 docker pull --platform linux/amd64 "$img"; then
    echo "Pulled $img"
    if command -v k3d >/dev/null 2>&1; then
      k3d_import "$img" || true
    fi
    continue
  fi
  # try mirror names quickly
  MIRRORS=(
    "k8s.gcr.io/ingress-nginx/controller:v1.14.1"
    "quay.io/ingress-nginx/controller:v1.14.1"
    "k8s.gcr.io/ingress-nginx/kube-webhook-certgen:v1.6.5"
    "quay.io/ingress-nginx/kube-webhook-certgen:v1.6.5"
  )
  for m in "${MIRRORS[@]}"; do
    if retry 2 docker pull --platform linux/amd64 "$m"; then
      echo "Pulled mirror $m; tagging as $img and importing"
      docker tag "$m" "$img" || true
      TAR=$(mktemp -u /tmp/imgXXXX.tar)
      docker save -o "$TAR" "$img" || true
      if command -v k3d >/dev/null 2>&1; then
        k3d_import "$TAR" || true
      fi
      rm -f "$TAR" || true
      break
    fi
  done
done

# Extract nginx image from compose and pre-pull/import using awk
if [ -f docker-compose.yml ]; then
  # Use awk to extract the image token under the nginx service, then strip quotes in shell
  NGINX_IMAGE=$(awk '
    BEGIN{in_services=0; in_nginx=0}
    /^[[:space:]]*services[[:space:]]*:/ { in_services=1; next }
    in_services && /^[^[:space:]]/ { if(in_nginx) exit }
    in_services && /^[[:space:]]*nginx[[:space:]]*:/ { in_nginx=1; next }
    in_nginx && /^[[:space:]]*image[[:space:]]*:/ {
      line=$0
      sub(/^[[:space:]]*image[[:space:]]*:[[:space:]]*/,"",line)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
      print line; exit
    }
  ' docker-compose.yml || true)
  # strip surrounding single or double quotes if present
  if [ -n "$NGINX_IMAGE" ]; then
    # strip surrounding double or single quotes (portable)
    NGINX_IMAGE=$(printf '%s' "$NGINX_IMAGE" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  else
    echo "Could not detect nginx image in docker-compose.yml" >&2
  fi
else
  echo "docker-compose.yml missing; aborting" >&2
  exit 1
fi

if [ -n "$NGINX_IMAGE" ]; then
  echo "Found nginx image: $NGINX_IMAGE"
  if retry 5 docker pull --platform linux/amd64 "$NGINX_IMAGE"; then
    echo "Pulled $NGINX_IMAGE"
    if command -v k3d >/dev/null 2>&1; then
      k3d_import "$NGINX_IMAGE" >/dev/null 2>&1 || true
    fi
  else
    echo "Warning: docker pull $NGINX_IMAGE failed; cluster may try to pull it" >&2
  fi
else
  echo "Could not detect nginx image in docker-compose.yml" >&2
fi

# Note: do NOT run terraform init/apply from here — this script is executed by Terraform
# The provisioner will perform image pre-pulls/imports and the Kubernetes apply steps only.
echo "Skipping terraform init/apply inside run_deploy.sh (Terraform is driving execution)"

# Post-deploy diagnostics
export KUBECONFIG="$PROJECT_DIR/.k3d_kubeconfig"

echo "===== cluster-info ====="
kubectl cluster-info || true

echo "===== pods (all namespaces) ====="
kubectl get pods -A -o wide || true

echo "===== default ns resources ====="
kubectl -n default get pods,svc,deploy -o wide || true

echo "===== nginx ConfigMaps ====="
kubectl -n default get configmap nginx-config nginx-confdir nginx-snippets nginx-html -o yaml || true

echo "===== nginx TLS secret ====="
kubectl -n default get secret nginx-tls -o yaml || true

# Save diagnostics if nginx not ready
NG_POD=$(kubectl -n default get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$NG_POD" ]; then
  READY=$(kubectl -n default get pod "$NG_POD" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || echo false)
  if [ "$READY" != "true" ]; then
    DIAG_FILE="$PROJECT_DIR/.nginx_deploy_diagnostics.txt"
    echo "Collecting diagnostics into $DIAG_FILE"
    {
      date
      echo
      echo "kubectl -n default get pods -o wide"
      kubectl -n default get pods -o wide || true
      echo
      echo "describe $NG_POD"
      kubectl -n default describe pod "$NG_POD" || true
      echo
      echo "logs $NG_POD"
      kubectl -n default logs "$NG_POD" --tail=200 || true
      echo
      echo "events"
      kubectl -n default get events --sort-by=.metadata.creationTimestamp | tail -n 200 || true
      echo
      echo "k3d image list"
      (k3d image list -c "$K3D_CLUSTER_NAME" 2>/dev/null || k3d image list 2>/dev/null) || true
      echo
      echo "docker images | grep nginx"
      docker images | grep nginx || true
    } > "$DIAG_FILE"
    echo "Diagnostics written to $DIAG_FILE"
  fi
fi

echo "run_deploy.sh finished"
