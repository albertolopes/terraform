#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG="${KUBECONFIG:-./.k3d_kubeconfig}"
OUTDIR="/tmp/tls-secrets-$$"
mkdir -p "$OUTDIR"

# Helper to create self-signed cert for a host and create k8s tls secret
create_tls_secret() {
  local host=$1
  local secret_name=$2

  echo "Generating TLS cert for $host -> secret $secret_name"
  local key="$OUTDIR/${host}.key.pem"
  local crt="$OUTDIR/${host}.crt.pem"

  # generate private key and cert
  openssl req -newkey rsa:2048 -nodes -keyout "$key" \
    -x509 -days 365 -out "$crt" -subj "/CN=${host}" >/dev/null 2>&1

  # create or replace Kubernetes TLS secret
  kubectl --kubeconfig "$KUBECONFIG" -n default delete secret "$secret_name" >/dev/null 2>&1 || true
  kubectl --kubeconfig "$KUBECONFIG" -n default create secret tls "$secret_name" --key="$key" --cert="$crt"
  echo "Created TLS secret $secret_name"
}

# Hosts and secret names
create_tls_secret "minio.127.0.0.1.nip.io" "minio-tls"
create_tls_secret "keycloak.127.0.0.1.nip.io" "keycloak-tls"

# cleanup
rm -rf "$OUTDIR"

echo "All TLS secrets created"

