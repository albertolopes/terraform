#!/usr/bin/env bash
set -euo pipefail

# Wrapper: if a Dockerfile exists, build the image locally first, then call image_import.sh
IMAGE=${IMAGE:-}
if [ -z "$IMAGE" ]; then
  echo "ERROR: IMAGE is required"
  exit 1
fi

# If there's a Dockerfile and the requested image tag looks like it matches this Dockerfile,
# build it locally. We can't detect automatically if the Dockerfile corresponds to the exact tag,
# so we just build if a Dockerfile exists to help local dev workflows.
if [ -f ./Dockerfile ]; then
  echo "Dockerfile present — attempting to build image $IMAGE"
  export IMAGE
  export PLATFORM
  bash ./scripts/build_image.sh
fi

# Now call the image_import script
export IMAGE
export PLATFORM
bash ./scripts/image_import.sh

exit 0
