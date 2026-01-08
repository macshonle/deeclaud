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
  $CMD [--debug] check [DockerfileName]
  $CMD teardown [DockerfileName]

Options:
  --debug    Use --no-cache --progress=plain when building
  --help     Show this help message

DockerfileName defaults to Dockerfile.claude-dev if not specified.

Environment:
  DEECLAUD_MEMORY   Container memory limit for builds (default: 4G)

Examples:
  $CMD setup
  $CMD --debug setup
  $CMD setup --debug                      # --debug can come after action
  $CMD setup Dockerfile.claude-dev-python312
  $CMD check
  $CMD teardown
  DEECLAUD_MEMORY=8G $CMD setup
EOF
  exit 2
}

if [ $# -lt 1 ]; then usage; fi

# Parse flags (--debug and --help can appear anywhere)
DEBUG_BUILD=false
ACTION=""
VARIANT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)
      DEBUG_BUILD=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    setup|check|teardown)
      ACTION="$1"
      shift
      ;;
    Dockerfile.*)
      # Dockerfile variant
      VARIANT="$1"
      shift
      ;;
    *)
      # Unknown option
      err "Unknown option: $1. Use --help for usage."
      ;;
  esac
done

if [ -z "$ACTION" ]; then usage; fi
VARIANT="${VARIANT:-Dockerfile.claude-dev}"

# Memory limit for container builds (default: 4G)
MEMORY_LIMIT="${DEECLAUD_MEMORY:-4G}"

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
  if ! container image pull "docker.io/library/${BASE_IMAGE}"; then
    err "Failed to pull base image. Check network connectivity and try again."
  fi

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
    container build --memory "$MEMORY_LIMIT" \
      "${LABEL_ARGS[@]}" \
      --no-cache --progress=plain --build-arg DEBUG=1 \
      -t "$IMAGE_NAME" -f "$DOCKERFILE_PATH" "$SCRIPT_DIR"
  else
    container build --memory "$MEMORY_LIMIT" \
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
  if ! command -v python3 >/dev/null 2>&1; then
    echo "  (python3 not found - metadata display unavailable)"
    return 0
  fi
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
    if ! container rm "$cid" 2>/dev/null; then
      echo "  Warning: Failed to remove container $cid (may already be removed)"
    fi
  done

  # Remove image
  if check_image; then
    echo "Removing image $IMAGE_NAME"
    if ! container image rm "$IMAGE_NAME"; then
      err "Failed to remove image '$IMAGE_NAME'. It may be in use by running containers."
    fi
  else
    echo "Image '$IMAGE_NAME' not found (already removed or never built)"
  fi

  echo "Teardown complete."
}

case "$ACTION" in
  setup) setup ;;
  check) check ;;
  teardown) teardown ;;
  *) usage ;;
esac
