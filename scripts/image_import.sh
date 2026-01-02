#!/usr/bin/env bash
set -euo pipefail

# Required env:
#   IMAGE - image reference (e.g. nginx:1.29.4-alpine)
# Optional env:
#   PLATFORM - docker platform to pull (default linux/amd64)
#   DOCKERHUB_USERNAME/DOCKERHUB_PASSWORD - optional credentials for docker.io

IMAGE=${IMAGE:-}
PLATFORM=${PLATFORM:-linux/amd64}
RETRIES=5

if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE environment variable is required"
  exit 1
fi

# Optional Docker Hub login
if [ -n "${DOCKERHUB_USERNAME:-}" ] && [ -n "${DOCKERHUB_PASSWORD:-}" ]; then
  echo "Logging into Docker Hub as $DOCKERHUB_USERNAME"
  echo "$DOCKERHUB_PASSWORD" | docker login -u "$DOCKERHUB_USERNAME" --password-stdin || echo "docker login failed"
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

# If k3d is available, prefer importing by image name; otherwise fallback to save+import
if command -v k3d >/dev/null 2>&1; then
  echo "Attempting k3d image import by name: $IMAGE"
  if k3d image import -c mycluster "$IMAGE" >/dev/null 2>&1; then
    echo "k3d image import by name succeeded for $IMAGE"
    exit 0
  fi

  # fallback: determine a fully-qualified name and save/import tar
  # parse base and tag
  BASE_TAG="$IMAGE"
  NAME_PART="${BASE_TAG%%:*}"
  TAG_PART="${BASE_TAG#*:}"
  if [[ "$BASE_TAG" == *"/"* ]]; then
    FIRST_SEG="${NAME_PART%%/*}"
    if [[ "$FIRST_SEG" == *.* ]] || [[ "$FIRST_SEG" == *:* ]]; then
      FULL_IMAGE="$IMAGE"
    else
      NAME="${NAME_PART##*/}"
      FULL_IMAGE="docker.io/library/${NAME}:${TAG_PART:-latest}"
    fi
  else
    NAME="$NAME_PART"
    FULL_IMAGE="docker.io/library/${NAME}:${TAG_PART:-latest}"
  fi

  # if we have the image locally, tag/save/import it
  if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Tagging $IMAGE -> $FULL_IMAGE"
    docker tag "$IMAGE" "$FULL_IMAGE" || true
    TAR_FILE="${PWD}/.image_for_k3d.tar"
    echo "Saving $FULL_IMAGE to $TAR_FILE"
    docker save -o "$TAR_FILE" "$FULL_IMAGE" || true
    echo "Importing $TAR_FILE into k3d"
    k3d image import -c mycluster "$TAR_FILE" || true
    rm -f "$TAR_FILE" || true
    echo "k3d tar import attempted"
  else
    echo "Local image $IMAGE not found to save; cluster will attempt to pull it when scheduling pods"
  fi
else
  echo "k3d not found; ensure cluster can pull images directly"
fi

exit 0

