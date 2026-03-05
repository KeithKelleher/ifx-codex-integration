#!/usr/bin/env bash

set -euo pipefail

PROXY_HOST="127.0.0.1"
PROXY_PORT="${PROXY_PORT:-8000}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOKEN_FILE="${CODEX_TOKEN_FILE:-${SCRIPT_DIR}/.codex-token}"

load_token_file() {
  if [[ -n "${AZURE_OPENAI_API_KEY:-}" ]]; then
    return
  fi

if [[ -f "$TOKEN_FILE" ]]; then
    AZURE_OPENAI_API_KEY="$(<"$TOKEN_FILE")"
    export AZURE_OPENAI_API_KEY
  fi
}

ensure_commands() {
  local missing=()
  for command_name in curl codex; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required commands: ${missing[*]}" >&2
    exit 1
  fi
}

ensure_proxy_running() {
  if ! curl -sS --max-time 2 "http://${PROXY_HOST}:${PROXY_PORT}/health" >/dev/null; then
    echo "Local proxy is not reachable at ${PROXY_HOST}:${PROXY_PORT}." >&2
    echo "Start it first in another terminal: ./proxy.sh" >&2
    exit 1
  fi
}

launch_codex() {
  codex
}

load_token_file
ensure_commands
ensure_proxy_running

if [[ -z "${AZURE_OPENAI_API_KEY:-}" ]]; then
  echo "Missing environment variable: AZURE_OPENAI_API_KEY" >&2
  echo "Start ./proxy.sh first so it writes ${TOKEN_FILE}." >&2
  exit 1
fi

echo "Launching Codex..."
launch_codex
