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

# Apply PV (dynamically using repo-relative volume directory if present), then secret, deployment, service, ingress
HOST_VOL_DIR="$MODULE_DIR/volume/minio"
if [ -d "$HOST_VOL_DIR" ]; then
  echo "Creating PV using hostPath: $HOST_VOL_DIR"
  cat <<PVYAML | kubectl --kubeconfig "$KUBECONFIG" apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-minio-hostpath
  labels:
    app: minio
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: "${HOST_VOL_DIR}"
    type: DirectoryOrCreate
PVYAML
else
  # fallback to existing k8s file if present
  if [ -f "$MODULE_DIR/k8s/minio/minio-hostpath-pv.yaml" ]; then
    kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio/minio-hostpath-pv.yaml" || true
  else
    echo "Warning: hostPath directory $HOST_VOL_DIR not found and no k8s/minio/minio-hostpath-pv.yaml present; continuing without hostPath PV" >&2
  fi
fi
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio/minio-secret.yaml"
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio/minio.yaml"
kubectl --kubeconfig "$KUBECONFIG" apply -f "$MODULE_DIR/k8s/minio/minio-ingress.yaml"

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
