#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="aveli"
TARGET_MEMORY_MB="2048"

log() {
  printf '[fly-enforce-vm] %s\n' "$*"
}

fail() {
  printf '[fly-enforce-vm] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

machine_rows() {
  fly machine list --app "$APP_NAME" --json | node -e '
const fs = require("fs");
let machines;

try {
  machines = JSON.parse(fs.readFileSync(0, "utf8"));
} catch (error) {
  console.error(`failed to parse fly machine JSON: ${error.message}`);
  process.exit(2);
}

if (!Array.isArray(machines)) {
  console.error("fly machine list --json did not return an array");
  process.exit(2);
}

let invalid = false;
for (const machine of machines) {
  const id = machine && machine.id;
  const config = machine && machine.config ? machine.config : {};
  const guest = config.guest ? config.guest : {};
  const metadata = config.metadata ? config.metadata : {};
  const env = config.env ? config.env : {};
  const memory = Object.prototype.hasOwnProperty.call(guest, "memory_mb") ? guest.memory_mb : "";
  const processGroup = metadata.fly_process_group || env.FLY_PROCESS_GROUP || "";
  const state = machine && machine.state ? machine.state : "";

  if (!id) {
    console.error("machine entry is missing id");
    invalid = true;
    continue;
  }

  console.log([id, memory, processGroup, state].join("\t"));
}

if (invalid) {
  process.exit(2);
}
'
}

require_cmd fly
require_cmd node

log "app=${APP_NAME} target_memory_mb=${TARGET_MEMORY_MB}"

machine_count=0
updated_count=0

while IFS=$'\t' read -r machine_id memory_mb process_group state; do
  [[ -n "$machine_id" ]] || continue
  machine_count=$((machine_count + 1))
  process_group="${process_group:-unknown}"
  state="${state:-unknown}"

  if [[ "$memory_mb" == "$TARGET_MEMORY_MB" ]]; then
    log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=${memory_mb} result=already-correct"
    continue
  fi

  if [[ -z "$memory_mb" ]]; then
    log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=missing action=update target_memory_mb=${TARGET_MEMORY_MB}"
  else
    log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=${memory_mb} action=update target_memory_mb=${TARGET_MEMORY_MB}"
  fi

  update_args=(machine update "$machine_id" --app "$APP_NAME" --vm-memory "$TARGET_MEMORY_MB" --yes --wait-timeout 300)
  if [[ "$state" != "started" ]]; then
    update_args+=(--skip-start)
  fi

  fly "${update_args[@]}"
  updated_count=$((updated_count + 1))
  log "machine=${machine_id} result=updated target_memory_mb=${TARGET_MEMORY_MB}"
done < <(machine_rows)

if [[ "$machine_count" -eq 0 ]]; then
  fail "no machines found for app ${APP_NAME}"
fi

log "complete machines_seen=${machine_count} machines_updated=${updated_count}"
