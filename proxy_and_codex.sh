#!/usr/bin/env bash

set -euo pipefail

############################################
# Configuration
############################################

: "${TENANT_ID:?TENANT_ID is not set}"
: "${CLIENT_ID:?CLIENT_ID is not set}"
: "${CLIENT_SECRET:?CLIENT_SECRET is not set}"

TOKEN_ENDPOINT="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
SCOPE="https://cognitiveservices.azure.com/.default"
PROXY_HOST="127.0.0.1"
PROXY_PORT="${PROXY_PORT:-8000}"
UVICORN_LOG_LEVEL="${UVICORN_LOG_LEVEL:-warning}"

PROXY_PID=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

############################################
# Functions
############################################

get_access_token() {
  local response
  local curl_exit=0
  response=$(curl -sS --fail -X POST "$TOKEN_ENDPOINT" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "scope=${SCOPE}" \
    --data-urlencode "grant_type=client_credentials") || curl_exit=$?

  if [[ $curl_exit -ne 0 ]]; then
    echo "Failed to request Azure access token (curl exit ${curl_exit})." >&2
    return "$curl_exit"
  fi

  echo "$response" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if 'error' in data:
    print(f\"OAuth error: {data['error']}: {data.get('error_description','')}\", file=sys.stderr)
    sys.exit(1)
token = data.get('access_token')
if not token:
    print('No access_token in response', file=sys.stderr)
    sys.exit(1)
print(token)
"
}

cleanup() {
  if [[ -n "${PROXY_PID}" ]] && kill -0 "${PROXY_PID}" 2>/dev/null; then
    kill "${PROXY_PID}" 2>/dev/null || true
    wait "${PROXY_PID}" 2>/dev/null || true
  fi
}

ensure_commands() {
  local missing=()
  for command_name in curl python3 uvicorn; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required commands: ${missing[*]}" >&2
    exit 1
  fi
}

start_proxy() {
  echo "Starting local Azure auth proxy on ${PROXY_HOST}:${PROXY_PORT}..."
  uvicorn proxy:app --app-dir "$SCRIPT_DIR" --host "$PROXY_HOST" --port "$PROXY_PORT" --log-level "$UVICORN_LOG_LEVEL" &
  PROXY_PID=$!
  echo "Proxy PID: $PROXY_PID"

  sleep 0.5
  if ! kill -0 "$PROXY_PID" 2>/dev/null; then
    echo "Proxy failed to start." >&2
    exit 1
  fi
}

launch_codex() {
  if command -v codex >/dev/null 2>&1; then
    codex
  else
    echo "Codex CLI not found in PATH."
    exit 1
  fi
}

############################################
# Main
############################################

echo "Requesting Azure access token..."
ensure_commands
trap cleanup EXIT INT TERM
export AZURE_OPENAI_API_KEY="$(get_access_token)"

echo "Token acquired."
start_proxy

echo "Launching Codex..."
launch_codex
