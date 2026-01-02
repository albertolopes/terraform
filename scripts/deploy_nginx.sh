#!/usr/bin/env bash
set -euo pipefail
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}
MODULE_DIR=${MODULE_DIR:-$PWD}
IMAGE=${NGINX_IMAGE:-"nginx:1.29.4-alpine"}
PLATFORM=${PLATFORM:-"linux/amd64"}

# ensure kubectl exists
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found — downloading latest kubectl into $HOME/.local/bin/kubectl"
  KUBE_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  curl -L "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/amd64/kubectl" -o "$HOME/.local/bin/kubectl"
  chmod +x "$HOME/.local/bin/kubectl"
  export PATH="$HOME/.local/bin:$PATH"
fi

login_if_creds() {
  if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_PASSWORD:-}" ]; then
    echo "Logging into Docker Hub as $DOCKERHUB_USERNAME"
    echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin >/dev/null 2>&1 || {
      echo "Warning: docker login failed" >&2
      return 1
    }
    return 0
  fi
  return 2
}

# Try to pull image locally for the specific platform so cluster doesn't need to reach the registry
echo "Pulling image $IMAGE locally for platform $PLATFORM (retries)"
RETRIES=5
i=0
until docker pull --platform "$PLATFORM" "$IMAGE" >/dev/null 2>&1; do
  i=$((i+1))
  # On first failure, attempt login if creds provided
  if [ $i -eq 1 ]; then
    login_if_creds || true
  fi
  if [ $i -ge $RETRIES ]; then
    echo "Warning: docker pull $IMAGE failed after $RETRIES attempts; continuing and letting cluster try to pull" >&2
    break
  fi
  echo "retrying pull ($i/$RETRIES)..."
  sleep 3
done

# Determine a full image ref for saving/importing (docker.io/library/<name>:<tag>)
# If IMAGE already contains a registry (has a dot in first path segment or contains '/'), use as-is
IFS=':' read -r BASE TAG <<< "$IMAGE"
if echo "$BASE" | grep -q '/'; then
  # has a slash: could be 'repo/name' or 'registry/repo/name'
  # if first segment contains a dot or colon it's a registry
  FIRST_SEG=$(echo "$BASE" | cut -d'/' -f1)
  if echo "$FIRST_SEG" | grep -Eq '\.|:'; then
    FULL_IMAGE="$IMAGE"
  else
    # repo/name -> docker.io/library/name
    NAME=$(echo "$BASE" | awk -F'/' '{print $NF}')
    FULL_IMAGE="docker.io/library/${NAME}:${TAG:-latest}"
  fi
else
  # name only -> docker.io/library/name:tag
  NAME="$BASE"
  FULL_IMAGE="docker.io/library/${NAME}:${TAG:-latest}"
fi

# If the pulled image exists under an explicit repo name, also tag it so docker save contains the FULL_IMAGE
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Tagging local image $IMAGE as $FULL_IMAGE"
  docker tag "$IMAGE" "$FULL_IMAGE" || true
fi

# If pulled, save and import into k3d so nodes already have it
DEPLOY_IMAGE="$IMAGE"
if docker image inspect "$FULL_IMAGE" >/dev/null 2>&1; then
  TARFILE="$MODULE_DIR/.nginx_image.tar"
  echo "Saving $FULL_IMAGE to $TARFILE"
  docker save -o "$TARFILE" "$FULL_IMAGE" || true
  if command -v k3d >/dev/null 2>&1; then
    echo "Trying k3d image import by image name first: $IMAGE"
    if k3d image import -c mycluster "$IMAGE" >/dev/null 2>&1; then
      echo "k3d image import by name succeeded for $IMAGE"
      # prefer the FULL_IMAGE reference if present on the node
      DEPLOY_IMAGE="$FULL_IMAGE"
    else
      echo "k3d image import by name failed; falling back to tar import"
      echo "Importing $TARFILE into k3d cluster 'mycluster'"
      if k3d image import -c mycluster "$TARFILE" >/dev/null 2>&1; then
        echo "tar import succeeded"
        DEPLOY_IMAGE="$FULL_IMAGE"
      else
        echo "tar import failed (continuing)" || true
      fi
    fi

    # Prefer to get a matching REF from k3d directly (more portable than docker exec ctr)
    if command -v k3d >/dev/null 2>&1; then
      echo "Querying k3d image list for matching refs..."
      K3D_REFS=$(k3d image list -c mycluster 2>/dev/null || true)
      echo "$K3D_REFS" | sed -n '1,200p'
      # Try exact IMAGE first
      if echo "$K3D_REFS" | grep -q -F "$IMAGE"; then
        DEPLOY_IMAGE=$(echo "$K3D_REFS" | grep -F "$IMAGE" | head -n1 | awk '{print $1}')
        echo "Found exact image in k3d image list: $DEPLOY_IMAGE"
      elif echo "$K3D_REFS" | grep -q -F "$FULL_IMAGE"; then
        DEPLOY_IMAGE=$(echo "$K3D_REFS" | grep -F "$FULL_IMAGE" | head -n1 | awk '{print $1}')
        echo "Found full image in k3d image list: $DEPLOY_IMAGE"
      else
        # fallback: pick any image line that mentions '/nginx'
        if echo "$K3D_REFS" | grep -i '/nginx' >/dev/null 2>&1; then
          DEPLOY_IMAGE=$(echo "$K3D_REFS" | grep -i '/nginx' | head -n1 | awk '{print $1}')
          echo "Using related nginx image from k3d list: $DEPLOY_IMAGE"
        fi
      fi
    fi

    # quick verification inside node(s)
    echo "Verifying image present in k3d node(s)..."
    NODE_FOUND_REF=""
    for node in $(docker ps --format '{{.Names}}' | grep k3d-mycluster-server || true); do
      echo "Checking node $node"
      # list REF column from ctr (first column)
      CTR_REFS=$(docker exec "$node" ctr -n k8s.io images ls 2>/dev/null | awk '{print $1}' || true)
      echo "$CTR_REFS" | sed -n '1,50p'
      # try to find exact match for FULL_IMAGE
      if echo "$CTR_REFS" | grep -q "$(echo $FULL_IMAGE | sed 's#/#\\/#g')"; then
        NODE_FOUND_REF=$(echo "$CTR_REFS" | grep "$(echo $FULL_IMAGE | sed 's#/#\\/#g')" | head -n1)
        echo "Found FULL_IMAGE on node $node: $NODE_FOUND_REF"
        break
      fi
      # try to find IMAGE tag match
      if echo "$CTR_REFS" | grep -q "$(echo $IMAGE | sed 's#/#\\/#g')"; then
        NODE_FOUND_REF=$(echo "$CTR_REFS" | grep "$(echo $IMAGE | sed 's#/#\\/#g')" | head -n1)
        echo "Found IMAGE tag on node $node: $NODE_FOUND_REF"
        break
      fi
      # otherwise, try to find any 'nginx' repo entry and prefer a digest (@sha256:...)
      if echo "$CTR_REFS" | grep -i '/nginx' >/dev/null 2>&1; then
        NODE_FOUND_REF=$(echo "$CTR_REFS" | grep -i '/nginx' | head -n1)
        echo "Found related nginx REF on node $node: $NODE_FOUND_REF"
        break
      fi
    done

    if [ -n "$NODE_FOUND_REF" ]; then
      echo "Using node REF for deployment: $NODE_FOUND_REF"
      DEPLOY_IMAGE="$NODE_FOUND_REF"
    else
      echo "No matching REF found on k3d nodes; will request original image ($IMAGE)"
    fi
  else
    echo "Note: image $FULL_IMAGE not found locally; cluster will attempt to pull it when scheduling pods"
  fi
else
  echo "Note: image $FULL_IMAGE not found locally; cluster will attempt to pull it when scheduling pods"
fi

# If there's a local ./nginx directory, create ConfigMaps from parts if they exist
# If not present, create a minimal fallback config in a temp dir so the deployment can start.
FALLBACK_NGINX_DIR=""
if [ ! -d "$MODULE_DIR/nginx" ]; then
  echo "No ./nginx folder found; creating temporary minimal nginx config for deployment"
  FALLBACK_NGINX_DIR="$MODULE_DIR/.nginx_auto"
  mkdir -p "$FALLBACK_NGINX_DIR/conf.d" "$FALLBACK_NGINX_DIR/snippets" || true
  cat > "$FALLBACK_NGINX_DIR/nginx.conf" <<'NGINXCONF'
user  nginx;
worker_processes  1;
error_log  /var/log/nginx/error.log warn;
pid        /var/run/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  localhost;
        location / {
            root   /usr/share/nginx/html;
            index  index.html index.htm;
        }
    }
}
NGINXCONF
  echo "<html><body><h1>nginx default</h1></body></html>" > "$FALLBACK_NGINX_DIR/index.html"
fi

# Use DIR variable for creating configmaps; prefer real dir over fallback
NGINX_CONFIG_SRC_DIR="$MODULE_DIR/nginx"
if [ ! -d "$NGINX_CONFIG_SRC_DIR" ] && [ -n "$FALLBACK_NGINX_DIR" ]; then
  NGINX_CONFIG_SRC_DIR="$FALLBACK_NGINX_DIR"
fi

if [ -d "$NGINX_CONFIG_SRC_DIR" ]; then
  echo "Creating/updating ConfigMaps from $NGINX_CONFIG_SRC_DIR"
  # nginx.conf
  if [ -f "$NGINX_CONFIG_SRC_DIR/nginx.conf" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create configmap nginx-config --from-file=nginx.conf="$NGINX_CONFIG_SRC_DIR/nginx.conf" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
  fi
  # conf.d
  if [ -d "$NGINX_CONFIG_SRC_DIR/conf.d" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create configmap nginx-confdir --from-file="$NGINX_CONFIG_SRC_DIR/conf.d" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
  fi
  # snippets
  if [ -d "$NGINX_CONFIG_SRC_DIR/snippets" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create configmap nginx-snippets --from-file="$NGINX_CONFIG_SRC_DIR/snippets" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
  fi
fi

# If there's a local ./html directory, create a configmap for static files fallback (optional)
if [ -d "$MODULE_DIR/html" ]; then
  echo "Creating/updating ConfigMap for html content from $MODULE_DIR/html (only used if small)"
  kubectl --kubeconfig "$KUBECONFIG" -n default create configmap nginx-html --from-file="$MODULE_DIR/html" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
else
  # if fallback index exists, create nginx-html configmap from fallback
  if [ -n "$FALLBACK_NGINX_DIR" ] && [ -f "$FALLBACK_NGINX_DIR/index.html" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create configmap nginx-html --from-file="$FALLBACK_NGINX_DIR/index.html" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
  fi
fi

# If certs exists, create a TLS secret (expects tls.crt + tls.key or cert.pem + key.pem)
if [ -d "$MODULE_DIR/certs" ]; then
  echo "Looking for TLS files in $MODULE_DIR/certs"
  if [ -f "$MODULE_DIR/certs/tls.crt" ] && [ -f "$MODULE_DIR/certs/tls.key" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create secret tls nginx-tls --cert="$MODULE_DIR/certs/tls.crt" --key="$MODULE_DIR/certs/tls.key" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
    TLS_SECRET=nginx-tls
  elif [ -f "$MODULE_DIR/certs/cert.pem" ] && [ -f "$MODULE_DIR/certs/key.pem" ]; then
    kubectl --kubeconfig "$KUBECONFIG" -n default create secret tls nginx-tls --cert="$MODULE_DIR/certs/cert.pem" --key="$MODULE_DIR/certs/key.pem" --dry-run=client -o yaml | kubectl --kubeconfig "$KUBECONFIG" apply -f - || true
    TLS_SECRET=nginx-tls
  else
    echo "No recognizable TLS pair found in ./certs (expected tls.crt/tls.key or cert.pem/key.pem). Skipping TLS secret creation." >&2
    TLS_SECRET=""
  fi
else
  TLS_SECRET=""
fi

# prepare service ports and TLS volumes conditionally
if [ -n "${TLS_SECRET:-}" ]; then
  SERVICE_PORTS=$(cat <<'EOF'
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
    - name: https
      protocol: TCP
      port: 443
      targetPort: 443
      nodePort: 30443
EOF
)
  CERT_VOLUME_MOUNT=$(cat <<'EOF'
        - name: nginx-certs
          mountPath: /etc/nginx/certs
          readOnly: true
EOF
)
  SECRET_VOLUME=$(cat <<EOF
      - name: nginx-certs
        secret:
          secretName: ${TLS_SECRET}
EOF
)
else
  SERVICE_PORTS=$(cat <<'EOF'
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30080
EOF
)
  CERT_VOLUME_MOUNT=""
  SECRET_VOLUME=""
fi

# apply nginx deployment + service + configmaps (use DEPLOY_IMAGE detected/imported earlier)
cat <<YAML | kubectl --kubeconfig "$KUBECONFIG" apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  selector:
    app: nginx
  ports:
${SERVICE_PORTS}
  type: NodePort
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      initContainers:
      - name: copy-html
        image: busybox:1.36.1
        command: ["/bin/sh","-c","cp -r /tmp/html/* /usr/share/nginx/html || true"]
        volumeMounts:
        - name: html-config
          mountPath: /tmp/html
        - name: html-content
          mountPath: /usr/share/nginx/html
      containers:
      - name: nginx
        image: ${DEPLOY_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
        - containerPort: 443
        volumeMounts:
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
        - name: nginx-confdir
          mountPath: /etc/nginx/conf.d
        - name: nginx-snippets
          mountPath: /etc/nginx/snippets
        - name: html-content
          mountPath: /usr/share/nginx/html
${CERT_VOLUME_MOUNT}
      volumes:
      - name: nginx-config
        configMap:
          name: nginx-config
      - name: nginx-confdir
        configMap:
          name: nginx-confdir
      - name: nginx-snippets
        configMap:
          name: nginx-snippets
      - name: html-config
        configMap:
          name: nginx-html
      - name: html-content
        emptyDir: {}
${SECRET_VOLUME}
YAML

# If DEPLOY_IMAGE is different than requested IMAGE or contains a digest, ensure the Deployment uses it
if [ "${DEPLOY_IMAGE}" != "${IMAGE}" ] || echo "${DEPLOY_IMAGE}" | grep -q '@sha256:'; then
  echo "Ensuring deployment uses image: ${DEPLOY_IMAGE}"
  kubectl --kubeconfig "$KUBECONFIG" -n default set image deployment/nginx-deployment nginx="${DEPLOY_IMAGE}" --record || true
fi

# wait for rollout with diagnostics on failure
ATT=0
MAX=60
echo "Waiting for nginx deployment to have ready replicas (timeout $((MAX*2))s)..."
while [ $ATT -lt $MAX ]; do
  READY=$(kubectl --kubeconfig "$KUBECONFIG" -n default get deploy nginx-deployment -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  READY=${READY:-0}
  if [ "$READY" -ge 1 ]; then
    echo "nginx deployment ready"
    exit 0
  fi
  ATT=$((ATT+1))
  echo "not ready yet ($ATT/$MAX)"
  sleep 2
done

# Timed out — print diagnostics to help root cause
echo "Warning: nginx deployment did not reach ready state in time. Gathering diagnostics..." >&2
kubectl --kubeconfig "$KUBECONFIG" -n default get pods -o wide || true
PODS=$(kubectl --kubeconfig "$KUBECONFIG" -n default get pods -l app=nginx -o name || true)
for p in $PODS; do
  echo "--- describe $p ---"
  kubectl --kubeconfig "$KUBECONFIG" -n default describe "$p" || true
  echo "--- logs $p (last 200 lines) ---"
  kubectl --kubeconfig "$KUBECONFIG" -n default logs "$p" --tail=200 || true
done

echo "--- recent events (last 200 lines) ---"
kubectl --kubeconfig "$KUBECONFIG" -n default get events --sort-by=.metadata.creationTimestamp | tail -n 200 || true

exit 0
