#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/backend/supabase/baseline_slots.lock.json"
BASELINE_DIR="$ROOT_DIR/backend/supabase/baseline_slots"
CHECKER="$ROOT_DIR/ops/check_baseline_slots.py"
AUTH_SUBSTRATE_SQL="$ROOT_DIR/ops/sql/minimal_auth_substrate.sql"
DRIFT_CHECK="$ROOT_DIR/backend/scripts/runtime_media_baseline_drift_check.sh"

PROTECTED_SLOTS=(
  "0001_foundation_auth_profiles.sql"
  "0002_access_teacher_roles.sql"
  "0003_courses_core.sql"
  "0004_enrollments_core.sql"
  "0005_lessons_core.sql"
  "0006_access_grants_core.sql"
  "0007_media_objects_core.sql"
  "0008_lesson_media_core.sql"
  "0009_courses_enrolled_read_alignment.sql"
  "0010_media_assets_core.sql"
  "0011_lesson_media_asset_bridge.sql"
  "0012_runtime_media_lesson_projection_core.sql"
  "0013_runtime_media_lesson_sync_core.sql"
  "0014_runtime_media_context_sync_core.sql"
  "0015_runtime_media_lesson_backfill_core.sql"
)

resolve_db_url() {
  if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
    printf '%s\n' "$SUPABASE_DB_URL"
    return 0
  fi
  if [[ -n "${DATABASE_URL:-}" ]]; then
    printf '%s\n' "$DATABASE_URL"
    return 0
  fi
  if command -v supabase >/dev/null 2>&1; then
    local status_env
    status_env="$(supabase status -o env)"
    local db_url
    db_url="$(printf '%s\n' "$status_env" | awk -F= '/^DB_URL=/{gsub(/"/,"",$2); print $2}')"
    if [[ -n "$db_url" ]]; then
      printf '%s\n' "$db_url"
      return 0
    fi
  fi
  return 1
}

derive_urls() {
  python3 - <<'PY' "$1" "$2"
from urllib.parse import urlparse, urlunparse
import sys

base_url = sys.argv[1]
scratch_db = sys.argv[2]
parsed = urlparse(base_url)
maintenance = parsed._replace(path="/postgres")
scratch = parsed._replace(path=f"/{scratch_db}")
print(urlunparse(maintenance))
print(urlunparse(scratch))
PY
}

DB_URL="$(resolve_db_url || true)"
if [[ -z "$DB_URL" ]]; then
  echo "baseline-replay: unable to resolve DB URL from SUPABASE_DB_URL, DATABASE_URL, or supabase status" >&2
  exit 2
fi

python3 "$CHECKER" --manifest "$MANIFEST_PATH" --baseline-dir "$BASELINE_DIR"

SCRATCH_DB="baseline_protection_$(date +%s)_$$"
mapfile -t DERIVED_URLS < <(derive_urls "$DB_URL" "$SCRATCH_DB")
MAINTENANCE_URL="${DERIVED_URLS[0]}"
SCRATCH_URL="${DERIVED_URLS[1]}"

cleanup() {
  if [[ "${BASELINE_KEEP_SCRATCH_DB:-0}" == "1" ]]; then
    echo "baseline-replay: keeping scratch_db=$SCRATCH_DB for inspection"
    return 0
  fi
  psql "$MAINTENANCE_URL" -X -q -c "drop database if exists \"$SCRATCH_DB\" with (force);" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql "$MAINTENANCE_URL" -X -q -v ON_ERROR_STOP=1 -c "create database \"$SCRATCH_DB\";"
psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$AUTH_SUBSTRATE_SQL" >/dev/null

echo "baseline-replay: scratch_db=$SCRATCH_DB"
echo "baseline-replay: scratch_url=$SCRATCH_URL"
echo "baseline-replay: applying 0001-0012"

for slot in "${PROTECTED_SLOTS[@]:0:12}"; do
  psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$BASELINE_DIR/$slot"
  echo "baseline-replay: applied $slot"
done

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 <<'SQL'
insert into auth.users (id, email)
values
  ('11111111-1111-4111-8111-111111111111', 'owner-one@example.com'),
  ('e1b0de33-16b7-4ec8-97f0-dedffcc7061d', 'owner-two@example.com'),
  ('22222222-2222-4222-8222-222222222222', 'enrolled@example.com'),
  ('33333333-3333-4333-8333-333333333333', 'outsider@example.com');
SQL

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 <<'SQL'
insert into app.profiles (user_id, email, display_name, role, role_v2)
values
  ('11111111-1111-4111-8111-111111111111', 'owner-one@example.com', 'Owner One', 'teacher', 'teacher'),
  ('e1b0de33-16b7-4ec8-97f0-dedffcc7061d', 'owner-two@example.com', 'Owner Two', 'teacher', 'teacher'),
  ('22222222-2222-4222-8222-222222222222', 'enrolled@example.com', 'Enrolled', 'student', 'user'),
  ('33333333-3333-4333-8333-333333333333', 'outsider@example.com', 'Outsider', 'student', 'user');

insert into app.courses (id, slug, title, created_by, is_published)
values
  ('43000000-0000-0000-0000-000000000001', 'baseline-protection-a', 'Baseline Protection A', '11111111-1111-4111-8111-111111111111', true),
  ('43000000-0000-0000-0000-000000000002', 'baseline-protection-b', 'Baseline Protection B', 'e1b0de33-16b7-4ec8-97f0-dedffcc7061d', true),
  ('43000000-0000-0000-0000-000000000003', 'baseline-protection-stale', 'Baseline Protection Stale', '11111111-1111-4111-8111-111111111111', true);

insert into app.lessons (id, title, course_id, position, is_intro)
values
  ('43000000-0000-0000-0000-000000000011', 'Lesson A', '43000000-0000-0000-0000-000000000001', 0, false),
  ('43000000-0000-0000-0000-000000000012', 'Lesson B', '43000000-0000-0000-0000-000000000002', 0, false);

insert into app.enrollments (user_id, course_id, status, source)
values
  ('22222222-2222-4222-8222-222222222222', '43000000-0000-0000-0000-000000000001', 'active', 'purchase'),
  ('22222222-2222-4222-8222-222222222222', '43000000-0000-0000-0000-000000000002', 'active', 'purchase');

insert into app.media_assets (
  id, owner_id, course_id, lesson_id, media_type, ingest_format,
  original_object_path, original_content_type, original_filename,
  original_size_bytes, storage_bucket, streaming_object_path,
  streaming_format, duration_seconds, codec, state, purpose, streaming_storage_bucket
)
values
(
  '43000000-0000-0000-0000-000000000101', '11111111-1111-4111-8111-111111111111',
  '43000000-0000-0000-0000-000000000001', '43000000-0000-0000-0000-000000000011',
  'audio', 'wav', 'media/source/audio-1.wav', 'audio/wav', 'audio-1.wav',
  2048, 'course-media', 'media/derived/audio-1.mp3',
  'mp3', 95, 'mp3', 'ready', 'lesson_audio', 'course-media'
),
(
  '43000000-0000-0000-0000-000000000102', 'e1b0de33-16b7-4ec8-97f0-dedffcc7061d',
  '43000000-0000-0000-0000-000000000002', '43000000-0000-0000-0000-000000000012',
  'image', 'png', 'media/source/image-1.png', 'image/png', 'image-1.png',
  4096, 'course-media', 'media/derived/image-1.png',
  'png', null, 'png', 'ready', 'lesson_media', 'course-media'
);

insert into app.media_objects (
  id, owner_id, storage_path, storage_bucket, content_type, byte_size, original_name
)
values (
  '43000000-0000-0000-0000-000000000201', '11111111-1111-4111-8111-111111111111',
  'courses/43000000-0000-0000-0000-000000000001/lessons/43000000-0000-0000-0000-000000000011/docs/material.pdf',
  'course-media', 'application/pdf', 1024, 'material.pdf'
);

insert into app.lesson_media (
  id, lesson_id, kind, position, media_id, media_asset_id, storage_path, storage_bucket, duration_seconds
)
values
(
  '43000000-0000-0000-0000-000000000301', '43000000-0000-0000-0000-000000000011',
  'audio', 0, null, '43000000-0000-0000-0000-000000000101', null, 'lesson-media', 95
),
(
  '43000000-0000-0000-0000-000000000302', '43000000-0000-0000-0000-000000000011',
  'pdf', 1, '43000000-0000-0000-0000-000000000201', null,
  'courses/43000000-0000-0000-0000-000000000001/lessons/43000000-0000-0000-0000-000000000011/docs/material.pdf',
  'course-media', null
),
(
  '43000000-0000-0000-0000-000000000303', '43000000-0000-0000-0000-000000000012',
  'image', 0, null, '43000000-0000-0000-0000-000000000102', null, 'lesson-media', null
);

insert into app.runtime_media (
  id, reference_type, auth_scope, fallback_policy, lesson_media_id,
  home_player_upload_id, teacher_id, course_id, lesson_id, media_asset_id,
  media_object_id, legacy_storage_bucket, legacy_storage_path, kind, active,
  created_at, updated_at
)
values (
  '43000000-0000-0000-0000-000000000401', 'lesson_media', 'lesson_course', 'legacy_only',
  '43000000-0000-0000-0000-000000000303', null,
  '11111111-1111-4111-8111-111111111111', '43000000-0000-0000-0000-000000000003',
  '43000000-0000-0000-0000-000000000012', null, null,
  'lesson-media', 'stale/path.png', 'audio', false, now(), now()
);
SQL

echo "baseline-replay: seed complete"
echo "baseline-replay: applying 0013-0015"

for slot in "${PROTECTED_SLOTS[@]:12}"; do
  psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -f "$BASELINE_DIR/$slot"
  echo "baseline-replay: applied $slot"
done

echo "baseline-replay: verifying backfill outcomes"
lesson_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from app.lesson_media;")"
runtime_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from app.runtime_media where lesson_media_id is not null;")"
duplicate_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from (select lesson_media_id from app.runtime_media where lesson_media_id is not null group by lesson_media_id having count(*) > 1) d;")"
document_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select kind, active::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000302'::uuid;")"
audio_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select kind, active::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000301'::uuid;")"
stale_image_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select id::text, teacher_id::text, course_id::text, media_asset_id::text, kind, active::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000303'::uuid;")"

[[ "$lesson_count" == "3" ]] || { echo "baseline-replay: expected 3 lesson_media rows, got $lesson_count" >&2; exit 1; }
[[ "$runtime_count" == "3" ]] || { echo "baseline-replay: expected 3 runtime_media lesson rows, got $runtime_count" >&2; exit 1; }
[[ "$duplicate_count" == "0" ]] || { echo "baseline-replay: duplicate runtime_media rows detected after backfill" >&2; exit 1; }
[[ "$document_state" == "document|false" ]] || { echo "baseline-replay: document row invariant failed: $document_state" >&2; exit 1; }
[[ "$audio_state" == "audio|true" ]] || { echo "baseline-replay: audio row invariant failed: $audio_state" >&2; exit 1; }
[[ "$stale_image_state" == "43000000-0000-0000-0000-000000000401|e1b0de33-16b7-4ec8-97f0-dedffcc7061d|43000000-0000-0000-0000-000000000002|43000000-0000-0000-0000-000000000102|image|true" ]] || {
  echo "baseline-replay: stale projection repair failed: $stale_image_state" >&2
  exit 1
}

echo "baseline-replay: verifying live sync behavior"
audio_runtime_id="$(psql "$SCRATCH_URL" -X -qAt -c "select id::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000301'::uuid;")"
stale_runtime_id="$(psql "$SCRATCH_URL" -X -qAt -c "select id::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000303'::uuid;")"

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -c "update app.lesson_media set kind = 'pdf' where id = '43000000-0000-0000-0000-000000000301'::uuid;" >/dev/null
audio_document_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select id::text, kind, active::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000301'::uuid;")"
[[ "$audio_document_state" == "$audio_runtime_id|document|false" ]] || {
  echo "baseline-replay: lesson_media->document sync failed: $audio_document_state" >&2
  exit 1
}

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -c "update app.lesson_media set kind = 'audio' where id = '43000000-0000-0000-0000-000000000301'::uuid;" >/dev/null
audio_reactivated_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select id::text, kind, active::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000301'::uuid;")"
[[ "$audio_reactivated_state" == "$audio_runtime_id|audio|true" ]] || {
  echo "baseline-replay: lesson_media reactivation sync failed: $audio_reactivated_state" >&2
  exit 1
}

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -c "update app.courses set created_by = '11111111-1111-4111-8111-111111111111'::uuid where id = '43000000-0000-0000-0000-000000000002'::uuid;" >/dev/null
teacher_sync_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select id::text, teacher_id::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000303'::uuid;")"
[[ "$teacher_sync_state" == "$stale_runtime_id|11111111-1111-4111-8111-111111111111" ]] || {
  echo "baseline-replay: course created_by sync failed: $teacher_sync_state" >&2
  exit 1
}

psql "$SCRATCH_URL" -X -q -v ON_ERROR_STOP=1 -c "update app.lessons set course_id = '43000000-0000-0000-0000-000000000001'::uuid, position = 1 where id = '43000000-0000-0000-0000-000000000012'::uuid;" >/dev/null
course_sync_state="$(psql "$SCRATCH_URL" -X -qAt -F '|' -c "select id::text, course_id::text from app.runtime_media where lesson_media_id = '43000000-0000-0000-0000-000000000303'::uuid;")"
[[ "$course_sync_state" == "$stale_runtime_id|43000000-0000-0000-0000-000000000001" ]] || {
  echo "baseline-replay: lesson course_id sync failed: $course_sync_state" >&2
  exit 1
}

echo "baseline-replay: running drift checks read-only"
bash "$DRIFT_CHECK" --db-url "$SCRATCH_URL"

echo "baseline-replay: verifying RLS"
enrolled_visible="$(psql "$SCRATCH_URL" -X -qAt <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select count(*)
from app.runtime_media rm
join app.lesson_media lm on lm.id = rm.lesson_media_id
where rm.active = true;
reset role;
SQL
)"
outsider_visible="$(psql "$SCRATCH_URL" -X -qAt <<'SQL'
set role authenticated;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', false);
select set_config('request.jwt.claim.role', 'authenticated', false);
select count(*)
from app.runtime_media rm
join app.lesson_media lm on lm.id = rm.lesson_media_id
where rm.active = true;
reset role;
SQL
)"
service_visible="$(psql "$SCRATCH_URL" -X -qAt <<'SQL'
set role service_role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claim.role', 'service_role', false);
select count(*)
from app.runtime_media rm
join app.lesson_media lm on lm.id = rm.lesson_media_id;
reset role;
SQL
)"

[[ "$(printf '%s\n' "$enrolled_visible" | tail -n 1)" == "2" ]] || {
  echo "baseline-replay: enrolled RLS check failed: $enrolled_visible" >&2
  exit 1
}
[[ "$(printf '%s\n' "$outsider_visible" | tail -n 1)" == "0" ]] || {
  echo "baseline-replay: outsider RLS check failed: $outsider_visible" >&2
  exit 1
}
[[ "$(printf '%s\n' "$service_visible" | tail -n 1)" == "3" ]] || {
  echo "baseline-replay: service_role RLS check failed: $service_visible" >&2
  exit 1
}

echo "baseline-replay: verifying runtime trigger surface"
runtime_sync_triggers="$(psql "$SCRATCH_URL" -X -qAt -c "select string_agg(tgname, ',' order by tgname) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and not t.tgisinternal and tgname like 'trg_runtime_media_sync%';")"
runtime_sync_trigger_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and not t.tgisinternal and tgname like 'trg_runtime_media_sync%';")"
runtime_media_trigger_count="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and c.relname = 'runtime_media' and not t.tgisinternal;")"
unexpected_runtime_surface="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'app' and proname in ('touch_home_player_uploads','sync_runtime_media_home_player_upload_trigger','upsert_runtime_media_for_home_player_upload');")"
home_player_table_present="$(psql "$SCRATCH_URL" -X -qAt -c "select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'app' and c.relname = 'home_player_uploads';")"

[[ "$runtime_sync_trigger_count" == "3" ]] || { echo "baseline-replay: expected 3 runtime sync triggers, got $runtime_sync_trigger_count" >&2; exit 1; }
[[ "$runtime_sync_triggers" == "trg_runtime_media_sync_course_context,trg_runtime_media_sync_lesson_context,trg_runtime_media_sync_lesson_media" ]] || {
  echo "baseline-replay: runtime sync trigger set mismatch: $runtime_sync_triggers" >&2
  exit 1
}
[[ "$runtime_media_trigger_count" == "0" ]] || { echo "baseline-replay: runtime_media table has unexpected triggers" >&2; exit 1; }
[[ "$unexpected_runtime_surface" == "0" ]] || { echo "baseline-replay: unexpected home-player runtime functions present" >&2; exit 1; }
[[ "$home_player_table_present" == "0" ]] || { echo "baseline-replay: unexpected home_player table present in baseline replay" >&2; exit 1; }

echo "baseline-replay: PASS"
