#!/usr/bin/env bash
set -euo pipefail

CMD=$(basename "$0")

err() {
  echo "${CMD}: ${*}" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $CMD [--debug] setup [DockerfileName]
  $CMD check [DockerfileName]
  $CMD teardown [DockerfileName]

Options:
  --debug    Use --no-cache --progress=plain when building

DockerfileName defaults to Dockerfile.claude-dev if not specified.

Examples:
  $CMD setup
  $CMD --debug setup
  $CMD setup Dockerfile.claude-dev-python312
  $CMD check
  $CMD check Dockerfile.claude-dev-python312
  $CMD teardown
EOF
  exit 1
}

if [ $# -lt 1 ]; then usage; fi

# Parse --debug flag
DEBUG_BUILD=false
if [ "$1" = "--debug" ]; then
  DEBUG_BUILD=true
  shift
fi

if [ $# -lt 1 ]; then usage; fi

ACTION="$1"
VARIANT="${2:-Dockerfile.claude-dev}"

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Image name is derived from Dockerfile name
IMAGE_NAME="$(basename "$VARIANT" | sed 's/^Dockerfile\.//')"

for cmd in git container; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd: command not found"
  fi
done

# Resolve full path to Dockerfile
DOCKERFILE_PATH="$SCRIPT_DIR/$VARIANT"

check_dockerfile() {
  if [ ! -f "$DOCKERFILE_PATH" ]; then
    err "Dockerfile '$DOCKERFILE_PATH' not found"
  fi
}

check_image() {
  container image list | grep -q "^${IMAGE_NAME}" || return 1
}

setup() {
  check_dockerfile
  echo "Setting up Claude container environment for variant: $IMAGE_NAME"

  echo "Pulling Ubuntu base image..."
  BASE_IMAGE="ubuntu:22.04"
  container image pull "docker.io/library/${BASE_IMAGE}"

  echo "Building image '$IMAGE_NAME' from $VARIANT..."

  # Generate metadata labels
  BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  BUILDER_VERSION="1.0"
  LABEL_ARGS=(
    "--label" "com.anthropic.claude-container.variant=${IMAGE_NAME}"
    "--label" "com.anthropic.claude-container.build-timestamp=${BUILD_TIMESTAMP}"
    "--label" "com.anthropic.claude-container.builder-version=${BUILDER_VERSION}"
    "--label" "com.anthropic.claude-container.base-image=${BASE_IMAGE}"
  )

  if [ "$DEBUG_BUILD" = true ]; then
    container build --memory 4G \
      "${LABEL_ARGS[@]}" \
      --no-cache --progress=plain --build-arg DEBUG=1 \
      -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$SCRIPT_DIR"
  else
    container build --memory 4G \
      "${LABEL_ARGS[@]}" \
      --build-arg DEBUG=0 \
      -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$SCRIPT_DIR"
  fi
  echo "Initialization complete."
  echo "Image: $IMAGE_NAME"
}

check() {
  echo "Checking Claude container environment for variant: $IMAGE_NAME"

  if ! check_image; then
    err "Image '$IMAGE_NAME' not found. Run: $CMD setup $VARIANT"
  fi

  # Display image metadata
  echo "Container image metadata:"
  container image inspect "$IMAGE_NAME" 2>/dev/null | \
    python3 -c '
  import sys, json
  try:
      data = json.load(sys.stdin)
      labels = data[0]["variants"][0]["config"]["config"].get("Labels", {})
      for key, val in labels.items():
          if key.startswith("com.anthropic.claude-container."):
              short_key = key.replace("com.anthropic.claude-container.", "")
              print(f"  {short_key}: {val}")
  except Exception as e:
      print(f"  (metadata unavailable: {e})", file=sys.stderr)
  ' || echo "  (metadata query failed)"
}

teardown() {
  echo "Tearing down Claude container environment for variant: $IMAGE_NAME"

  # Remove containers using this image
  for cid in $(container list --all | awk -v img="$IMAGE_NAME" '$2==img {print $1}'); do
    echo "Removing container $cid"
    container rm "$cid"
  done

  # Remove image
  if check_image; then
    echo "Removing image $IMAGE_NAME"
    container image rm "$IMAGE_NAME"
  fi

  echo "Teardown complete."
}

case "$ACTION" in
  setup) setup ;;
  check) check ;;
  teardown) teardown ;;
  *) usage ;;
esac
