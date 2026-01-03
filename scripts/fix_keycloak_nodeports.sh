#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
NAMESPACE=${NAMESPACE:-default}
SERVICE=${SERVICE:-keycloak}

# Preferred ports to try first
PREFERRED=(32080 32087 32090 32100 32101 32102)

echo "Gathering used nodePorts from cluster..."
USED_NODEPORTS=$(kubectl --kubeconfig "$KUBECONFIG" get svc -A -o jsonpath='{range .items[*]}{.spec.ports[*].nodePort}{" "}{end}' 2>/dev/null || true)
# normalize
USED_NODEPORTS=($USED_NODEPORTS)

echo "Gathering host listening TCP ports..."
HOST_PORTS=$(ss -lnt 2>/dev/null || true)
HOST_USED=()
if [ -n "$HOST_PORTS" ]; then
  # extract ports from local addresses
  while read -r line; do
    port=$(echo "$line" | awk '{print $4}' | sed -E 's/.*:([0-9]+)$/\1/' | grep -E '^[0-9]+$' || true)
    if [ -n "$port" ]; then HOST_USED+=("$port"); fi
  done <<<"$HOST_PORTS"
fi

is_used() {
  local v=$1
  for x in "${USED_NODEPORTS[@]}"; do [ "$x" = "$v" ] && return 0; done
  for x in "${HOST_USED[@]}"; do [ "$x" = "$v" ] && return 0; done
  return 1
}

pick_free() {
  for p in "${PREFERRED[@]}"; do
    if ! is_used "$p"; then echo "$p"; return 0; fi
  done
  for ((p=30000;p<=32767;p++)); do
    if ! is_used "$p"; then echo "$p"; return 0; fi
  done
  return 1
}

P1=$(pick_free) || { echo "Could not find free nodePort" >&2; exit 1; }
P2=$(pick_free) || { echo "Could not find free nodePort for debug" >&2; exit 1; }
P3=$(pick_free) || { echo "Could not find free nodePort for management" >&2; exit 1; }

echo "Selected nodePorts: http=$P1 debug=$P2 management=$P3"

PATCH=$(cat <<EOF
{
  "spec": {
    "type": "LoadBalancer",
    "ports": [
      {"name":"http","port":8080,"targetPort":8080,"nodePort":$P1},
      {"name":"debug","port":8787,"targetPort":8787,"nodePort":$P2},
      {"name":"management","port":9000,"targetPort":9000,"nodePort":$P3}
    ]
  }
}
EOF
)

echo "Patching service $SERVICE in namespace $NAMESPACE with chosen nodePorts..."
kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" patch svc "$SERVICE" --type=merge -p "$PATCH" || {
  echo "Patch failed; attempting to recreate service by fetching current manifest, updating nodePorts, and applying" >&2
  kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get svc "$SERVICE" -o yaml > /tmp/${SERVICE}.yaml
  sed -E -i "/nodePort:/d" /tmp/${SERVICE}.yaml
  cat >> /tmp/${SERVICE}.yaml <<YAML
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    nodePort: $P1
  - name: debug
    port: 8787
    targetPort: 8787
    nodePort: $P2
  - name: management
    port: 9000
    targetPort: 9000
    nodePort: $P3
YAML
  kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" apply -f /tmp/${SERVICE}.yaml || { echo "Failed to apply updated service manifest" >&2; exit 1; }
}

echo "Patched service. Waiting briefly for svclb to reconcile..."
sleep 3
# find svclb pods
echo "Listing svclb pods and recent events (kube-system)..."
kubectl --kubeconfig "$KUBECONFIG" -n kube-system get pods -o wide | grep svclb || true
# describe any svclb pods
for pod in $(kubectl --kubeconfig "$KUBECONFIG" -n kube-system get pods -o name | grep svclb || true); do
  echo "--- describing $pod ---"
  kubectl --kubeconfig "$KUBECONFIG" -n kube-system describe $pod || true
done

echo "Done. New service nodePorts:"
kubectl --kubeconfig "$KUBECONFIG" -n "$NAMESPACE" get svc "$SERVICE" -o wide || true


