#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

cd "$ROOT_DIR"

requested_mode="${BASELINE_MODE:-V2}"
requested_mode="${requested_mode^^}"
if [[ "$requested_mode" != "V2" ]]; then
  echo "ERROR: Baseline replay is V2-only; BASELINE_MODE=${requested_mode} is not allowed." >&2
  exit 1
fi

requested_profile="${BASELINE_PROFILE:-local_dev}"
requested_profile="${requested_profile,,}"
case "$requested_profile" in
  local_dev|hosted_supabase) ;;
  *)
    echo "ERROR: Baseline replay profile must be local_dev or hosted_supabase; BASELINE_PROFILE=${requested_profile} is not allowed." >&2
    exit 1
    ;;
esac

if [[ "$requested_profile" == "hosted_supabase" && "${ALLOW_HOSTED_BASELINE_REPLAY:-}" != "1" ]]; then
  echo "ERROR: Hosted Supabase replay requires ALLOW_HOSTED_BASELINE_REPLAY=1 and explicit operator approval." >&2
  exit 1
fi

export BASELINE_MODE="V2"
export BASELINE_PROFILE="$requested_profile"
"$AVELI_BACKEND_PYTHON" -c "from backend.bootstrap.baseline_v2 import verify_v2_lock; lock = verify_v2_lock(); print('BASELINE_V2_LOCK_OK=1'); print(f'BASELINE_V2_SLOT_COUNT={len(lock[\"slots\"])}'); print(f'BASELINE_PROFILE={lock[\"execution_profiles\"][\"$requested_profile\"][\"name\"]}')"
exec "$AVELI_BACKEND_PYTHON" -m backend.bootstrap.baseline_v2
