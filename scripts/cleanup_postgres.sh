#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG="${1:-./.k3d_kubeconfig}"

# Aggressive cleanup: remove finalizers quickly via kubectl patch and delete resources
kubectl --kubeconfig "$KUBECONFIG" -n default get pvc postgres-pvc -o name 2>/dev/null | grep -q . && {
  echo "Patching PVC to remove finalizers and deleting"
  kubectl --kubeconfig "$KUBECONFIG" -n default patch pvc postgres-pvc --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  kubectl --kubeconfig "$KUBECONFIG" -n default delete pvc postgres-pvc --ignore-not-found=true || true
}

kubectl --kubeconfig "$KUBECONFIG" get pv pv-postgres-hostpath -o name 2>/dev/null | grep -q . && {
  echo "Patching PV to remove finalizers and deleting"
  kubectl --kubeconfig "$KUBECONFIG" patch pv pv-postgres-hostpath --type=merge -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
  kubectl --kubeconfig "$KUBECONFIG" delete pv pv-postgres-hostpath --ignore-not-found=true || true
}

# Short wait loop (30s) for deletion
for i in $(seq 1 30); do
  pvc_exists=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pvc postgres-pvc --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  pv_exists=$(kubectl --kubeconfig "$KUBECONFIG" get pv pv-postgres-hostpath --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || true)
  if [ -z "$pvc_exists" ] && [ -z "$pv_exists" ]; then
    echo "PVC and PV removed"
    exit 0
  fi
  sleep 1
done

echo "warning: pvc/pv may still exist after timeout; continuing" >&2
exit 0
