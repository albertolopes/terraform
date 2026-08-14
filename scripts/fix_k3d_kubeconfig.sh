#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH=${KUBECONFIG_PATH:-"$(pwd)/.k3d_kubeconfig"}
CONTEXT=${CONTEXT:-"k3d-mycluster"}
SERVER=${SERVER:-"https://127.0.0.1:6443"}

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: kubeconfig not found: $KUBECONFIG_PATH" >&2
  exit 1
fi

cluster_name=$(kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw \
  -o jsonpath="{.contexts[?(@.name==\"$CONTEXT\")].context.cluster}")

if [ -z "$cluster_name" ]; then
  echo "ERROR: context not found in kubeconfig: $CONTEXT" >&2
  kubectl --kubeconfig "$KUBECONFIG_PATH" config get-contexts
  exit 1
fi

kubectl --kubeconfig "$KUBECONFIG_PATH" config set-cluster "$cluster_name" \
  --server="$SERVER" \
  --insecure-skip-tls-verify=true

kubectl --kubeconfig "$KUBECONFIG_PATH" config unset "clusters.$cluster_name.certificate-authority-data" >/dev/null 2>&1 || true
kubectl --kubeconfig "$KUBECONFIG_PATH" config use-context "$CONTEXT" >/dev/null
chmod 600 "$KUBECONFIG_PATH"

echo "Updated $KUBECONFIG_PATH"
kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw \
  -o jsonpath="{.clusters[?(@.name==\"$cluster_name\")].cluster.server}{'\n'}"
