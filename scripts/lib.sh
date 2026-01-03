#!/usr/bin/env bash
set -euo pipefail

# common helper functions for k3d image import and kubeconfig fixes

# Normalize kubeconfig endpoints (replace 0.0.0.0 with 127.0.0.1)
fix_kubeconfig_paths() {
  local cfgs=("$PWD/.k3d_kubeconfig" "$HOME/.kube/config")
  for cfg in "${cfgs[@]}"; do
    if [ -f "$cfg" ]; then
      # Use a safe temp-file replace to avoid sed -i rename errors on some filesystems
      if command -v sed >/dev/null 2>&1; then
        local tmp
        tmp=$(mktemp "${cfg}.tmp.XXXX") || tmp="${cfg}.tmp"
        if sed -e 's/0.0.0.0/127.0.0.1/g' "$cfg" > "$tmp" 2>/dev/null; then
          # attempt atomic move; preserve permissions if possible
          chmod --reference="$cfg" "$tmp" 2>/dev/null || true
          mv "$tmp" "$cfg" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; }
        else
          rm -f "$tmp" 2>/dev/null || true
        fi
      fi
    fi
  done
}

# Wait for kube-apiserver to become responsive
wait_for_kube_api() {
  local kubeconfig=${1:-$PWD/.k3d_kubeconfig}
  local max_attempts=${2:-30}
  local sleep_for=${3:-2}
  local i=0
  while [ $i -lt $max_attempts ]; do
    if kubectl --kubeconfig "$kubeconfig" get --raw=/healthz >/dev/null 2>&1; then
      return 0
    fi
    # also accept kubectl version success as sign of API availability
    if kubectl --kubeconfig "$kubeconfig" version --short >/dev/null 2>&1; then
      return 0
    fi
    i=$((i+1))
    sleep "$sleep_for"
  done
  return 1
}

# Apply a manifest file with a fallback to --validate=false when server-side validation fails
kubectl_apply_with_validate_fallback() {
  local kubeconfig=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
  local file=${1:--}
  if kubectl --kubeconfig "$kubeconfig" apply -f "$file"; then
    return 0
  fi
  echo "kubectl apply failed; retrying with --validate=false" >&2
  kubectl --kubeconfig "$kubeconfig" apply --validate=false -f "$file"
}

# Safe apply: only call kubectl if the file exists and contains non-comment Kubernetes objects
safe_kubectl_apply() {
  local file="$1"
  if [ -z "$file" ] || [ ! -f "$file" ]; then
    echo "safe_kubectl_apply: file not found: $file"
    return 0
  fi
  # Check for non-empty, non-comment lines and presence of apiVersion or kind
  if grep -E -v '^\s*#' "$file" | grep -q '\S' && grep -qE '^\s*(apiVersion|kind):' "$file"; then
    kubectl_apply_with_validate_fallback "$file"
  else
    echo "safe_kubectl_apply: no objects to apply in $file; skipping"
  fi
}

# Robust k3d image import wrapper. Tries safe variants based on available k3d CLI behavior.
# Prefer using a cluster name from env var K3D_CLUSTER_NAME or fallback to 'mycluster'.
k3d_import_cmd() {
  local src="$1"
  if ! command -v k3d >/dev/null 2>&1; then
    return 2
  fi
  local cluster_name=${K3D_CLUSTER_NAME:-mycluster}
  # probe help to detect flags supported
  local helpout
  helpout=$(k3d image import --help 2>&1 || true)

  # Try long-form --cluster first (safer across versions)
  if printf '%s' "$helpout" | grep -q -- '--cluster'; then
    if k3d image import --cluster "$cluster_name" "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Try explicit positional cluster then image (older variants)
  if printf '%s' "$helpout" | grep -q 'image import <'; then
    if k3d image import "$cluster_name" "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Try shorthand -c only if help indicates support for it (some builds differ)
  if printf '%s' "$helpout" | grep -q -E '\-c\b'; then
    if k3d image import -c "$cluster_name" "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi

  # Fallback: import without cluster arg (may import into default context)
  if k3d image import "$src" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Provide k3d_import convenience wrapper (some scripts call k3d_import)
k3d_import() {
  local src="$1"
  if ! command -v k3d >/dev/null 2>&1; then
    return 2
  fi
  if declare -f k3d_import_cmd >/dev/null 2>&1; then
    k3d_import_cmd "$src" && return 0 || true
  fi
  local cluster_name=${K3D_CLUSTER_NAME:-mycluster}
  # try several forms
  if k3d image import --cluster "$cluster_name" "$src" >/dev/null 2>&1; then
    return 0
  fi
  if k3d image import "$cluster_name" "$src" >/dev/null 2>&1; then
    return 0
  fi
  if k3d image import "$src" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# safe k3d image list wrapper: prefer cluster-scoped list if supported
k3d_list() {
  if ! command -v k3d >/dev/null 2>&1; then
    return 2
  fi
  local helpout
  helpout=$(k3d image --help 2>&1 || true)
  local cluster_name=${K3D_CLUSTER_NAME:-mycluster}
  if printf '%s' "$helpout" | grep -q -E '\-c\b|--cluster'; then
    k3d image list --cluster "$cluster_name" 2>/dev/null || k3d image list 2>/dev/null
  else
    k3d image list 2>/dev/null || true
  fi
}
