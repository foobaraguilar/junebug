#!/usr/bin/env bash
# Gateway wrapper — project-local OpenClaw state (openclaw/runtime/).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export OPENCLAW_STATE_DIR="$REPO_ROOT/openclaw/runtime"
export OPENCLAW_CONFIG_PATH="$OPENCLAW_STATE_DIR/openclaw.json"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "error: openclaw CLI not found — install from https://openclaw.ai" >&2
  exit 1
fi

exec openclaw "$@"
