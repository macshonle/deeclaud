#!/usr/bin/env bash

# Deeclaud(*): Contain the beast! Run Claude Code in a container.

# (*) We want to be clear that we don't support the practice of declawing cats
# or other animals. Declawing amputates part of a cat's toes and can cause
# lasting pain and behavior problems. Many veterinary organizations and
# countries have recognized this harm and now discourage or ban the procedure.
# Scratching issues can be managed humanely with regular nail trimming,
# scratching posts, or nail caps.

set -euo pipefail

# Cleanup function to restore terminal state
cleanup_terminal() {
  stty sane 2>/dev/null || true
  tput init 2>/dev/null || true
}

# Ensure terminal cleanup on exit (normal or interrupted)
trap cleanup_terminal EXIT INT TERM

CMD=$(basename "$0")

usage() {
  echo "Usage: $CMD <repo-dir> <branch> [variant]"
  exit 1
}

err() {
  echo "${CMD}: ${*}" >&2
  exit 1
}

if [ $# -lt 2 ]; then usage; fi

REPO_DIR="$1"
BRANCH="$2"
VARIANT="${3:-Dockerfile.claude-dev}"

for cmd in git container; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "$cmd: command not found"
  fi
done

# Resolve absolute paths
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

# Validate repo
[ -d "$REPO_DIR/.git" ] || err "$REPO_DIR: Not a git repository"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 \
  || err "$BRANCH: Invalid branch name"

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Derive names
BRANCH_SAFE="${BRANCH//\//-}"
REPO_NAME="$(basename "$REPO_DIR")"
IMAGE_NAME="$(basename "$VARIANT" | sed 's/^Dockerfile\.//')"
CONTAINER_NAME="${IMAGE_NAME}-${REPO_NAME}-${BRANCH_SAFE}"

# Per-repo, per-variant container home (shared across branches)
CONTAINER_HOME="$HOME/Containers/${IMAGE_NAME}-${REPO_NAME}-home"
mkdir -p "$CONTAINER_HOME"

# Worktree
BASE_DIR="$(dirname "$REPO_DIR")"
WORKTREE_DIR="$BASE_DIR/${REPO_NAME}-wt-${BRANCH_SAFE}"

if ! git -C "$REPO_DIR" worktree list | grep -q "$WORKTREE_DIR"; then
  echo "Creating worktree at $WORKTREE_DIR"
  if git -C "$REPO_DIR" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git -C "$REPO_DIR" worktree add "$WORKTREE_DIR" "$BRANCH"
  else
    git -C "$REPO_DIR" worktree add -b "$BRANCH" "$WORKTREE_DIR"
  fi
fi

# Initialize/update submodules in worktree (if any exist)
if [ -f "$WORKTREE_DIR/.gitmodules" ]; then
  echo "Initializing submodules in worktree..."
  git -C "$WORKTREE_DIR" submodule update --init --recursive
fi

# Check environment
if ! container image list | grep -q "^${IMAGE_NAME}"; then
  err "Image '$IMAGE_NAME' not found. Run: ./manage-container.sh setup $VARIANT"
fi

# Retrieve OAuth token from keychain
echo "Retrieving OAuth token..."
CLAUDE_CODE_OAUTH_TOKEN=$("$SCRIPT_DIR/get-claude-token.sh") || err "Failed to retrieve OAuth token"
echo "Token retrieved (starts with: ${CLAUDE_CODE_OAUTH_TOKEN:0:15}...)"

# Remove old container if exists
INSPECT_OUTPUT=$(container inspect "$CONTAINER_NAME" 2>/dev/null)
if [ "$INSPECT_OUTPUT" != "[]" ]; then
  echo "Removing old container $CONTAINER_NAME"
  container rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Container user home directory
CONTAINER_USER_HOME="/home/claude"

# Shared credentials (read-only mounts for security)
GH_CONFIG="$HOME/.config/gh"
SSH_DIR="$HOME/.ssh"

VOLUMES=(
  "--volume" "$CONTAINER_HOME:$CONTAINER_USER_HOME"
  "--volume" "$WORKTREE_DIR:/workspace"
)

[ -d "$GH_CONFIG" ] && VOLUMES+=("--volume" "$GH_CONFIG:$CONTAINER_USER_HOME/.config/gh:ro")
[ -d "$SSH_DIR" ] && VOLUMES+=("--volume" "$SSH_DIR:$CONTAINER_USER_HOME/.ssh:ro")

# Run Claude Code interactively
# Use full path to claude binary to avoid PATH issues
CLAUDE_BIN="/opt/claude/bin/claude"
SETUP_CMD="mkdir -p ~/.local/bin && ln -sf $CLAUDE_BIN ~/.local/bin/claude"
RUN_CMD="$CLAUDE_BIN --dangerously-skip-permissions /workspace"

echo "Launching container: $CONTAINER_NAME"
container run --memory 4G -it --rm \
  --name "$CONTAINER_NAME" \
  --workdir /workspace \
  --env "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN" \
  --env "HOME=$CONTAINER_USER_HOME" \
  --env "PATH=$CONTAINER_USER_HOME/.local/bin:/opt/claude/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  "${VOLUMES[@]}" \
  "$IMAGE_NAME" \
  bash -c "$SETUP_CMD && $RUN_CMD"
