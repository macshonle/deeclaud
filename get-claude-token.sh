#!/usr/bin/env bash
# Retrieves Claude OAuth token from macOS Keychain
set -euo pipefail

SERVICE_NAME="claude-code-container"
ACCOUNT_NAME="oauth-token"

# Retrieve and output token (exits with error if not found)
security find-generic-password \
  -s "$SERVICE_NAME" \
  -a "$ACCOUNT_NAME" \
  -w 2>/dev/null || {
  echo "Error: OAuth token not found in keychain" >&2
  echo "Store it with: security add-generic-password -s '$SERVICE_NAME' -a '$ACCOUNT_NAME' -w '<TOKEN>'" >&2
  exit 1
}
