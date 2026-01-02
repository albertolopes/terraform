#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   IMAGE - image reference (e.g. nginx:1.29.4-alpine)
# Optional env:
#   PLATFORM - docker platform to pull (default linux/amd64)

IMAGE=${IMAGE:-}
PLATFORM=${PLATFORM:-linux/amd64}
RETRIES=5

if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE environment variable is required"
  exit 1
fi

# Try to pull the image for the requested platform
i=0
until docker pull --platform "$PLATFORM" "$IMAGE" >/dev/null 2>&1; do
  i=$((i+1))
  if [ $i -ge $RETRIES ]; then
    echo "Warning: docker pull $IMAGE failed after $RETRIES attempts"
    break
  fi
  echo "retrying pull ($i/$RETRIES)..."
  sleep 3
done

# source common lib
if [ -f ./scripts/lib.sh ]; then
  # shellcheck disable=SC1091
  . ./scripts/lib.sh
fi

# If k3d is available, prefer importing by image name; otherwise fallback to save+import
if command -v k3d >/dev/null 2>&1; then
  echo "Attempting k3d image import by name: $IMAGE"
  if k3d_import_cmd "$IMAGE" >/dev/null 2>&1; then
    echo "k3d image import by name succeeded for $IMAGE"
    exit 0
  fi

  # fallback: save the local image (if present) and import tar into k3d
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    TAR_FILE="${PWD}/.image_for_k3d.tar"
    echo "Saving $IMAGE to $TAR_FILE"
    docker save -o "$TAR_FILE" "$IMAGE" || true
    echo "Importing $TAR_FILE into k3d"
    k3d_import_cmd "$TAR_FILE" || true
    rm -f "$TAR_FILE" || true
    echo "k3d tar import attempted"
  else
    echo "Local image $IMAGE not found to save; cluster will attempt to pull it when scheduling pods"
  fi
else
  echo "k3d not found; ensure cluster can pull images directly"
fi

exit 0
