#!/usr/bin/env bash
set -euo pipefail

DB_URL="${SUPABASE_DB_URL:-${DATABASE_URL:-}}"
FAIL_ON_HOME_PLAYER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db-url)
      DB_URL="$2"
      shift 2
      ;;
    --allow-home-player)
      FAIL_ON_HOME_PLAYER=0
      shift
      ;;
    *)
      echo "baseline-runtime-drift: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$DB_URL" ]]; then
  echo "baseline-runtime-drift: DB URL missing (set SUPABASE_DB_URL, DATABASE_URL, or --db-url)" >&2
  exit 2
fi

run_sql() {
  PGOPTIONS="-c default_transaction_read_only=on" \
    psql "$DB_URL" -X -qAt -F $'\t' -v ON_ERROR_STOP=1 -c "$1"
}

scalar() {
  local query="$1"
  local value
  value="$(run_sql "$query")"
  printf '%s' "${value//$'\n'/}"
}

sample_ids() {
  local query="$1"
  local value
  value="$(run_sql "$query")"
  printf '%s' "${value//$'\n'/}"
}

lesson_count="$(scalar "select count(*) from app.lesson_media;")"
runtime_lesson_count="$(scalar "select count(*) from app.runtime_media where lesson_media_id is not null;")"

missing_projection_rows="$(scalar "
  select count(*)
  from app.lesson_media lm
  left join app.runtime_media rm on rm.lesson_media_id = lm.id
  where rm.id is null;
")"
missing_projection_sample="$(sample_ids "
  select coalesce(string_agg(lm.id::text, ', ' order by lm.id::text), '')
  from (
    select lm.id
    from app.lesson_media lm
    left join app.runtime_media rm on rm.lesson_media_id = lm.id
    where rm.id is null
    order by lm.id
    limit 10
  ) lm;
")"

duplicate_runtime_rows="$(scalar "
  select count(*)
  from (
    select lesson_media_id
    from app.runtime_media
    where lesson_media_id is not null
    group by lesson_media_id
    having count(*) > 1
  ) duplicates;
")"
duplicate_runtime_sample="$(sample_ids "
  select coalesce(string_agg(lesson_media_id::text, ', ' order by lesson_media_id::text), '')
  from (
    select lesson_media_id
    from app.runtime_media
    where lesson_media_id is not null
    group by lesson_media_id
    having count(*) > 1
    order by lesson_media_id
    limit 10
  ) duplicates;
")"

context_drift_rows="$(scalar "
  select count(*)
  from app.runtime_media rm
  join app.lesson_media lm on lm.id = rm.lesson_media_id
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  left join app.media_objects mo on mo.id = lm.media_id
  where rm.course_id is distinct from l.course_id
     or rm.teacher_id is distinct from coalesce(c.created_by, ma.owner_id, mo.owner_id);
")"
context_drift_sample="$(sample_ids "
  select coalesce(string_agg(rm.id::text, ', ' order by rm.id::text), '')
  from (
    select rm.id
    from app.runtime_media rm
    join app.lesson_media lm on lm.id = rm.lesson_media_id
    join app.lessons l on l.id = lm.lesson_id
    join app.courses c on c.id = l.course_id
    left join app.media_assets ma on ma.id = lm.media_asset_id
    left join app.media_objects mo on mo.id = lm.media_id
    where rm.course_id is distinct from l.course_id
       or rm.teacher_id is distinct from coalesce(c.created_by, ma.owner_id, mo.owner_id)
    order by rm.id
    limit 10
  ) rm;
")"

invalid_projection_state_rows="$(scalar "
  select count(*)
  from app.runtime_media rm
  join app.lesson_media lm on lm.id = rm.lesson_media_id
  join app.lessons l on l.id = lm.lesson_id
  join app.courses c on c.id = l.course_id
  left join app.media_assets ma on ma.id = lm.media_asset_id
  left join app.media_objects mo on mo.id = lm.media_id
  where rm.reference_type <> 'lesson_media'
     or rm.auth_scope <> 'lesson_course'
     or rm.fallback_policy <> app.runtime_media_lesson_fallback_policy(
          lm.kind,
          lm.media_asset_id,
          lm.media_id,
          lm.storage_path
        )
     or rm.course_id is distinct from l.course_id
     or rm.lesson_id is distinct from lm.lesson_id
     or rm.teacher_id is distinct from coalesce(c.created_by, ma.owner_id, mo.owner_id)
     or rm.media_asset_id is distinct from lm.media_asset_id
     or rm.media_object_id is distinct from lm.media_id
     or rm.legacy_storage_bucket is distinct from (
          case
            when nullif(trim(lm.storage_path), '') is not null
              then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
            else null
          end
        )
     or rm.legacy_storage_path is distinct from nullif(trim(lm.storage_path), '')
     or rm.kind is distinct from app.normalize_runtime_media_kind(lm.kind)
     or rm.active is distinct from app.runtime_media_kind_is_playback_capable(lm.kind);
")"
invalid_projection_state_sample="$(sample_ids "
  select coalesce(string_agg(rm.id::text, ', ' order by rm.id::text), '')
  from (
    select rm.id
    from app.runtime_media rm
    join app.lesson_media lm on lm.id = rm.lesson_media_id
    join app.lessons l on l.id = lm.lesson_id
    join app.courses c on c.id = l.course_id
    left join app.media_assets ma on ma.id = lm.media_asset_id
    left join app.media_objects mo on mo.id = lm.media_id
    where rm.reference_type <> 'lesson_media'
       or rm.auth_scope <> 'lesson_course'
       or rm.fallback_policy <> app.runtime_media_lesson_fallback_policy(
            lm.kind,
            lm.media_asset_id,
            lm.media_id,
            lm.storage_path
          )
       or rm.course_id is distinct from l.course_id
       or rm.lesson_id is distinct from lm.lesson_id
       or rm.teacher_id is distinct from coalesce(c.created_by, ma.owner_id, mo.owner_id)
       or rm.media_asset_id is distinct from lm.media_asset_id
       or rm.media_object_id is distinct from lm.media_id
       or rm.legacy_storage_bucket is distinct from (
            case
              when nullif(trim(lm.storage_path), '') is not null
                then coalesce(nullif(trim(lm.storage_bucket), ''), 'lesson-media')
              else null
            end
          )
       or rm.legacy_storage_path is distinct from nullif(trim(lm.storage_path), '')
       or rm.kind is distinct from app.normalize_runtime_media_kind(lm.kind)
       or rm.active is distinct from app.runtime_media_kind_is_playback_capable(lm.kind)
    order by rm.id
    limit 10
  ) rm;
")"

unexpected_runtime_rows="$(scalar "
  select count(*)
  from app.runtime_media rm
  where rm.lesson_media_id is null
     or rm.reference_type <> 'lesson_media'
     or rm.home_player_upload_id is not null;
")"
unexpected_runtime_sample="$(sample_ids "
  select coalesce(string_agg(rm.id::text, ', ' order by rm.id::text), '')
  from (
    select rm.id
    from app.runtime_media rm
    where rm.lesson_media_id is null
       or rm.reference_type <> 'lesson_media'
       or rm.home_player_upload_id is not null
    order by rm.id
    limit 10
  ) rm;
")"

home_player_rows="$(scalar "
  select count(*)
  from app.runtime_media
  where home_player_upload_id is not null;
")"

printf 'baseline-runtime-drift: lesson_media_count=%s\n' "$lesson_count"
printf 'baseline-runtime-drift: runtime_lesson_count=%s\n' "$runtime_lesson_count"
printf 'baseline-runtime-drift: missing_projection_rows=%s\n' "$missing_projection_rows"
printf 'baseline-runtime-drift: duplicate_runtime_rows=%s\n' "$duplicate_runtime_rows"
printf 'baseline-runtime-drift: context_drift_rows=%s\n' "$context_drift_rows"
printf 'baseline-runtime-drift: invalid_projection_state_rows=%s\n' "$invalid_projection_state_rows"
printf 'baseline-runtime-drift: unexpected_runtime_rows=%s\n' "$unexpected_runtime_rows"
printf 'baseline-runtime-drift: home_player_rows=%s\n' "$home_player_rows"

failures=()
[[ "$lesson_count" == "$runtime_lesson_count" ]] || failures+=("row_count_mismatch lesson_media=$lesson_count runtime_media=$runtime_lesson_count")
[[ "$missing_projection_rows" == "0" ]] || failures+=("missing_projection_rows=$missing_projection_rows sample=[$missing_projection_sample]")
[[ "$duplicate_runtime_rows" == "0" ]] || failures+=("duplicate_runtime_rows=$duplicate_runtime_rows sample=[$duplicate_runtime_sample]")
[[ "$context_drift_rows" == "0" ]] || failures+=("context_drift_rows=$context_drift_rows sample=[$context_drift_sample]")
[[ "$invalid_projection_state_rows" == "0" ]] || failures+=("invalid_projection_state_rows=$invalid_projection_state_rows sample=[$invalid_projection_state_sample]")
[[ "$unexpected_runtime_rows" == "0" ]] || failures+=("unexpected_runtime_rows=$unexpected_runtime_rows sample=[$unexpected_runtime_sample]")
if [[ "$FAIL_ON_HOME_PLAYER" == "1" ]]; then
  [[ "$home_player_rows" == "0" ]] || failures+=("home_player_rows=$home_player_rows")
fi

if [[ "${#failures[@]}" -gt 0 ]]; then
  printf 'baseline-runtime-drift: FAIL\n' >&2
  for failure in "${failures[@]}"; do
    printf '  - %s\n' "$failure" >&2
  done
  exit 1
fi

printf 'baseline-runtime-drift: PASS\n'
