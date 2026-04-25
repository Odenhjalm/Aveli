#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="aveli"
TARGET_MEMORY_MB="2048"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() {
  printf '[deploy] %s\n' "$*"
}

fail() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

require_cmd fly
require_cmd node
require_cmd bash

cd "$REPO_DIR"

log "app=${APP_NAME} target_memory_mb=${TARGET_MEMORY_MB} action=fly-deploy"
fly deploy --app "$APP_NAME" --config "$REPO_DIR/fly.toml" --yes

log "action=enforce-vm-memory"
bash "$SCRIPT_DIR/fly_enforce_vm.sh"

log "action=verify-vm-memory"
bash "$SCRIPT_DIR/fly_verify_vm.sh"

log "complete app=${APP_NAME} verified_memory_mb=${TARGET_MEMORY_MB}"
