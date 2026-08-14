#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH=${KUBECONFIG_PATH:-"$(pwd)/.k3d_kubeconfig"}
CONTEXT=${CONTEXT:-"k3d-mycluster"}

echo "kubeconfig: $KUBECONFIG_PATH"

if [ ! -f "$KUBECONFIG_PATH" ]; then
  echo "ERROR: kubeconfig not found" >&2
  exit 1
fi

echo
echo "cluster server:"
kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath="{.clusters[?(@.name==\"$CONTEXT\")].cluster.server}{'\n'}" || true

echo
echo "current context:"
kubectl --kubeconfig "$KUBECONFIG_PATH" config current-context || true

echo
echo "available contexts:"
kubectl --kubeconfig "$KUBECONFIG_PATH" config get-contexts

echo
echo "credentials present for context user:"
USER_NAME=$(kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath="{.contexts[?(@.name==\"$CONTEXT\")].context.user}")
echo "user: $USER_NAME"
kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath="{.users[?(@.name==\"$USER_NAME\")].user.client-certificate-data}" | wc -c | awk '{print "client-certificate-data bytes: " $1}'
kubectl --kubeconfig "$KUBECONFIG_PATH" config view --raw -o jsonpath="{.users[?(@.name==\"$USER_NAME\")].user.client-key-data}" | wc -c | awk '{print "client-key-data bytes: " $1}'

echo
echo "kubectl get namespaces:"
kubectl --kubeconfig "$KUBECONFIG_PATH" --context "$CONTEXT" get namespaces

echo
echo "kubectl auth can-i get namespaces:"
kubectl --kubeconfig "$KUBECONFIG_PATH" --context "$CONTEXT" auth can-i get namespaces
