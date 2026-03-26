#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MIGRATIONS_DIR="$ROOT_DIR/supabase/migrations"
ORDERED_MIGRATIONS=(
  "0001_base_schemas.sql"
  "0002_base_types.sql"
  "0003_core_tables.sql"
  "0004_media_runtime.sql"
  "0005_access.sql"
  "0006_commerce.sql"
  "0007_memberships_events.sql"
  "0008_phase3_5_access_commerce.sql"
)

REQUIRED_TABLES=(
  "app.profiles"
  "app.media_objects"
  "app.courses"
  "app.lessons"
  "app.lesson_media"
  "app.media_assets"
  "app.home_player_uploads"
  "app.runtime_media"
  "app.memberships"
  "public.subscription_plans"
  "public.subscriptions"
  "app.events"
  "app.live_events"
  "app.seminars"
  "app.event_participants"
  "app.live_event_registrations"
  "app.seminar_attendees"
  "app.entitlements"
  "app.enrollments"
  "app.orders"
  "app.payments"
  "app.payment_events"
)

for f in "${ORDERED_MIGRATIONS[@]}"; do
  if [[ ! -f "$MIGRATIONS_DIR/$f" ]]; then
    echo "Missing migration file: $MIGRATIONS_DIR/$f" >&2
    exit 1
  fi
done

supabase db start >/dev/null
supabase db reset --no-seed

DB_URL="$(supabase status -o env | sed -n 's/^DB_URL="\(.*\)"$/\1/p')"
if [[ -z "$DB_URL" ]]; then
  echo "Could not resolve DB_URL from supabase status." >&2
  exit 1
fi

TABLE_LIST_SQL=""
for t in "${REQUIRED_TABLES[@]}"; do
  TABLE_LIST_SQL+="'${t}',"
done
TABLE_LIST_SQL="${TABLE_LIST_SQL%,}"

missing_tables="$({
  echo "WITH required(table_name) AS (VALUES ($(echo "$TABLE_LIST_SQL" | sed "s/,/),(/g" | sed "s/^/(/" | sed "s/$/)/")))"
  echo "SELECT table_name FROM required"
  echo "WHERE to_regclass(table_name) IS NULL;"
} | psql "$DB_URL" -v ON_ERROR_STOP=1 -At)"

if [[ -n "$missing_tables" ]]; then
  echo "Missing required tables after bootstrap:" >&2
  echo "$missing_tables" >&2
  exit 1
fi

schema_a="$(mktemp /tmp/aveli_baseline_schema_a_XXXXXX.sql)"
schema_b="$(mktemp /tmp/aveli_baseline_schema_b_XXXXXX.sql)"
norm_a="$(mktemp /tmp/aveli_baseline_schema_a_norm_XXXXXX.sql)"
norm_b="$(mktemp /tmp/aveli_baseline_schema_b_norm_XXXXXX.sql)"
trap 'rm -f "$schema_a" "$schema_b" "$norm_a" "$norm_b"' EXIT

pg_dump "$DB_URL" --schema-only --no-owner --no-privileges > "$schema_a"
supabase db reset --no-seed
pg_dump "$DB_URL" --schema-only --no-owner --no-privileges > "$schema_b"

# Ignore pg_dump session randomizers that are not schema content.
grep -vE '^\\(un)?restrict ' "$schema_a" > "$norm_a"
grep -vE '^\\(un)?restrict ' "$schema_b" > "$norm_b"

if ! diff -u "$norm_a" "$norm_b" >/dev/null; then
  echo "Replay verification failed: schema differs after reset replay." >&2
  diff -u "$norm_a" "$norm_b" || true
  exit 1
fi

echo "Baseline bootstrap successful."
echo "All required tables exist."
echo "Replay produced identical schema."
