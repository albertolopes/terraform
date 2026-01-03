#!/usr/bin/env bash
set -euo pipefail
MODULE_DIR=${MODULE_DIR:-$(pwd)}
KUBECONFIG=${KUBECONFIG:-$MODULE_DIR/.k3d_kubeconfig}
K3D_CLUSTER=${K3D_CLUSTER:-mycluster}

# Keycloak-specific timeout (seconds) — default 5 minutes
KEYCLOAK_TIMEOUT_SECONDS=${KEYCLOAK_TIMEOUT_SECONDS:-300}

# helper: wait for kube API to be reachable via provided KUBECONFIG
wait_for_kube() {
  local timeout=${1:-600}
  local start=$(date +%s)
  echo "Waiting up to ${timeout}s for Kubernetes API (kubeconfig=${KUBECONFIG}) to be available..."
  while true; do
    if [ -f "$KUBECONFIG" ]; then
      # Check API readiness endpoint
      if kubectl --kubeconfig "$KUBECONFIG" get --raw /readyz >/dev/null 2>&1; then
        # ensure there is at least one Ready node
        if kubectl --kubeconfig "$KUBECONFIG" get nodes --no-headers 2>/dev/null | awk '{print $2}' | grep -q "Ready"; then
          echo "Kubernetes API is reachable and nodes are Ready"
          return 0
        else
          echo "Kubernetes API reachable but no Ready nodes yet"
        fi
      else
        echo "Kubernetes API not ready yet"
      fi
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge $timeout ]; then
      echo "Timed out waiting for Kubernetes API (${KUBECONFIG})" >&2
      return 1
    fi
    sleep 5
  done
}

# Ensure image available in k3d
IMAGE=$(awk '/^services:/ {f=1} f && /^\s*keycloak:/ {g=1; next} g && /image:/ {gsub(/^[[:space:]]*image:[[:space:]]*/,"", $0); print $0; exit}' $MODULE_DIR/docker/keycloak.yaml || true)
IMAGE=${IMAGE:-quay.io/keycloak/keycloak:25.0.6}

if command -v k3d >/dev/null 2>&1; then
  echo "k3d found — ensuring image '$IMAGE' is present in cluster '$K3D_CLUSTER'"
  # Verify cluster exists
  if ! k3d cluster list --no-headers | awk '{print $1}' | grep -q "^${K3D_CLUSTER}$"; then
    echo "Error: k3d cluster '$K3D_CLUSTER' not found. Current clusters:"
    k3d cluster list || true
    echo "Skipping k3d image import. Ensure K3D_CLUSTER is set to an existing cluster." >&2
  else
    # Try direct import by tar to avoid ambiguity with cluster selection in different k3d versions
    TMP_TAR="/tmp/keycloak-image-$$.tar"
    echo "Pulling image locally: $IMAGE"
    docker pull "$IMAGE" || echo "docker pull failed; proceeding to attempt import by name"
    echo "Saving image to tar: $TMP_TAR"
    docker save "$IMAGE" -o "$TMP_TAR"
    echo "Importing tar into k3d cluster $K3D_CLUSTER"
    # Prefer explicit cluster flag; if unsupported, fall back to importing the tar without flag
    if k3d image import --cluster "$K3D_CLUSTER" "$TMP_TAR" >/dev/null 2>&1; then
      echo "Imported image tar into cluster $K3D_CLUSTER"
    else
      echo "--cluster flag unsupported or import failed; trying import without --cluster"
      if k3d image import "$TMP_TAR" >/dev/null 2>&1; then
        echo "Imported image tar (no --cluster)"
      else
        echo "Warning: k3d image import failed; the cluster may already have the image or network access will be used." >&2
      fi
    fi
    rm -f "$TMP_TAR"
  fi
fi

# Wait for kube API before applying manifests
if ! wait_for_kube 600; then
  echo "Kubernetes API not available; aborting deploy_keycloak.sh" >&2
  exit 1
fi

# Wait for Postgres deployment to be ready
wait_for_postgres() {
  local timeout=${1:-300}
  local start=$(date +%s)
  echo "Waiting up to ${timeout}s for Postgres deployment to have Ready replicas..."
  while true; do
    READY=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deploy postgres -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ -n "$READY" ] && [ "$READY" -ge 1 ]; then
      echo "Postgres deployment has Ready replicas"
      return 0
    fi
    now=$(date +%s)
    if [ $((now - start)) -ge $timeout ]; then
      echo "Timed out waiting for Postgres to be Ready" >&2
      return 1
    fi
    sleep 5
  done
}

if ! wait_for_postgres 300; then
  echo "Postgres not ready after timeout; aborting keycloak DB creation" >&2
  exit 1
fi

# Remove previous job if present to avoid 'field is immutable' issues when template changes
kubectl --kubeconfig "$KUBECONFIG" -n default delete job create-keycloak-db --ignore-not-found=true || true
kubectl --kubeconfig "$KUBECONFIG" -n default delete job create-keycloak-role --ignore-not-found=true || true

# First create role job (idempotent)
cat <<'YAML' | kubectl --kubeconfig "$KUBECONFIG" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: create-keycloak-role
  namespace: default
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: createrole
        image: postgres:15
        env:
        - name: PGPASSWORD
          value: "postgres"
        command: ["/bin/sh","-c"]
        args:
          - |
            set -e
            echo "Checking/creating role 'keycloak'..."
            if ! psql "postgresql://postgres:postgres@postgres:5432/postgres" -tAc "SELECT 1 FROM pg_roles WHERE rolname='keycloak'" | grep -q 1; then
              psql "postgresql://postgres:postgres@postgres:5432/postgres" -c "CREATE USER keycloak WITH ENCRYPTED PASSWORD 'keycloak';"
              echo "Role keycloak created"
            else
              echo "Role keycloak already exists"
            fi
YAML

# Wait for role job to complete
ROLE_JOB=create-keycloak-role
ROLE_TIMEOUT=${ROLE_TIMEOUT:-120}
START_TS=$(date +%s)
while true; do
  SUCCEEDED=$(kubectl --kubeconfig "$KUBECONFIG" -n default get job ${ROLE_JOB} -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
  FAILED=$(kubectl --kubeconfig "$KUBECONFIG" -n default get job ${ROLE_JOB} -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  if [ "$SUCCEEDED" = "1" ]; then
    echo "Role job ${ROLE_JOB} succeeded"
    break
  fi
  if [ "$FAILED" != "" ] && [ "$FAILED" -gt 0 ]; then
    echo "Role job ${ROLE_JOB} failed; dumping logs and exiting" >&2
    POD=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l job-name=${ROLE_JOB} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$POD" ]; then
      kubectl --kubeconfig "$KUBECONFIG" -n default logs "$POD" --tail=500 >&2 || true
    fi
    kubectl --kubeconfig "$KUBECONFIG" -n default delete job ${ROLE_JOB} --ignore-not-found=true || true
    exit 1
  fi
  NOW=$(date +%s)
  if [ $((NOW-START_TS)) -ge $ROLE_TIMEOUT ]; then
    echo "Role job ${ROLE_JOB} timed out after ${ROLE_TIMEOUT}s" >&2
    POD=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l job-name=${ROLE_JOB} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$POD" ]; then
      kubectl --kubeconfig "$KUBECONFIG" -n default logs "$POD" --tail=500 >&2 || true
    fi
    kubectl --kubeconfig "$KUBECONFIG" -n default delete job ${ROLE_JOB} --ignore-not-found=true || true
    exit 1
  fi
  sleep 2
done

# Now create database job (idempotent)
cat <<'YAML' | kubectl --kubeconfig "$KUBECONFIG" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: create-keycloak-db
  namespace: default
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: createdb
        image: postgres:15
        env:
        - name: PGPASSWORD
          value: "postgres"
        command: ["/bin/sh","-c"]
        args:
          - |
            set -e
            echo "Checking/creating database 'keycloak'..."
            if ! psql "postgresql://postgres:postgres@postgres:5432/postgres" -tAc "SELECT 1 FROM pg_database WHERE datname='keycloak'" | grep -q 1; then
              psql "postgresql://postgres:postgres@postgres:5432/postgres" -c "CREATE DATABASE keycloak OWNER keycloak;"
            else
              echo "Database keycloak already exists"
            fi
            echo "Setting schema ownership and grants"
            psql "postgresql://postgres:postgres@postgres:5432/keycloak" -c "ALTER SCHEMA public OWNER TO keycloak;" || true
            psql "postgresql://postgres:postgres@postgres:5432/keycloak" -c "GRANT ALL ON SCHEMA public TO keycloak;" || true
YAML

# Wait for job completion with improved handling
JOB_NAME=create-keycloak-db
JOB_TIMEOUT_SECONDS=${JOB_TIMEOUT_SECONDS:-300}
START_TS=$(date +%s)

echo "Waiting up to ${JOB_TIMEOUT_SECONDS}s for Job ${JOB_NAME} to complete..."
while true; do
  # Check status
  SUCCEEDED=$(kubectl --kubeconfig "$KUBECONFIG" -n default get job ${JOB_NAME} -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
  FAILED=$(kubectl --kubeconfig "$KUBECONFIG" -n default get job ${JOB_NAME} -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")
  if [ "$SUCCEEDED" = "1" ]; then
    echo "Job ${JOB_NAME} succeeded"
    break
  fi
  if [ "$FAILED" != "" ] && [ "$FAILED" -gt 0 ]; then
    echo "Job ${JOB_NAME} failed (failed=${FAILED}). Dumping pod logs for debugging..." >&2
    POD=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$POD" ]; then
      echo "=== Logs from $POD ===" >&2
      kubectl --kubeconfig "$KUBECONFIG" -n default logs "$POD" --tail=500 >&2 || true
    fi
    echo "Removing failed job ${JOB_NAME} and exiting with error" >&2
    kubectl --kubeconfig "$KUBECONFIG" -n default delete job ${JOB_NAME} --ignore-not-found=true || true
    exit 1
  fi
  NOW=$(date +%s)
  ELAPSED=$((NOW-START_TS))
  if [ "$ELAPSED" -ge "$JOB_TIMEOUT_SECONDS" ]; then
    echo "Job ${JOB_NAME} did not complete within ${JOB_TIMEOUT_SECONDS}s. Gathering pod logs and continuing (job will be deleted)." >&2
    POD=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l job-name=${JOB_NAME} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$POD" ]; then
      echo "=== Logs from $POD ===" >&2
      kubectl --kubeconfig "$KUBECONFIG" -n default logs "$POD" --tail=500 >&2 || true
    else
      echo "No pod found for job ${JOB_NAME}" >&2
    fi
    kubectl --kubeconfig "$KUBECONFIG" -n default delete job ${JOB_NAME} --ignore-not-found=true || true
    break
  fi
  sleep 5
done

# Apply keycloak manifests
kubectl --kubeconfig "$KUBECONFIG" apply -f $MODULE_DIR/k8s/keycloak/keycloak-realm-configmap.yaml || true
kubectl --kubeconfig "$KUBECONFIG" apply -f $MODULE_DIR/k8s/keycloak/keycloak-deployment.yaml || true
kubectl --kubeconfig "$KUBECONFIG" apply -f $MODULE_DIR/k8s/ingress/keycloak-ingress.yaml || true

# Wait for deployment
kubectl --kubeconfig "$KUBECONFIG" -n default rollout status deployment/keycloak --timeout=600s || true

# Basic readiness
for i in $(seq 1 120); do
  READY=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deploy keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if [ "$READY" = "1" ]; then
    echo "keycloak ready"
    exit 0
  fi
  sleep 5
done

echo "keycloak did not become ready within timeout" >&2
exit 1

