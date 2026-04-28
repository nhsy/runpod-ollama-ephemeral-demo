#!/bin/bash
# scripts/fetch-ssh.sh
# Usage: ./scripts/fetch-ssh.sh <POD_ID>
# Deps:  runpodctl (configured with RUNPOD_API_KEY or ~/.runpod/config.toml)

set -euo pipefail

POD_ID="${1:?Usage: fetch-ssh.sh <pod_id>}"
SSH_CONFIG="${HOME}/.ssh/config"
SSH_HOST_ALIAS="runpod-ollama"

# Validate JSON output from runpodctl
INFO=$(runpodctl ssh info "$POD_ID" 2>/dev/null) || {
  echo "Error: runpodctl ssh info failed for pod $POD_ID" >&2
  exit 1
}

# Check if output is valid JSON
if ! echo "$INFO" | jq empty 2>/dev/null; then
  echo "Error: invalid JSON from runpodctl" >&2
  exit 1
fi

# Extract fields
POD_IP=$(echo "$INFO" | jq -r '.ip // empty')
POD_PORT=$(echo "$INFO" | jq -r '.port // empty')

# Validate we have required fields
if [[ -z "$POD_IP" ]]; then
  echo "Error: could not parse IP from runpodctl output" >&2
  exit 1
fi

if [[ -z "$POD_PORT" ]]; then
  echo "Error: could not parse port from runpodctl output" >&2
  exit 1
fi

echo "Pod $POD_ID → $POD_IP:$POD_PORT"

# --- Patch ~/.ssh/config ---

# Create temp file for the new config
TEMP_CONFIG=$(mktemp)
trap 'rm -f "$TEMP_CONFIG"' EXIT

if grep -q "^Host ${SSH_HOST_ALIAS}$" "$SSH_CONFIG" 2>/dev/null; then
  # Update existing host block
  awk -v alias="$SSH_HOST_ALIAS" -v ip="$POD_IP" -v port="$POD_PORT" '
    /^Host / { in_target = ($0 == "Host " alias) }
    in_target && /^[[:space:]]+HostName / { print "  HostName " ip; next }
    in_target && /^[[:space:]]+Port / { print "  Port " port; next }
    { print }
  ' "$SSH_CONFIG" > "$TEMP_CONFIG"

  # Only overwrite if changes were made
  if ! cmp -s "$TEMP_CONFIG" "$SSH_CONFIG"; then
    mv "$TEMP_CONFIG" "$SSH_CONFIG"
    trap - EXIT
    echo "Updated '${SSH_HOST_ALIAS}' in ${SSH_CONFIG}"
  else
    echo "No changes needed for '${SSH_HOST_ALIAS}'"
  fi
else
  # Append new host block
  cat >> "$SSH_CONFIG" << EOF

Host ${SSH_HOST_ALIAS}
  HostName ${POD_IP}
  Port ${POD_PORT}
  User root
  IdentityFile ~/.ssh/id_ed25519
  LocalForward 11434 127.0.0.1:11434
  ServerAliveInterval 30
  ServerAliveCountMax 3
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
  StrictHostKeyChecking accept-new
EOF
  echo "Appended '${SSH_HOST_ALIAS}' to ${SSH_CONFIG}"
fi

echo "Connect: ssh ${SSH_HOST_ALIAS}"
echo "Verify:  curl http://localhost:11434/api/version"
