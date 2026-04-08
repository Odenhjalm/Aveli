#!/usr/bin/env bash
set -euo pipefail

REPLAY_BASELINE_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPLAY_BASELINE_SCRIPT_DIR="$(cd "$(dirname "$REPLAY_BASELINE_SCRIPT_PATH")" && pwd)"
BOOTSTRAP_GATE_ROOT_DIR="$(cd "$REPLAY_BASELINE_SCRIPT_DIR/../.." && pwd)"

source "$BOOTSTRAP_GATE_ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"
PYTHON_BIN="$AVELI_BACKEND_PYTHON"
export AVELI_BACKEND_PYTHON="$PYTHON_BIN"

set +e
GATE_OUTPUT="$(
  cd "$BOOTSTRAP_GATE_ROOT_DIR" &&
  "$PYTHON_BIN" backend/scripts/bootstrap_gate.py 2>&1 | tr -d '\r'
)"
GATE_STATUS=$?
set -e

printf '%s\n' "$GATE_OUTPUT"

if [ "$GATE_STATUS" -ne 0 ]; then
  echo "BOOTSTRAP GATE FAILED - STOPPING"
  exit 1
fi

if ! printf '%s\n' "$GATE_OUTPUT" | grep -q '^BOOTSTRAP_GATE_OK=1$'; then
  echo "BOOTSTRAP TOKEN MISSING - STOPPING"
  exit 1
fi

# shellcheck source=/dev/null
source "$REPLAY_BASELINE_SCRIPT_DIR/dev_common.sh"

load_backend_env
require_local_db_config
require_local_db_host
require_postgres_cli
wait_for_local_postgres postgres
ensure_local_database_exists

echo "==> Local MCP audit/testing/verification authority: backend/supabase/baseline_slots"
echo "==> Resetting managed schemas for deterministic baseline replay..."
db_psql <<'SQL'
drop schema if exists app cascade;
drop schema if exists auth cascade;
drop schema if exists extensions cascade;
drop schema if exists storage cascade;
SQL

echo "==> Applying auth substrate..."
db_psql < "$AUTH_SUBSTRATE_SQL"

echo "==> Applying baseline slots..."
lock_file_for_python="$LOCK_FILE"
if [[ "${PYTHON_BIN,,}" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
  lock_file_for_python="$(wslpath -w "$LOCK_FILE")"
fi

slot_listing="$(
  "$PYTHON_BIN" - <<'PY' "$lock_file_for_python"
import json
import sys
from pathlib import Path

lock_path = Path(sys.argv[1])
data = json.loads(lock_path.read_text())
for entry in sorted(data["slots"], key=lambda item: int(item["slot"])):
    print(entry["path"])
PY
)"

mapfile -t slot_files < <(printf '%s\n' "$slot_listing" | tr -d '\r')

for relative_path in "${slot_files[@]}"; do
  absolute_path="$ROOT_DIR/$relative_path"
  if [[ ! -f "$absolute_path" ]]; then
    echo "ERROR: baseline slot missing: $absolute_path" >&2
    exit 1
  fi
  db_psql < "$absolute_path"
  echo "   applied ${relative_path##*/}"
done

echo "==> Applying storage substrate..."
db_psql < "$STORAGE_SUBSTRATE_SQL"

echo "==> Applying local test cleanup substrate..."
db_psql <<'SQL'
create or replace function app.cleanup_test_session(target_test_session_id uuid)
returns void
language plpgsql
as $$
begin
  if target_test_session_id is null then
    raise exception 'cleanup_test_session requires test_session_id'
      using errcode = '22004';
  end if;

  if to_regclass('app.home_player_course_links') is not null
     and to_regclass('app.lesson_media') is not null then
    delete from app.home_player_course_links hpcl
    where hpcl.lesson_media_id in (
      select lm.id
      from app.lesson_media lm
      where coalesce(lm.is_test, false) = true
        and lm.test_session_id = target_test_session_id
    );
  end if;

  if to_regclass('app.home_player_uploads') is not null
     and to_regclass('app.media_assets') is not null then
    delete from app.home_player_uploads hpu
    where hpu.media_asset_id in (
      select ma.id
      from app.media_assets ma
      where ma.course_id in (
        select c.id
        from app.courses c
        where coalesce(c.is_test, false) = true
          and c.test_session_id = target_test_session_id
      )
      or ma.lesson_id in (
        select l.id
        from app.lessons l
        where coalesce(l.is_test, false) = true
          and l.test_session_id = target_test_session_id
      )
    );
  end if;

  if to_regclass('app.lesson_contents') is not null then
    delete from app.lesson_contents lc
    where lc.lesson_id in (
      select l.id
      from app.lessons l
      where coalesce(l.is_test, false) = true
        and l.test_session_id = target_test_session_id
    );
  end if;

  if to_regclass('app.course_enrollments') is not null then
    delete from app.course_enrollments ce
    where ce.course_id in (
      select c.id
      from app.courses c
      where coalesce(c.is_test, false) = true
        and c.test_session_id = target_test_session_id
    );
  end if;

  if to_regclass('app.lesson_media') is not null then
    delete from app.lesson_media lm
    where coalesce(lm.is_test, false) = true
      and lm.test_session_id = target_test_session_id;
  end if;

  if to_regclass('app.media_assets') is not null then
    delete from app.media_assets ma
    where ma.course_id in (
      select c.id
      from app.courses c
      where coalesce(c.is_test, false) = true
        and c.test_session_id = target_test_session_id
    )
    or ma.lesson_id in (
      select l.id
      from app.lessons l
      where coalesce(l.is_test, false) = true
        and l.test_session_id = target_test_session_id
    );
  end if;

  if to_regclass('app.lessons') is not null then
    delete from app.lessons l
    where coalesce(l.is_test, false) = true
      and l.test_session_id = target_test_session_id;
  end if;

  if to_regclass('app.courses') is not null then
    delete from app.courses c
    where coalesce(c.is_test, false) = true
      and c.test_session_id = target_test_session_id;
  end if;
end;
$$;
SQL

echo "==> Baseline replay complete."
