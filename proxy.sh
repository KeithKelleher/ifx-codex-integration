#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="${CODEX_TOKEN_FILE:-${SCRIPT_DIR}/.codex-token}"

: "${TENANT_ID:?TENANT_ID is not set}"
: "${CLIENT_ID:?CLIENT_ID is not set}"
: "${CLIENT_SECRET:?CLIENT_SECRET is not set}"

TOKEN_ENDPOINT="https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token"
SCOPE="https://cognitiveservices.azure.com/.default"
PROXY_HOST="127.0.0.1"
PROXY_PORT="${PROXY_PORT:-8000}"
UVICORN_LOG_LEVEL="${UVICORN_LOG_LEVEL:-warning}"

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

echo "Requesting Azure access token..."
ensure_commands
AZURE_OPENAI_API_KEY="$(get_access_token)"
export AZURE_OPENAI_API_KEY

umask 077
printf '%s\n' "$AZURE_OPENAI_API_KEY" > "$TOKEN_FILE"

echo "Token acquired."
echo "Token written to ${TOKEN_FILE}."
echo "Starting local Azure auth proxy on ${PROXY_HOST}:${PROXY_PORT}..."
uvicorn proxy:app --app-dir "$SCRIPT_DIR" --host "$PROXY_HOST" --port "$PROXY_PORT" --log-level "$UVICORN_LOG_LEVEL"
