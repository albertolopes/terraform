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

# Use env vars from Terraform when provided
USE_LOCAL_PATH=${USE_LOCAL_PATH:-"false"}
POSTGRES_HOST_PATH=${POSTGRES_HOST_PATH:-""}

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

# source common lib
if [ -f ./scripts/lib.sh ]; then
  # shellcheck disable=SC1091
  . ./scripts/lib.sh
  # ensure kubeconfig endpoints point at localhost instead of 0.0.0.0
  # only call fix_kubeconfig_paths if kubeconfig file exists (avoid sed rename errors)
  wait_for_kubeconfig_file() {
    local cfg_file="$MODULE_DIR/.k3d_kubeconfig"
    local tries=0
    local max=30
    while [ $tries -lt $max ]; do
      if [ -f "$cfg_file" ]; then
        return 0
      fi
      tries=$((tries+1))
      sleep 1
    done
    return 1
  }
  if wait_for_kubeconfig_file; then
    if declare -F fix_kubeconfig_paths >/dev/null 2>&1; then
      fix_kubeconfig_paths || true
    fi
  else
    echo "Warning: kubeconfig $MODULE_DIR/.k3d_kubeconfig not found after waiting; continuing but kubectl calls may fail" >&2
  fi
fi

# graceful shutdown on interrupt so Terraform local-exec exits cleanly
_graceful_exit() {
  echo "Received interrupt; exiting deploy_postgres.sh" >&2
  exit 130
}
trap _graceful_exit INT TERM

# ensure using the per-cluster kubeconfig file
export KUBECONFIG=${KUBECONFIG:-$MODULE_DIR/.k3d_kubeconfig}

# wait for kube API to be available before applying manifests
if declare -F wait_for_kube_api >/dev/null 2>&1; then
  wait_for_kube_api "$KUBECONFIG" 60 2 || true
fi

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
  if k3d_import_cmd "$IMAGE"; then
    echo "k3d import by name succeeded for $IMAGE"
  else
    TAR="$MODULE_DIR/.postgres_image.tar"
    docker save -o "$TAR" "$IMAGE" || true
    if [ -f "$TAR" ]; then
      k3d_import_cmd "$TAR" >/dev/null 2>&1 || true
      rm -f "$TAR" || true
    fi
  fi
fi

# Determine deploy image ref (prefer imported REF if any)
DEPLOY_IMAGE="$IMAGE"
if command -v k3d >/dev/null 2>&1; then
  REFS=$(k3d_list 2>/dev/null || true)
  if echo "$REFS" | grep -q -F "$IMAGE"; then
    DEPLOY_IMAGE=$(echo "$REFS" | grep -F "$IMAGE" | head -n1 | awk '{print $1}')
  fi
fi

echo "Using image for deployment: $DEPLOY_IMAGE"

HOST_PATH=""
if [ -f "$MODULE_DIR/docker/postgres.yaml" ]; then
  # Simpler and robust: look for a volume line that contains an absolute host path (starts with '/')
  HOST_PATH=$(grep -Po '^[[:space:]]*-\s*"(\/[^"]+' "$MODULE_DIR/docker/postgres.yaml" 2>/dev/null | sed -E 's/^[[:space:]]*-\s*"//' | head -n1 || true)
  # fallback: unquoted path (no double quotes)
  if [ -z "$HOST_PATH" ]; then
    HOST_PATH=$(grep -Po '^[[:space:]]*\-\s*(\/[^:]+):' "$MODULE_DIR/docker/postgres.yaml" 2>/dev/null | sed -E 's/^[[:space:]]*\-\s*//' | sed -E 's/:$//' | head -n1 || true)
  fi
fi

# If repo-relative volume directory exists, prefer it (so we always look at volume/postgres)
if [ -z "$POSTGRES_HOST_PATH" ] && [ -d "$MODULE_DIR/volume/postgres" ]; then
  POSTGRES_HOST_PATH="$MODULE_DIR/volume/postgres"
fi

# Allow deploy to be controlled by USE_LOCAL_PATH: when true, don't create hostPath PV, use storageClass provisioning
if [ "$USE_LOCAL_PATH" = "true" ] || [ "$USE_LOCAL_PATH" = "True" ] || [ "$USE_LOCAL_PATH" = "1" ]; then
  echo "Using storageClass provisioning (local-path) for postgres PVC"
  HOST_PATH=""
else
  # prefer POSTGRES_HOST_PATH env var (absolute) or docker-compose path detection
  HOST_PATH="$POSTGRES_HOST_PATH"
  if [ -z "$HOST_PATH" ] && [ -f "$MODULE_DIR/docker/postgres.yaml" ]; then
    HOST_PATH=$(grep -Po '^[[:space:]]*-[[:space:]]*"?(/[^":]+)' "$MODULE_DIR/docker/postgres.yaml" 2>/dev/null | sed -E 's/^[[:space:]]*-[[:space:]]*"?//' | head -n1 || true)
  fi
  # fallback to repo volume folder
  if [ -z "$HOST_PATH" ] && [ -d "$MODULE_DIR/volume/postgres-data" ]; then
    HOST_PATH="$MODULE_DIR/volume/postgres-data"
  fi
fi

# If the PVC already exists and is Bound, don't attempt to change it (PVC spec is immutable)
PVC_STATUS=$(kubectl --kubeconfig "$KUBECONFIG" get pvc "$PVC_NAME" -n default -o jsonpath='{.status.phase}' 2>/dev/null || true)
PVC_BOUND=false
if [ "$PVC_STATUS" = "Bound" ]; then
  PVC_BOUND=true
  echo "PVC $PVC_NAME already exists and is Bound; checking underlying PV"
  # get associated PV name
  PV_NAME_FROM_PVC=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pvc "$PVC_NAME" -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
  if [ -n "$PV_NAME_FROM_PVC" ]; then
    PV_HOSTPATH=$(kubectl --kubeconfig "$KUBECONFIG" get pv "$PV_NAME_FROM_PVC" -o jsonpath='{.spec.hostPath.path}' 2>/dev/null || true)
    # If PV hostPath exists and is outside our repo volume dir, remove PV+PVC to recreate pointing to repo/volume
    if [ -n "$PV_HOSTPATH" ]; then
      case "$PV_HOSTPATH" in
        "$MODULE_DIR/volume/postgres" )
          echo "PV $PV_NAME_FROM_PVC hostPath $PV_HOSTPATH points to repo mountpoint (volume/postgres) — will delete PV/PVC so we can recreate into a 'data' subdir"
          kubectl --kubeconfig "$KUBECONFIG" -n default delete pvc "$PVC_NAME" --ignore-not-found=true || true
          kubectl --kubeconfig "$KUBECONFIG" delete pv "$PV_NAME_FROM_PVC" --ignore-not-found=true || true
          PVC_BOUND=false
          ;;
        "$MODULE_DIR/volume"*|"$MODULE_DIR/volume/postgres"* )
          echo "PV $PV_NAME_FROM_PVC hostPath $PV_HOSTPATH is inside repo volume — keeping PVC/PV"
          ;;
        *)
          echo "PV $PV_NAME_FROM_PVC hostPath $PV_HOSTPATH is outside repo volume; deleting PVC and PV to allow reprovision into repo/volume/postgres"
          kubectl --kubeconfig "$KUBECONFIG" -n default delete pvc "$PVC_NAME" --ignore-not-found=true || true
          kubectl --kubeconfig "$KUBECONFIG" delete pv "$PV_NAME_FROM_PVC" --ignore-not-found=true || true
          PVC_BOUND=false
          ;;
      esac
    else
      echo "PV name from PVC ($PV_NAME_FROM_PVC) has no hostPath (maybe dynamic); keeping PVC"
    fi
  else
    echo "PVC $PVC_NAME is Bound but no PV found in spec.volumeName; keeping PVC"
  fi
fi

# Skip PV/PVC creation if PVC is already Bound
if [ "$PVC_BOUND" = "false" ]; then
  if [ "$USE_LOCAL_PATH" = "true" ] || [ "$USE_LOCAL_PATH" = "True" ] || [ "$USE_LOCAL_PATH" = "1" ]; then
    # Create PVC using the storage class (local-path)
    TMPPVC=$(mktemp -p "$MODULE_DIR" pvc-postgres-XXXXX.yaml)
    cat > "$TMPPVC" <<PVCYAML
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
    kubectl_apply_with_validate_fallback "$TMPPVC" || true
    rm -f "$TMPPVC" || true

    # Immediately create deployment so WaitForFirstConsumer triggers binding
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

  else
    # Non-local-path (hostPath) flow
    if [ -n "$HOST_PATH" ]; then
      if command -v readlink >/dev/null 2>&1; then
        HOST_VOL_DIR=$(readlink -f "$HOST_PATH")
      elif command -v realpath >/dev/null 2>&1; then
        HOST_VOL_DIR=$(realpath "$HOST_PATH")
      else
        HOST_VOL_DIR="$HOST_PATH"
      fi
    else
      # fallback to repo volume folder
      # use a dedicated 'data' subdir inside the repo volume to avoid using mountpoint directly
      HOST_VOL_DIR="$MODULE_DIR/volume/postgres/data/pgdata"
    fi

    PV_NAME="pv-postgres-hostpath"

    # Ensure host dir exists
    mkdir -p "$HOST_VOL_DIR" || true

    # Ensure the path exists inside each k3d node container (so kubelet can mount it without host sudo)
    # Determine cluster name and node container names
    CLUSTER_NAME="${K3D_CLUSTER_NAME:-mycluster}"
    NODE_CONTAINERS=$(docker ps --format '{{.Names}}' | grep -E "^k3d-${CLUSTER_NAME}-" || true)
    if [ -n "$NODE_CONTAINERS" ]; then
      echo "Ensuring host path exists inside k3d node containers: $HOST_VOL_DIR"
      for nc in $NODE_CONTAINERS; do
        # best-effort, do not fail the script if docker exec fails
        docker exec "$nc" bash -lc "mkdir -p '${HOST_VOL_DIR}' || true; chown -R 999:999 '${HOST_VOL_DIR}' || true; chmod -R 700 '${HOST_VOL_DIR}' || true" || true
      done
    else
      echo "No k3d node containers detected (expected names like k3d-${CLUSTER_NAME}-server-0). Continuing; kubelet will attempt to create hostPath on host." >&2
    fi

    # Try to clean existing contents; if permission denied or dir not empty afterwards, create a new subdir
    CLEAN_OK=true
    if [ "$(ls -A "$HOST_VOL_DIR" 2>/dev/null || true)" != "" ]; then
      echo "Host dir $HOST_VOL_DIR exists and is not empty — attempting to clean contents"
      if rm -rf "${HOST_VOL_DIR:?}/"* 2>/dev/null; then
        echo "Cleaned $HOST_VOL_DIR"
      else
        echo "Could not clean $HOST_VOL_DIR (permission denied?) — will create a new timestamped subdir for PG data"
        CLEAN_OK=false
      fi
    fi

    if [ "$CLEAN_OK" = "false" ]; then
      # create a new unique subdir under the repo volume and use its 'data' subdir
      BASE_DIR="$MODULE_DIR/volume/postgres/pgdata-$(date +%s)"
      HOST_VOL_DIR="$BASE_DIR/data/pgdata"
      mkdir -p "$HOST_VOL_DIR" || true
      echo "Using new host dir $HOST_VOL_DIR for postgres data"
      # ensure created inside node containers as well
      if [ -n "$NODE_CONTAINERS" ]; then
        for nc in $NODE_CONTAINERS; do
          docker exec "$nc" bash -lc "mkdir -p '${HOST_VOL_DIR}' || true; chown -R 999:999 '${HOST_VOL_DIR}' || true; chmod -R 700 '${HOST_VOL_DIR}' || true" || true
        done
      fi
    fi

    # Ensure ownership is postgres UID:GID (999:999)
    chown -R 999:999 "$HOST_VOL_DIR" 2>/dev/null || true

    echo "Creating PV using hostPath: $HOST_VOL_DIR"
    TMPPV=$(mktemp -p "$MODULE_DIR" pv-postgres-XXXXX.yaml)
    cat > "$TMPPV" <<PVYAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
  labels:
    app: postgres
spec:
  capacity:
    storage: ${STORAGE_SIZE}
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: "${HOST_VOL_DIR}"
    type: DirectoryOrCreate
PVYAML
    kubectl_apply_with_validate_fallback "$TMPPV" || true
    rm -f "$TMPPV" || true

    TMPPVC=$(mktemp -p "$MODULE_DIR" pvc-postgres-XXXXX.yaml)
    cat > "$TMPPVC" <<PVCYAML
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
    kubectl_apply_with_validate_fallback "$TMPPVC" || true
    rm -f "$TMPPVC" || true
  fi
fi

# WAIT for PVC to be bound before creating deployment
echo "Waiting for PVC ${PVC_NAME} to be Bound (timeout 300s)"
wait_for_pvc_bound() {
  local kubeconfig=${KUBECONFIG}
  local ns=${1:-default}
  local pvc=${2:-$PVC_NAME}
  local timeout=${3:-300}
  local interval=2
  local elapsed=0
  while [ $elapsed -lt $timeout ]; do
    status=$(kubectl --kubeconfig "$kubeconfig" -n "$ns" get pvc "$pvc" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$status" = "Bound" ]; then
      return 0
    fi
    sleep $interval
    elapsed=$((elapsed+interval))
  done
  return 1
}

if ! wait_for_pvc_bound default ${PVC_NAME} 300; then
  echo "PVC ${PVC_NAME} did not become Bound within timeout" >&2
  kubectl --kubeconfig "$KUBECONFIG" -n default get pvc ${PVC_NAME} -o yaml || true
  kubectl --kubeconfig "$KUBECONFIG" -n default get pv ${PV_NAME:-pv-postgres-hostpath} -o yaml || true
  exit 1
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
echo "Waiting for postgres pod to be ready (timeout 300s)"
ATT=0
MAX=150
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
