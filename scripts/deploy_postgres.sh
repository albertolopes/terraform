#!/usr/bin/env bash
set -euo pipefail

# deploy_postgres.sh
# Deploys Postgres to the k3d cluster using a PVC (local-path) and exposes it via NodePort 30532.

KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}
IMAGE=${POSTGRES_IMAGE:-"postgres:15"}
PLATFORM=${PLATFORM:-"linux/amd64"}

POSTGRES_USER=${POSTGRES_USER:-postgres}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-postgres}
POSTGRES_DB=${POSTGRES_DB:-na-palma}

NODE_PORT=${POSTGRES_NODE_PORT:-30532}
PVC_NAME=${POSTGRES_PVC_NAME:-postgres-pvc}
STORAGE_CLASS=${POSTGRES_STORAGE_CLASS:-local-path}
STORAGE_SIZE=${POSTGRES_STORAGE_SIZE:-1Gi}

# ensure kubectl exists
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found — downloading latest kubectl into $HOME/.local/bin/kubectl"
  KUBE_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -L "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl" -o "$HOME/.local/bin/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
  export PATH="$HOME/.local/bin:$PATH"
fi

k3d_import() {
  src="$1"
  if ! command -v k3d >/dev/null 2>&1; then
    echo "k3d not found; cannot import $src" >&2
    return 2
  fi
  if k3d image import -c mycluster "$src" >/dev/null 2>&1; then
    return 0
  fi
  if k3d image import --cluster mycluster "$src" >/dev/null 2>&1; then
    return 0
  fi
  if k3d image import "$src" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# If a docker/docker.yaml exists, prefer the postgres image defined there
if [ -f "$MODULE_DIR/docker/postgres.yaml" ]; then
  YAML_IMAGE=$(awk '/^[[:space:]]*postgres:\s*$/ { inp=1; next } inp && /image:/ { gsub(/^[[:space:]]*image:[[:space:]]*/,"",$0); print $0; exit }' "$MODULE_DIR/docker/postgres.yaml" | tr -d '"' | tr -d "'" || true)
  if [ -n "$YAML_IMAGE" ]; then
    echo "Detected postgres image in docker/docker.yaml: $YAML_IMAGE"
    IMAGE="$YAML_IMAGE"
  fi
fi

# Pull image locally and import into k3d so pods don't need to pull from the registry
echo "Ensuring postgres image $IMAGE locally and imported into k3d"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker pull --platform "$PLATFORM" "$IMAGE" || true
fi
# Try k3d import by name, fallback to docker save + k3d import
if command -v k3d >/dev/null 2>&1; then
  if k3d_import "$IMAGE"; then
    echo "k3d import by name succeeded for $IMAGE"
  else
    TAR="$MODULE_DIR/.postgres_image.tar"
    docker save -o "$TAR" "$IMAGE" || true
    if [ -f "$TAR" ]; then
      k3d image import -c mycluster "$TAR" >/dev/null 2>&1 || true
      rm -f "$TAR" || true
    fi
  fi
fi

# Determine deploy image ref (prefer imported REF if any)
DEPLOY_IMAGE="$IMAGE"
if command -v k3d >/dev/null 2>&1; then
  REFS=$(k3d image list -c mycluster 2>/dev/null || true)
  if echo "$REFS" | grep -q -F "$IMAGE"; then
    DEPLOY_IMAGE=$(echo "$REFS" | grep -F "$IMAGE" | head -n1 | awk '{print $1}')
  fi
fi

echo "Using image for deployment: $DEPLOY_IMAGE"

HOST_PATH=""
if [ -f "$MODULE_DIR/docker/postgres.yaml" ]; then
  # Simpler and robust: look for a volume line that contains an absolute host path (starts with '/')
  HOST_PATH=$(grep -Po '^[[:space:]]*-\s*"(\/[^\"]+)' "$MODULE_DIR/docker/postgres.yaml" 2>/dev/null | sed -E 's/^[[:space:]]*-\s*"//' | head -n1 || true)
  # fallback: unquoted path (no double quotes)
  if [ -z "$HOST_PATH" ]; then
    HOST_PATH=$(grep -Po '^[[:space:]]*-\s*(\/[^:]+):' "$MODULE_DIR/docker/postgres.yaml" 2>/dev/null | sed -E 's/^[[:space:]]*-\s*//' | sed -E 's/:$//' | head -n1 || true)
  fi
fi

# If the PVC already exists and is Bound, don't attempt to change it (PVC spec is immutable)
PVC_STATUS=$(kubectl --kubeconfig "$KUBECONFIG" get pvc "$PVC_NAME" -n default -o jsonpath='{.status.phase}' 2>/dev/null || true)
PVC_BOUND=false
if [ "$PVC_STATUS" = "Bound" ]; then
  PVC_BOUND=true
  echo "PVC $PVC_NAME already exists and is Bound; skipping PV/PVC creation and not modifying PVC spec"
fi

# Skip PV/PVC creation if PVC is already Bound
if [ "$PVC_BOUND" = "false" ]; then
  # If HOST_PATH was detected, create a PV for it and set volumeName in PVC
  PV_NAME=""
  if [ -n "$HOST_PATH" ]; then
    # normalize path
    HOST_PATH_UNESCAPED="$HOST_PATH"
    PV_NAME="pv-postgres-$(echo "$HOST_PATH_UNESCAPED" | md5sum | cut -d' ' -f1)"
    echo "Detected hostPath for postgres data: $HOST_PATH_UNESCAPED -> PV_NAME=$PV_NAME"
    # create PV (idempotent)
    cat <<PVYAML | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
spec:
  capacity:
    storage: ${STORAGE_SIZE}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: "${HOST_PATH_UNESCAPED}"
    type: DirectoryOrCreate
PVYAML
    # create PVC with volumeName to bind to this PV
    cat <<PVCYAML | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
  storageClassName: manual
  volumeName: ${PV_NAME}
PVCYAML
  else
    # default behavior: create PVC that uses storage class (e.g., local-path)
    cat <<PVCYAML | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${STORAGE_CLASS}
  resources:
    requests:
      storage: ${STORAGE_SIZE}
PVCYAML
  fi
fi

# Ensure PVC health: if PVC exists but is Pending and references a missing PV or wrong storageClass, delete it so local-path can re-provision.
EXISTING_PVC_JSON=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pvc "$PVC_NAME" -o json 2>/dev/null || true)
if [ -n "$EXISTING_PVC_JSON" ]; then
  PVC_PHASE=$(echo "$EXISTING_PVC_JSON" | jq -r '.status.phase')
  PVC_SC=$(echo "$EXISTING_PVC_JSON" | jq -r '.spec.storageClassName // ""')
  PVC_VOLNAME=$(echo "$EXISTING_PVC_JSON" | jq -r '.spec.volumeName // ""')
  # If PVC is Pending and volumeName is set but PV doesn't exist OR storageClass != local-path, delete PVC to allow reprovision
  if [ "$PVC_PHASE" != "Bound" ]; then
    DELETE_PVC=false
    if [ -n "$PVC_VOLNAME" ]; then
      PV_EXISTS=$(kubectl --kubeconfig "$KUBECONFIG" get pv "$PVC_VOLNAME" -o name 2>/dev/null || true)
      if [ -z "$PV_EXISTS" ]; then
        echo "PVC $PVC_NAME references PV $PVC_VOLNAME which does not exist; deleting PVC to allow reprovision"
        DELETE_PVC=true
      fi
    fi
    if [ "$PVC_SC" != "local-path" ]; then
      echo "PVC $PVC_NAME uses storageClass $PVC_SC (not local-path); deleting to allow reprovision with local-path"
      DELETE_PVC=true
    fi
    if [ "$DELETE_PVC" = true ]; then
      kubectl --kubeconfig "$KUBECONFIG" -n default delete pvc "$PVC_NAME" --ignore-not-found || true
      # Wait briefly for deletion to propagate
      sleep 2
    else
      echo "PVC $PVC_NAME is Pending but appears healthy; leaving it for now"
    fi
  fi
fi

# Now apply Deployment and Service (uses PVC by name)
cat <<YAML | kubectl --kubeconfig "$KUBECONFIG" apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: ${DEPLOY_IMAGE}
        env:
        - name: POSTGRES_USER
          value: "${POSTGRES_USER}"
        - name: POSTGRES_PASSWORD
          value: "${POSTGRES_PASSWORD}"
        - name: POSTGRES_DB
          value: "${POSTGRES_DB}"
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: postgres-data
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres
spec:
  selector:
    app: postgres
  type: LoadBalancer
  ports:
  - name: postgresql
    port: 5432
    targetPort: 5432
YAML

# Wait for pod ready
echo "Waiting for postgres pod to be ready (timeout 120s)"
ATT=0
MAX=60
while [ $ATT -lt $MAX ]; do
  READY=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deploy postgres -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  READY=${READY:-0}
  if [ "$READY" -ge 1 ]; then
    echo "postgres deployment ready"
    exit 0
  fi
  ATT=$((ATT+1))
  echo "not ready yet ($ATT/$MAX)"
  sleep 2
done

# timed out - dump diagnostics
kubectl --kubeconfig "$KUBECONFIG" -n default get pods -o wide || true
kubectl --kubeconfig "$KUBECONFIG" -n default describe deploy postgres || true
kubectl --kubeconfig "$KUBECONFIG" -n default logs -l app=postgres --tail=200 || true

exit 1
