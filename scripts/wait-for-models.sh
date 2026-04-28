#!/usr/bin/env bash
set -euo pipefail

# Read expected models from Terraform output
MODELS_RAW="$(terraform output -raw ollama_models)"

if [[ -z "$MODELS_RAW" ]]; then
  echo "No ollama_models found in Terraform output"
  exit 0
fi

IFS=',' read -ra EXPECTED_MODELS <<< "$MODELS_RAW"

echo "Waiting for Ollama models to be ready (${#EXPECTED_MODELS[@]} models)..."

MAX_RETRIES=180
RETRY_INTERVAL=10
RETRY=0

while (( RETRY < MAX_RETRIES )); do
  if ! RESPONSE=$(curl -sf http://localhost:11434/api/tags 2>/dev/null); then
    echo "  Attempt $((RETRY + 1))/${MAX_RETRIES} — Ollama not responding yet, retrying in ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
    RETRY=$((RETRY + 1))
    continue
  fi

  ALL_FOUND=true
  for MODEL in "${EXPECTED_MODELS[@]}"; do
    if ! echo "$RESPONSE" | jq -e --arg model "$MODEL" '[.models[].name] | index($model) == null | not' > /dev/null 2>&1; then
      ALL_FOUND=false
      break
    fi
  done

  if $ALL_FOUND; then
    echo "All models loaded and ready!"
    exit 0
  fi

  echo "  Attempt $((RETRY + 1))/${MAX_RETRIES} — models not ready yet, retrying in ${RETRY_INTERVAL}s..."
  sleep "$RETRY_INTERVAL"
  RETRY=$((RETRY + 1))
done

echo "Timeout waiting for models after $((MAX_RETRIES * RETRY_INTERVAL))s"
exit 1