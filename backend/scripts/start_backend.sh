#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${BACKEND_ENV_FILE:-"${BACKEND_DIR}/.env"}"
OVERLAY_ENV_FILE="${BACKEND_ENV_OVERLAY_FILE:-""}"

load_env_file() {
  local env_file="$1"
  if [[ -z "$env_file" ]]; then
    return 0
  fi
  if [[ ! -f "$env_file" ]]; then
    echo "[env] ERROR: env file missing at ${env_file}" >&2
    return 1
  fi
  eval "$(
    python3 - <<'PY' "$env_file"
import os
import shlex
import sys

path = sys.argv[1]
for raw_line in open(path, "r", encoding="utf-8"):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    if line.startswith("export "):
        line = line[len("export "):].strip()
    if "=" not in line:
        continue
    key, value = line.split("=", 1)
    key = key.strip()
    value = value.strip()
    if value and value[0] == value[-1] and value[0] in ("\"", "'"):
        value = value[1:-1]
    if not key:
        continue
    print(f"export {key}={shlex.quote(value)}")
PY
  )"
}

if ! load_env_file "$ENV_FILE"; then
  exit 1
fi
echo "[env] loaded BACKEND_ENV_FILE=$ENV_FILE"
if [[ -n "$OVERLAY_ENV_FILE" ]]; then
  if ! load_env_file "$OVERLAY_ENV_FILE"; then
    exit 1
  fi
  echo "[env] loaded BACKEND_ENV_OVERLAY_FILE=$OVERLAY_ENV_FILE"
else
  echo "[env] loaded BACKEND_ENV_OVERLAY_FILE=none"
fi

PORT="${PORT:-8080}"

cd "$BACKEND_DIR"
if command -v poetry >/dev/null 2>&1; then
  source "$(poetry env info --path)"/bin/activate
fi

echo "[Backend] Starting Uvicorn on port ${PORT}..."
uvicorn app.main:app --reload --host 127.0.0.1 --port "${PORT}"
