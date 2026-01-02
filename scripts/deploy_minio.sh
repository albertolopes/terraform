#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}
IMAGE=${MINIO_IMAGE:-"minio/minio:latest"}

# ensure docker image exists locally and import to k3d
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker pull "$IMAGE" || true
fi
if command -v k3d >/dev/null 2>&1; then
  k3d image import -c mycluster "$IMAGE" >/dev/null 2>&1 || true
fi

# Ensure PVC health: if PVC exists but is Pending and references a missing PV or wrong storageClass, delete it so hostPath PV can bind
PVC_NAME=minio-pvc
EXISTING_PVC_JSON=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pvc "$PVC_NAME" -o json 2>/dev/null || true)
if [ -n "$EXISTING_PVC_JSON" ]; then
  PVC_PHASE=$(echo "$EXISTING_PVC_JSON" | jq -r '.status.phase')
  PVC_SC=$(echo "$EXISTING_PVC_JSON" | jq -r '.spec.storageClassName // ""')
  PVC_VOLNAME=$(echo "$EXISTING_PVC_JSON" | jq -r '.spec.volumeName // ""')
  if [ "$PVC_PHASE" != "Bound" ]; then
    DELETE_PVC=false
    if [ -n "$PVC_VOLNAME" ]; then
      PV_EXISTS=$(kubectl --kubeconfig "$KUBECONFIG" get pv "$PVC_VOLNAME" -o name 2>/dev/null || true)
      if [ -z "$PV_EXISTS" ]; then
        echo "PVC $PVC_NAME references PV $PVC_VOLNAME which does not exist; deleting PVC to allow reprovision"
        DELETE_PVC=true
      fi
    fi
    if [ "$PVC_SC" != "manual" ]; then
      echo "PVC $PVC_NAME uses storageClass $PVC_SC (expected manual); deleting to allow reprovision with manual hostPath PV"
      DELETE_PVC=true
    fi
    if [ "$DELETE_PVC" = true ]; then
      kubectl --kubeconfig "$KUBECONFIG" -n default delete pvc "$PVC_NAME" --ignore-not-found || true
      sleep 2
    else
      echo "PVC $PVC_NAME is Pending but appears healthy; leaving it"
    fi
  fi
fi

# Apply PV, secret, deployment, service, ingress
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio-hostpath-pv.yaml"
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio-secret.yaml"
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio.yaml"
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio-ingress.yaml"

# Wait for pod ready
ATT=0
MAX=60
while [ $ATT -lt $MAX ]; do
  READY=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deploy minio -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  READY=${READY:-0}
  if [ "$READY" -ge 1 ]; then
    echo "minio deployment ready"
    exit 0
  fi
  ATT=$((ATT+1))
  echo "not ready yet ($ATT/$MAX)"
  sleep 2
done

kubectl --kubeconfig "$KUBECONFIG" -n default get pods,svc,ingress,pvc -o wide || true
kubectl --kubeconfig "$KUBECONFIG" -n default describe deploy minio || true
kubectl --kubeconfig "$KUBECONFIG" -n default logs -l app=minio --tail=200 || true
exit 1
