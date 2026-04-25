#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="aveli"
TARGET_MEMORY_MB="2048"

log() {
  printf '[fly-verify-vm] %s\n' "$*"
}

fail() {
  printf '[fly-verify-vm] ERROR: %s\n' "$*" >&2
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
mismatch_count=0

while IFS=$'\t' read -r machine_id memory_mb process_group state; do
  [[ -n "$machine_id" ]] || continue
  machine_count=$((machine_count + 1))
  process_group="${process_group:-unknown}"
  state="${state:-unknown}"

  if [[ "$memory_mb" == "$TARGET_MEMORY_MB" ]]; then
    log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=${memory_mb} result=pass"
  else
    if [[ -z "$memory_mb" ]]; then
      log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=missing expected_memory_mb=${TARGET_MEMORY_MB} result=fail"
    else
      log "machine=${machine_id} process_group=${process_group} state=${state} memory_mb=${memory_mb} expected_memory_mb=${TARGET_MEMORY_MB} result=fail"
    fi
    mismatch_count=$((mismatch_count + 1))
  fi
done < <(machine_rows)

if [[ "$machine_count" -eq 0 ]]; then
  fail "no machines found for app ${APP_NAME}"
fi

if [[ "$mismatch_count" -ne 0 ]]; then
  fail "memory verification failed mismatches=${mismatch_count} machines_seen=${machine_count}"
fi

log "complete machines_seen=${machine_count} mismatches=${mismatch_count}"
