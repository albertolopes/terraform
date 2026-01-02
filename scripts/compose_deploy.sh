#!/usr/bin/env bash
set -euo pipefail
MODULE_DIR=${MODULE_DIR:-$PWD}
COMPOSE_FILE="$MODULE_DIR/docker-compose.yml"
KUBECONFIG=${KUBECONFIG:-$PWD/.k3d_kubeconfig}

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "docker-compose.yml not found at $COMPOSE_FILE"
  echo "Please place your docker-compose.yml in the module directory or set COMPOSE_FILE to point to it"
  exit 1
fi

# Extract the services section to search for service images and mounts. Using sed is more tolerant
SERVICES_SECTION=$(sed -n '/^services:/,/^[^[:space:]]/p' "$COMPOSE_FILE" 2>/dev/null || sed -n '/^services:/,$p' "$COMPOSE_FILE")
if [ -z "$SERVICES_SECTION" ]; then
  echo "Could not find a 'services:' section in $COMPOSE_FILE" >&2
  exit 1
fi

# extract service:image pairs and pick the best candidate (prefer service named 'nginx')
SERVICE_IMAGES_RAW=$(awk '
  BEGIN{in_services=0; svc=""}
  /^\s*services:\s*$/ { in_services=1; next }
  in_services==1 {
    if (match($0,/^[ \t]*([^[:space:]:]+):[ \t]*$/,m)) { svc=m[1]; next }
    if (match($0,/^[ \t]*image[ \t]*:[ \t]*/)) {
      line=$0
      sub(/^[ \t]*image[ \t]*:[ \t]*/,"",line)
      gsub(/^[ \t]+|[ \t]+$/,"",line)
      print svc ":" line
    }
  }
' <<< "$SERVICES_SECTION")

NGINX_IMAGE=""
# prefer exact service name 'nginx'
if [ -n "$SERVICE_IMAGES_RAW" ]; then
  # try service named nginx
  NGINX_IMAGE=$(printf '%s' "$SERVICE_IMAGES_RAW" | awk -F: '$1=="nginx" { $1=""; sub(/^:/,""); print substr($0,2); exit }' || true)
  # if not found, try any image that contains 'nginx'
  if [ -z "$NGINX_IMAGE" ]; then
    NGINX_IMAGE=$(printf '%s' "$SERVICE_IMAGES_RAW" | awk -F: '{ img=substr($0,index($0,":")+1); if(tolower(img) ~ /nginx/) { print img; exit } }' || true)
  fi
  # fallback: take first image
  if [ -z "$NGINX_IMAGE" ]; then
    NGINX_IMAGE=$(printf '%s' "$SERVICE_IMAGES_RAW" | head -n1 | sed 's/^[^:]*://' || true)
  fi
fi

if [ -z "$NGINX_IMAGE" ]; then
  echo "No image found for any service in $COMPOSE_FILE" >&2
  exit 1
fi

# find host paths mounted within the services section
NGINX_CONF_DIR=$(printf '%s' "$SERVICES_SECTION" | grep -oE "\./nginx(/[^[:space:]\"]*)?" | head -n1 || true)
HTML_DIR=$(printf '%s' "$SERVICES_SECTION" | grep -oE "\./html(/[^[:space:]\"]*)?" | head -n1 || true)
CERTS_DIR=$(printf '%s' "$SERVICES_SECTION" | grep -oE "\./certs(/[^[:space:]\"]*)?" | head -n1 || true)
SSL_DIR=$(printf '%s' "$SERVICES_SECTION" | grep -oE "\./ssl(/[^[:space:]\"]*)?" | head -n1 || true)

# normalize to absolute paths
if [ -n "$NGINX_CONF_DIR" ]; then NGINX_CONF_DIR="$MODULE_DIR/${NGINX_CONF_DIR#./}"; fi
if [ -n "$HTML_DIR" ]; then HTML_DIR="$MODULE_DIR/${HTML_DIR#./}"; fi
if [ -n "$CERTS_DIR" ]; then CERTS_DIR="$MODULE_DIR/${CERTS_DIR#./}"; fi
if [ -n "$SSL_DIR" ]; then SSL_DIR="$MODULE_DIR/${SSL_DIR#./}"; fi

export NGINX_IMAGE
export IMAGE="$NGINX_IMAGE"
export NGINX_CONF_DIR
export HTML_DIR
export CERTS_DIR
export SSL_DIR
export KUBECONFIG

echo "Using image: $NGINX_IMAGE"
[ -n "$NGINX_CONF_DIR" ] && echo "Found nginx conf dir: $NGINX_CONF_DIR"
[ -n "$HTML_DIR" ] && echo "Found html dir: $HTML_DIR"
[ -n "$CERTS_DIR" ] && echo "Found certs dir: $CERTS_DIR"
[ -n "$SSL_DIR" ] && echo "Found ssl dir: $SSL_DIR"

# Call image import wrapper to ensure image is present in k3d
if [ -x "$MODULE_DIR/scripts/image_import_wrapper.sh" ]; then
  echo "Importing image into k3d (if needed)..."
  (cd "$MODULE_DIR" && IMAGE="$IMAGE" bash ./scripts/image_import_wrapper.sh)
else
  echo "image_import_wrapper.sh not found or not executable; skipping image import" >&2
fi

# Call deploy script which will create configmaps/secrets and the deployment
if [ -x "$MODULE_DIR/scripts/deploy_nginx.sh" ]; then
  echo "Deploying nginx via cluster-managed manifests..."
  (cd "$MODULE_DIR" && export NGINX_IMAGE="$NGINX_IMAGE" && bash ./scripts/deploy_nginx.sh)
else
  echo "deploy_nginx.sh not found or not executable" >&2
  exit 1
fi
