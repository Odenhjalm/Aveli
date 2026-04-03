#!/usr/bin/env bash
set -euo pipefail

REPLAY_BASELINE_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPLAY_BASELINE_SCRIPT_DIR="$(cd "$(dirname "$REPLAY_BASELINE_SCRIPT_PATH")" && pwd)"

# shellcheck source=/dev/null
source "$REPLAY_BASELINE_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host

echo "==> Resetting managed schemas for deterministic baseline replay..."
compose_psql <<'SQL'
drop schema if exists app cascade;
drop schema if exists auth cascade;
drop schema if exists extensions cascade;
SQL

echo "==> Applying auth substrate..."
compose_psql < "$AUTH_SUBSTRATE_SQL"

echo "==> Applying baseline slots..."
mapfile -t slot_files < <(
  "$AVELI_BACKEND_PYTHON" - <<'PY' "$LOCK_FILE"
import json
import sys
from pathlib import Path

lock_path = Path(sys.argv[1])
data = json.loads(lock_path.read_text())
for entry in sorted(data["slots"], key=lambda item: int(item["slot"])):
    print(entry["path"])
PY
)

for relative_path in "${slot_files[@]}"; do
  absolute_path="$ROOT_DIR/$relative_path"
  if [[ ! -f "$absolute_path" ]]; then
    echo "ERROR: baseline slot missing: $absolute_path" >&2
    exit 1
  fi
  compose_psql < "$absolute_path"
  echo "   applied ${relative_path##*/}"
done

echo "==> Baseline replay complete."
