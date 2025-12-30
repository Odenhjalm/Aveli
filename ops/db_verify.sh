#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/db_env.sh"

require_command psql

if [[ -z "${DB_URL:-}" ]]; then
  echo "DB_URL is required for verification." >&2
  exit 1
fi

if [[ "${DB_TARGET}" == "remote" ]]; then
  require_remote_readonly_guards
fi

CHECKS_TMP="$(mktemp)"
PASS_COUNT=0
FAIL_COUNT=0

record_check() {
  local status="$1"
  local name="$2"
  local detail="$3"
  if [[ "${status}" == "PASS" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  if [[ -n "${detail}" ]]; then
    echo "- ${status}: ${name} - ${detail}" >> "${CHECKS_TMP}"
  else
    echo "- ${status}: ${name}" >> "${CHECKS_TMP}"
  fi
}

psql_scalar() {
  PSQLRC=/dev/null psql -X "${DB_URL}" -q -t -A -v ON_ERROR_STOP=1 -c "$1"
}

REQUIRED_EXTENSIONS=(pgcrypto "uuid-ossp")
REQUIRED_ENUMS=(
  app.service_status
)
REQUIRED_TABLES=(
  app.activities
  app.activities_feed
  app.auth_events
  app.refresh_tokens
  app.profiles
  app.courses
  app.modules
  app.lessons
  app.lesson_media
  app.media_objects
  app.enrollments
  app.certificates
  app.course_quizzes
  app.quiz_questions
  app.services
  app.sessions
  app.session_slots
  app.orders
  app.payments
  app.memberships
  app.subscriptions
  app.billing_logs
  app.payment_events
  app.course_entitlements
  app.course_bundles
  app.course_bundle_courses
  app.stripe_customers
  app.course_display_priorities
  app.teachers
  app.teacher_profile_media
  app.teacher_approvals
  app.teacher_payout_methods
  app.seminars
  app.seminar_sessions
  app.seminar_attendees
  app.seminar_recordings
  app.livekit_webhook_jobs
  app.app_config
  storage.buckets
  storage.objects
)

RLS_TABLES=(
  app.profiles
  app.courses
  app.lessons
  app.lesson_media
  app.enrollments
  app.memberships
  app.subscriptions
  app.orders
  app.payments
  app.seminars
  app.seminar_attendees
  app.seminar_sessions
  storage.objects
)

REQUIRED_FUNCTIONS=(
  app.set_updated_at
  app.touch_course_display_priorities
  app.touch_teacher_profile_media
  app.touch_course_entitlements
  app.touch_livekit_webhook_jobs
  app.is_admin
  app.is_seminar_host
  app.is_seminar_attendee
  app.can_access_seminar
  app.grade_quiz_and_issue_certificate
)

REQUIRED_TRIGGERS=(
  "trg_courses_touch|app.courses"
  "trg_modules_touch|app.modules"
  "trg_lessons_touch|app.lessons"
  "trg_services_touch|app.services"
  "trg_orders_touch|app.orders"
  "trg_payments_touch|app.payments"
  "trg_seminars_touch|app.seminars"
  "trg_profiles_touch|app.profiles"
  "trg_teacher_approvals_touch|app.teacher_approvals"
  "trg_teacher_payout_methods_touch|app.teacher_payout_methods"
  "trg_teachers_touch|app.teachers"
  "trg_sessions_touch|app.sessions"
  "trg_session_slots_touch|app.session_slots"
  "trg_course_entitlements_touch|app.course_entitlements"
  "trg_course_display_priorities_touch|app.course_display_priorities"
  "trg_teacher_profile_media_touch|app.teacher_profile_media"
  "trg_seminar_sessions_touch|app.seminar_sessions"
  "trg_seminar_recordings_touch|app.seminar_recordings"
  "trg_livekit_webhook_jobs_touch|app.livekit_webhook_jobs"
)

REQUIRED_COLUMNS=(
  "app.profiles:user_id"
  "app.profiles:role_v2"
  "app.profiles:display_name"
  "app.profiles:is_admin"
  "app.courses:id"
  "app.courses:slug"
  "app.courses:is_published"
  "app.courses:created_by"
  "app.lesson_media:id"
  "app.lesson_media:lesson_id"
  "app.lesson_media:storage_path"
  "app.lesson_media:storage_bucket"
  "app.media_objects:id"
  "app.media_objects:storage_path"
  "app.media_objects:storage_bucket"
  "app.media_objects:content_type"
  "app.memberships:user_id"
  "app.memberships:status"
  "app.memberships:stripe_subscription_id"
  "app.memberships:stripe_customer_id"
  "app.subscriptions:user_id"
  "app.subscriptions:subscription_id"
  "app.subscriptions:status"
  "app.orders:id"
  "app.orders:user_id"
  "app.orders:status"
  "app.orders:amount_cents"
  "app.orders:currency"
  "app.payments:id"
  "app.payments:order_id"
  "app.payments:status"
  "app.payments:amount_cents"
  "app.seminars:id"
  "app.seminars:host_id"
  "app.seminars:status"
  "app.seminars:livekit_room"
  "app.seminar_sessions:id"
  "app.seminar_sessions:seminar_id"
  "app.seminar_sessions:status"
  "app.seminar_sessions:livekit_room"
  "app.course_entitlements:user_id"
  "app.course_entitlements:course_slug"
  "app.livekit_webhook_jobs:id"
  "app.livekit_webhook_jobs:payload"
  "app.livekit_webhook_jobs:attempt"
  "app.livekit_webhook_jobs:next_run_at"
  "app.stripe_customers:user_id"
  "app.stripe_customers:customer_id"
)

for ext in "${REQUIRED_EXTENSIONS[@]}"; do
  exists=$(psql_scalar "select 1 from pg_extension where extname='${ext}';")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "extension ${ext}" ""
  else
    record_check "FAIL" "extension ${ext}" "missing"
  fi
done

for enum in "${REQUIRED_ENUMS[@]}"; do
  schema="${enum%%.*}"
  name="${enum#*.}"
  exists=$(psql_scalar "select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='${schema}' and t.typname='${name}' and t.typtype='e';")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "enum ${enum}" ""
  else
    record_check "FAIL" "enum ${enum}" "missing"
  fi
done

for table in "${REQUIRED_TABLES[@]}"; do
  exists=$(psql_scalar "select to_regclass('${table}');")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "table ${table}" ""
  else
    record_check "FAIL" "table ${table}" "missing"
  fi
done

for entry in "${REQUIRED_COLUMNS[@]}"; do
  schema_table="${entry%%:*}"
  column="${entry#*:}"
  schema="${schema_table%%.*}"
  table="${schema_table#*.}"
  exists=$(psql_scalar "select 1 from information_schema.columns where table_schema='${schema}' and table_name='${table}' and column_name='${column}';")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "column ${schema_table}.${column}" ""
  else
    record_check "FAIL" "column ${schema_table}.${column}" "missing"
  fi
done

for func in "${REQUIRED_FUNCTIONS[@]}"; do
  schema="${func%%.*}"
  name="${func#*.}"
  exists=$(psql_scalar "select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='${schema}' and p.proname='${name}';")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "function ${func}" ""
  else
    record_check "FAIL" "function ${func}" "missing"
  fi
done

for trigger_entry in "${REQUIRED_TRIGGERS[@]}"; do
  trigger_name="${trigger_entry%%|*}"
  table_name="${trigger_entry#*|}"
  schema="${table_name%%.*}"
  table="${table_name#*.}"
  exists=$(psql_scalar "select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='${schema}' and c.relname='${table}' and t.tgname='${trigger_name}' and not t.tgisinternal;")
  if [[ -n "${exists}" ]]; then
    record_check "PASS" "trigger ${trigger_name} on ${table_name}" ""
  else
    record_check "FAIL" "trigger ${trigger_name} on ${table_name}" "missing"
  fi
done

for table in "${RLS_TABLES[@]}"; do
  schema="${table%%.*}"
  name="${table#*.}"
  rls=$(psql_scalar "select relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='${schema}' and c.relname='${name}';")
  if [[ "${rls}" == "t" ]]; then
    record_check "PASS" "RLS enabled ${table}" ""
  else
    record_check "FAIL" "RLS enabled ${table}" "not enabled"
  fi
  policy_count=$(psql_scalar "select count(*) from pg_policies where schemaname='${schema}' and tablename='${name}';")
  if [[ "${policy_count}" != "0" ]]; then
    record_check "PASS" "policies ${table}" "count=${policy_count}"
  else
    record_check "FAIL" "policies ${table}" "none"
  fi
done

public_buckets=$(psql_scalar "select coalesce(string_agg(id, ',' order by id), '') from storage.buckets where public is true;")
if [[ "${public_buckets}" == "public-media" ]]; then
  record_check "PASS" "storage public buckets" "${public_buckets}"
else
  record_check "FAIL" "storage public buckets" "expected public-media only, got '${public_buckets}'"
fi

anon_storage_policies=$(psql_scalar "select count(*) from pg_policies where schemaname='storage' and tablename='objects' and 'anon' = any(roles) and (qual is null or qual not ilike '%public-media%');")
if [[ "${anon_storage_policies}" == "0" ]]; then
  record_check "PASS" "storage anon policies" "no unexpected anon access"
else
  record_check "FAIL" "storage anon policies" "${anon_storage_policies} policies allow anon without public-media guard"
fi

REPORT_PATH="${REPO_ROOT}/docs/ops/DB_REPAIR_REPORT.md"
NOW_UTC=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
MASKED_DB_URL=$(mask_db_url "${DB_URL}")

cat <<EOF_REPORT > "${REPORT_PATH}"
# DB Repair Report

## Summary
- Status: **${FAIL_COUNT} FAIL / ${PASS_COUNT} PASS**
- Target: ${DB_TARGET}
- Timestamp: ${NOW_UTC}
- Database: ${MASKED_DB_URL}

## Source of truth
- Canonical migrations: \`supabase/migrations/*.sql\`
- Canonical apply path: \`backend/scripts/apply_supabase_migrations.sh\`

## Repairs applied
- See git history and ops scripts for applied fixes.

## Verification results
EOF_REPORT

cat "${CHECKS_TMP}" >> "${REPORT_PATH}"

cat <<EOF_REPORT >> "${REPORT_PATH}"

## Notes
- Remote verification requires allowlisted project refs.
- This report is generated by \`ops/db_verify.sh\`.
EOF_REPORT

rm -f "${CHECKS_TMP}"

if [[ "${FAIL_COUNT}" -ne 0 ]]; then
  exit 2
fi
