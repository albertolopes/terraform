#!/usr/bin/env bash
set -euo pipefail

# Build a Docker image from the local Dockerfile and tag it as $IMAGE
# Required env:
#   IMAGE - image tag to build (e.g. nginx:1.29.4-alpine)
# Optional env:
#   PLATFORM - docker buildx platform (default linux/amd64)

IMAGE=${IMAGE:-}
PLATFORM=${PLATFORM:-linux/amd64}

if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE environment variable is required"
  exit 1
fi

if [ ! -f ./Dockerfile ]; then
  echo "No Dockerfile found in current directory; skipping build"
  exit 0
fi

# Use BuildKit for multi-platform builds when available
export DOCKER_BUILDKIT=1

echo "Building local image $IMAGE from Dockerfile for platform $PLATFORM"
# Build and force platform if docker build supports --platform; fallback to normal build
if docker build --help | grep -q -- --platform; then
  docker build --platform "$PLATFORM" -t "$IMAGE" .
else
  docker build -t "$IMAGE" .
fi

echo "Build complete: $IMAGE"
exit 0

