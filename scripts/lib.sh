#!/usr/bin/env bash
set -euo pipefail

# common helper functions for k3d image import and kubeconfig fixes

# Normalize kubeconfig endpoints (replace 0.0.0.0 with 127.0.0.1)
fix_kubeconfig_paths() {
  local cfgs=("$PWD/.k3d_kubeconfig" "$HOME/.kube/config")
  for cfg in "${cfgs[@]}"; do
    if [ -f "$cfg" ]; then
      if command -v sed >/dev/null 2>&1; then
        sed -i.bak -e 's/0.0.0.0/127.0.0.1/g' "$cfg" || true
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

# Robust k3d image import wrapper. Tries safe variants based on available k3d CLI behavior.
k3d_import_cmd() {
  local src="$1"
  if ! command -v k3d >/dev/null 2>&1; then
    return 2
  fi
  # probe help to detect flags supported
  local helpout
  helpout=$(k3d image import --help 2>&1 || true)
  # try -c if supported
  if printf '%s' "$helpout" | grep -q -E '\-c\b'; then
    if k3d image import -c mycluster "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # try --cluster
  if printf '%s' "$helpout" | grep -q -- '--cluster'; then
    if k3d image import --cluster mycluster "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # try positional cluster then image
  if printf '%s' "$helpout" | grep -q 'image import <'; then
    if k3d image import mycluster "$src" >/dev/null 2>&1; then
      return 0
    fi
  fi
  # try file-only or image-only fallback
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
  helpout=$(k3d image --help 2>&1 || true)
  if printf '%s' "$helpout" | grep -q -E '\-c\b'; then
    k3d image list -c mycluster 2>/dev/null || k3d image list 2>/dev/null
  else
    k3d image list 2>/dev/null || true
  fi
}
