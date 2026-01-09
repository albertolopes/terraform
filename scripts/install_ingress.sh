#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}

# ensure kubectl exists
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found — downloading latest kubectl into $HOME/.local/bin/kubectl"
  KUBE_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -L "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl" -o "$HOME/.local/bin/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
  export PATH="$HOME/.local/bin:$PATH"
fi

PLATFORM=${PLATFORM:-"linux/amd64"}

# source common lib for helper functions like k3d_import_cmd, k3d_list, kubectl_apply_with_validate_fallback
if [ -f "$MODULE_DIR/scripts/lib.sh" ]; then
  # shellcheck disable=SC1091
  . "$MODULE_DIR/scripts/lib.sh"
fi

# --- ensure Traefik is not running (remove and wait) ---
remove_traefik() {
  echo "Ensuring Traefik is absent to avoid port conflicts..."
  # try helm uninstall if helm present
  if command -v helm >/dev/null 2>&1; then
    helm -n kube-system uninstall traefik --wait --timeout 30s || true
  fi

  # delete common traefik resources by label/name and wait for pods to be gone
  kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete deployment,svc,daemonset,replicaset,job -l app=traefik --ignore-not-found=true || true
  kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete deployment traefik --ignore-not-found=true || true
  kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete svc traefik --ignore-not-found=true || true

  # delete any svclb daemonsets/pods that reference traefik
  # first try to find daemonsets with 'svclb' in the name and containing traefik
  ds_to_del=$(kubectl --kubeconfig "$KUBECONFIG" -n kube-system get daemonset -o name 2>/dev/null | grep -i svclb || true)
  for ds in $ds_to_del; do
    # check if this ds has pods referencing traefik
    name=$(basename "$ds")
    if kubectl --kubeconfig "$KUBECONFIG" -n kube-system get ds "$name" -o yaml 2>/dev/null | grep -iq 'traefik\|ingress'; then
      echo "Deleting svclb daemonset $name"
      kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete daemonset "$name" --ignore-not-found=true || true
    fi
  done

  # delete any svclb pods containing traefik/traefik label
  kubectl --kubeconfig "$KUBECONFIG" -n kube-system get pods -o name 2>/dev/null | grep -i traefik || true | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete --ignore-not-found=true || true

  # wait briefly until no traefik pods or services remain
  echo "Waiting for Traefik pods/services to be removed (timeout 60s)"
  for i in $(seq 1 12); do
    sleep 5
    if ! kubectl --kubeconfig "$KUBECONFIG" -n kube-system get pods -o name 2>/dev/null | grep -iq traefik; then
      if ! kubectl --kubeconfig "$KUBECONFIG" -n kube-system get svc -o name 2>/dev/null | grep -iq traefik; then
        echo "No Traefik pods/services detected"
        return 0
      fi
    fi
    echo "Traefik still present, waiting... ($((i*5))s)"
  done
  echo "Finished waiting for Traefik removal"
}

# call removal early
remove_traefik || true

# If lib.sh did not define wait_for_kube_api, provide a robust fallback implementation
if ! declare -F wait_for_kube_api >/dev/null 2>&1; then
  wait_for_kube_api() {
    local kubeconfig=${1:-"$PWD/.k3d_kubeconfig"}
    local timeout=${2:-300}
    local step=${3:-5}
    local elapsed=0
    echo "Waiting up to ${timeout}s for kube API (kubeconfig=${kubeconfig})"
    while true; do
      # prefer GET /readyz if available
      if kubectl --kubeconfig "$kubeconfig" get --raw="/readyz" >/dev/null 2>&1; then
        echo "kube API ready"
        return 0
      fi
      if kubectl --kubeconfig "$kubeconfig" version --short >/dev/null 2>&1; then
        echo "kubectl can reach API"
        return 0
      fi
      sleep "$step"
      elapsed=$((elapsed + step))
      echo "kube API not ready yet (${elapsed}s elapsed)"
      if [ "$elapsed" -ge "$timeout" ]; then
        echo "kube API did not become ready within ${timeout}s" >&2
        return 1
      fi
    done
  }
fi

# NOTE: we intentionally do NOT perform docker login to Docker Hub here — images should be public or pre-pulled

# images and tags we need
CTRL_TAG="v1.14.1"
CERT_TAG="v1.6.5"
CTRL_NAME="ingress-nginx/controller"
CERT_NAME="ingress-nginx/kube-webhook-certgen"
TARFILE="$MODULE_DIR/.ingress-images.tar"

# Only try common public registries, do not include Docker Hub or attempt docker login
REGISTRIES=("registry.k8s.io" "k8s.gcr.io" "quay.io" "ghcr.io")
CHOSEN_CTRL=""
CHOSEN_CERT=""

try_find_image() {
  local name="$1"; shift
  local tag="$1"; shift
  local max_attempts=${1:-3} # optional third arg: max attempts per registry (default 3)
  local delay=2
  for reg in "${REGISTRIES[@]}"; do
    img="$reg/$name:$tag"
    echo "Trying to pull $img (platform=$PLATFORM)" >&2
    attempt=1
    while [ $attempt -le $max_attempts ]; do
      if docker pull --platform "$PLATFORM" "$img" >/dev/null 2>&1; then
        echo "Pulled $img" >&2
        printf '%s' "$img"
        return 0
      fi
      echo "pull failed for $img (attempt $attempt/$max_attempts), retrying in ${delay}s..." >&2
      sleep $delay
      attempt=$((attempt+1))
      delay=$((delay*2))
    done
    echo "Giving up trying registry $reg for $name:$tag after $max_attempts attempts" >&2
  done
  return 1
}

CHOSEN_CTRL_IMG=$(try_find_image "$CTRL_NAME" "$CTRL_TAG" 3 2>/dev/null || true)
CHOSEN_CTRL=$(printf '%s' "$CHOSEN_CTRL_IMG" | tr -d '\r' | xargs || true)

# try certgen with smaller number of attempts (back off quickly)
CHOSEN_CERT_IMG=$(try_find_image "$CERT_NAME" "$CERT_TAG" 2 2>/dev/null || true)
CHOSEN_CERT=$(printf '%s' "$CHOSEN_CERT_IMG" | tr -d '\r' | xargs || true)

if [ -n "$CHOSEN_CTRL" ] || [ -n "$CHOSEN_CERT" ]; then
  echo "At least one ingress image pulled; saving and importing into k3d"
  IMAGES_TO_SAVE=()
  if [ -n "$CHOSEN_CTRL" ]; then
    if docker image inspect "$CHOSEN_CTRL" >/dev/null 2>&1; then
      IMAGES_TO_SAVE+=("$CHOSEN_CTRL")
    else
      echo "Image $CHOSEN_CTRL not present locally — attempting docker pull"
      docker pull "$CHOSEN_CTRL" || true
      if docker image inspect "$CHOSEN_CTRL" >/dev/null 2>&1; then
        IMAGES_TO_SAVE+=("$CHOSEN_CTRL")
      else
        echo "Warning: $CHOSEN_CTRL still not available locally; skipping"
      fi
    fi
  fi
  if [ -n "$CHOSEN_CERT" ]; then
    if docker image inspect "$CHOSEN_CERT" >/dev/null 2>&1; then
      IMAGES_TO_SAVE+=("$CHOSEN_CERT")
    else
      echo "Image $CHOSEN_CERT not present locally — attempting docker pull"
      docker pull "$CHOSEN_CERT" || true
      if docker image inspect "$CHOSEN_CERT" >/dev/null 2>&1; then
        IMAGES_TO_SAVE+=("$CHOSEN_CERT")
      else
        echo "Warning: $CHOSEN_CERT still not available locally; skipping"
      fi
    fi
  fi

  if [ ${#IMAGES_TO_SAVE[@]} -gt 0 ]; then
    echo "Images to save: ${IMAGES_TO_SAVE[*]}"
    rm -f "$TARFILE" || true
    # try per-image k3d import first (preferred)
    if command -v k3d >/dev/null 2>&1; then
      IMPORT_SUCCEEDED=false
      for img in "${IMAGES_TO_SAVE[@]}"; do
        echo "Attempting k3d image import by name: $img"
        if k3d_import_cmd "$img" >/dev/null 2>&1; then
          echo "k3d image import succeeded for $img"
          IMPORT_SUCCEEDED=true
        else
          echo "k3d image import by name failed for $img; will try tar fallback later"
        fi
      done
      # if any image imported by name, note it
      if [ "$IMPORT_SUCCEEDED" = true ]; then
        echo "At least one image imported by name into k3d"
      fi
    fi

    # as a robust fallback, create a tar with any images not imported and import the tar
    PENDING_IMAGES=()
    for img in "${IMAGES_TO_SAVE[@]}"; do
      # check if image is present in k3d list
      if command -v k3d >/dev/null 2>&1 && k3d_list | grep -F "$img" >/dev/null 2>&1; then
        echo "Image $img already present in k3d"
        continue
      fi
      PENDING_IMAGES+=("$img")
    done

    if [ ${#PENDING_IMAGES[@]} -gt 0 ]; then
      echo "Saving pending images to tar: ${PENDING_IMAGES[*]}"
      docker save -o "$TARFILE" "${PENDING_IMAGES[@]}" || true
      if [ -f "$TARFILE" ]; then
        if command -v k3d >/dev/null 2>&1; then
          echo "Importing $TARFILE into k3d cluster '${K3D_CLUSTER_NAME:-mycluster}'"
          if k3d_import_cmd "$TARFILE" >/dev/null 2>&1; then
            echo "k3d tar import succeeded"
          else
            echo "k3d tar import failed; will try per-image tar import"
            for img in "${PENDING_IMAGES[@]}"; do
              T="${MODULE_DIR}/.tmp_image_$(echo "$img" | tr '/:' '__').tar"
              echo "Saving $img -> $T"
              docker save -o "$T" "$img" || true
              if [ -f "$T" ]; then
                echo "Importing $T into k3d"
                k3d_import_cmd "$T" || true
                rm -f "$T" || true
              fi
            done
          fi
        fi
      else
        echo "WARN: tarfile $TARFILE not created for pending images; skipping k3d import"
      fi
    else
      echo "No pending images to tar-import"
    fi
  else
    echo "No images available to save/import"
  fi
fi

INGRESS_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml"
if ! curl -fsSL "$INGRESS_URL" -o /tmp/ingress-nginx-cloud.yaml; then
  echo "Failed to download ingress-nginx manifest from $INGRESS_URL" >&2
  exit 2
fi

# Backup original manifest for debugging
cp /tmp/ingress-nginx-cloud.yaml /tmp/ingress-nginx-cloud.orig.yaml || true

# Proactively relax failurePolicy in the manifest to reduce chance of webhook blocking
if grep -q "failurePolicy:\s*Fail" /tmp/ingress-nginx-cloud.yaml >/dev/null 2>&1; then
  echo "Relaxing webhook failurePolicy in manifest (Fail -> Ignore) to prevent blocking during install" >&2
  sed -i 's/failurePolicy:\s*Fail/failurePolicy: Ignore/g' /tmp/ingress-nginx-cloud.yaml || true
fi

# If we have chosen images, replace occurrences in the manifest safely
escape_sed_repl() {
  # escape backslash, ampersand and the sed delimiter '#'
  printf '%s' "$1" | sed -e 's/[\\&\#]/\\&/g'
}

ensure_import_image() {
  # Usage: ensure_import_image <image>
  local image="$1"
  local PLATFORM_LOCAL=${PLATFORM:-"linux/amd64"}
  echo "Ensuring image available in k3d: $image" >&2

  # Delegate to robust wrapper which probes supported flags
  if command -v k3d >/dev/null 2>&1; then
    if k3d_import_cmd "$image" >/dev/null 2>&1; then
      echo "k3d import by name succeeded for $image" >&2
    else
      echo "k3d import by name failed for $image; attempting docker pull+tar import" >&2
      # try docker pull for specific platform
      if docker pull --platform "$PLATFORM_LOCAL" "$image" >/dev/null 2>&1; then
        echo "docker pull succeeded for $image" >&2
        local tarfile
        tarfile="$MODULE_DIR/.tmp_import_$(echo "$image" | tr '/:' '__').tar"
        docker save -o "$tarfile" "$image" || true
        if [ -f "$tarfile" ]; then
          if k3d_import_cmd "$tarfile" >/dev/null 2>&1; then
            echo "k3d tar import succeeded for $image" >&2
            rm -f "$tarfile" || true
          else
            echo "k3d tar import failed for $image; will attempt per-image tar fallback" >&2
          fi
        else
          echo "docker save did not produce tar for $image" >&2
        fi
      else
        echo "docker pull failed for $image (network/registry issue?)" >&2
      fi
    fi
  else
    echo "k3d not found; skipping k3d import for $image" >&2
  fi

  # Return a REF present in k3d (try exact image, full image list name, or digest)
  if command -v k3d >/dev/null 2>&1; then
    local refs
    refs=$(k3d_list 2>/dev/null || true)
    # prefer exact match
    if echo "$refs" | grep -q -F "$image"; then
      echo "$(echo "$refs" | grep -F "$image" | head -n1 | awk '{print $1}')"
      return 0
    fi
    # try by repo/name (strip registry if not present)
    local base=${image%%:*}
    local name_only=${base##*/}
    if echo "$refs" | grep -i "/$name_only" >/dev/null 2>&1; then
      echo "$(echo "$refs" | grep -i "/$name_only" | head -n1 | awk '{print $1}')"
      return 0
    fi
    # try to find any nginx controller related ref
    if echo "$refs" | grep -i 'ingress-nginx' >/dev/null 2>&1; then
      echo "$(echo "$refs" | grep -i 'ingress-nginx' | head -n1 | awk '{print $1}')"
      return 0
    fi
    # as last resort return original image
    echo "$image"
    return 0
  fi

  echo "$image"
}

# Replace earlier CHOSEN_* usage: ensure images and determine REF to use in manifest
CHOSEN_CTRL_REF=""
CHOSEN_CERT_REF=""
if [ -n "$CHOSEN_CTRL" ]; then
  echo "Ensuring controller image: $CHOSEN_CTRL"
  CHOSEN_CTRL_REF=$(ensure_import_image "$CHOSEN_CTRL" 2>/dev/null || true)
  # sanitize: extract last whitespace-delimited token (should be the image ref)
  CHOSEN_CTRL_REF=$(printf '%s' "$CHOSEN_CTRL_REF" | tr -d '\r' | awk '{print $NF}' | xargs || true)
  echo "Controller REF to use in manifest: $CHOSEN_CTRL_REF"
fi
if [ -n "$CHOSEN_CERT" ]; then
  echo "Ensuring certgen image: $CHOSEN_CERT"
  CHOSEN_CERT_REF=$(ensure_import_image "$CHOSEN_CERT" 2>/dev/null || true)
  CHOSEN_CERT_REF=$(printf '%s' "$CHOSEN_CERT_REF" | tr -d '\r' | awk '{print $NF}' | xargs || true)
  echo "Certgen REF to use in manifest: $CHOSEN_CERT_REF"
fi

# If we have chosen REF values, replace occurrences in the manifest safely
if [ -n "$CHOSEN_CTRL_REF" ]; then
  ESC_CTRL=$(escape_sed_repl "$CHOSEN_CTRL_REF")
  sed -i "s#\(registry.k8s.io\|k8s.gcr.io\|quay.io\|ghcr.io\)/$CTRL_NAME:[^[:space:]][^[:space:]]*#${ESC_CTRL}#g" /tmp/ingress-nginx-cloud.yaml || true
  sed -i "s#\(registry.k8s.io\|k8s.gcr.io\|quay.io\|ghcr.io\)/$CTRL_NAME@sha256:[^[:space:]][^[:space:]]*#${ESC_CTRL}#g" /tmp/ingress-nginx-cloud.yaml || true
fi
if [ -n "$CHOSEN_CERT_REF" ]; then
  ESC_CERT=$(escape_sed_repl "$CHOSEN_CERT_REF")
  sed -i "s#\(registry.k8s.io\|k8s.gcr.io\|quay.io\|ghcr.io\)/$CERT_NAME:[^[:space:]][^[:space:]]*#${ESC_CERT}#g" /tmp/ingress-nginx-cloud.yaml || true
  sed -i "s#\(registry.k8s.io\|k8s.gcr.io\|quay.io\|ghcr.io\)/$CERT_NAME@sha256:[^[:space:]][^[:space:]]*#${ESC_CERT}#g" /tmp/ingress-nginx-cloud.yaml || true
fi

# apply manifest
# remove previously created admission jobs if they exist to avoid immutable-field patch errors
kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx delete job ingress-nginx-admission-create ingress-nginx-admission-patch --ignore-not-found=true || true

# Wait for kube API to be responsive before attempting to apply the manifest
echo "Waiting for kube API to be ready before installing ingress..."
if declare -F wait_for_kube_api >/dev/null 2>&1; then
  if ! wait_for_kube_api "$KUBECONFIG" 300 2; then
    echo "kube API did not become ready after timeout; attempting to proceed but kubectl may fail" >&2
  fi
fi

# Use robust apply helper which retries with --validate=false on server-side validation failures
kubectl_apply_with_validate_fallback "/tmp/ingress-nginx-cloud.yaml"

# Immediately remove any existing svclb daemonsets for ingress-nginx to avoid hostPort collisions
echo "Ensuring no svclb-ingress-nginx daemonsets remain (avoid hostPort conflicts)"
kubectl --kubeconfig "$KUBECONFIG" -n kube-system get daemonset -o name 2>/dev/null | grep -E 'svclb-ingress-nginx|svclb-traefik' || true | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete --ignore-not-found=true || true
# Also delete any lingering svclb pods by name pattern
kubectl --kubeconfig "$KUBECONFIG" -n kube-system get pods -o name 2>/dev/null | grep -E 'svclb-ingress-nginx|svclb-traefik' || true | xargs -r -n1 kubectl --kubeconfig "$KUBECONFIG" -n kube-system delete --ignore-not-found=true || true

# --- IMMEDIATE PATCH: convert newly-created ingress controller Service to NodePort to avoid svclb/hostPort scheduling issues
if kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx get svc ingress-nginx-controller >/dev/null 2>&1; then
  echo "Patching ingress-nginx-controller Service to type=NodePort immediately (nodePorts: 30082,30444)"
  PATCH_JSON='{"spec":{"type":"NodePort","ports":[{"name":"http","port":80,"nodePort":30082,"protocol":"TCP","targetPort":80},{"name":"https","port":443,"nodePort":30444,"protocol":"TCP","targetPort":443}]}}'
  kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx patch svc ingress-nginx-controller --type="merge" -p "$PATCH_JSON" || true
fi

# --- wait for admission webhook endpoints (so webhook validations succeed) ---
echo "Waiting for ingress-nginx admission endpoints..."
ATTEMPTS=90
SLEEP=2
for i in $(seq 1 $ATTEMPTS); do
  EP=$(kubectl --kubeconfig "$KUBECONFIG" -n ingress-nginx get endpoints ingress-nginx-controller-admission -o jsonpath='{.subsets}' 2>/dev/null || true)
  if [ -n "$EP" ] && [ "$EP" != "[]" ]; then
    echo "admission endpoints ready"
    break
  fi
  echo "not ready ($i/$ATTEMPTS)"
  sleep $SLEEP
done

kubectl --kubeconfig "$KUBECONFIG" apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-global-ingress
  namespace: default
  annotations:
    kubernetes.io/ingress.class: "nginx"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
YAML

