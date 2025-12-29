#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="${1:-${ENV_PROFILE:-dev}}"

ENV_FILE="${ROOT}/backend/.env"
if [[ "$PROFILE" == "staging" && -f "${ROOT}/backend/.env.staging" ]]; then
  ENV_FILE="${ROOT}/backend/.env.staging"
elif [[ "$PROFILE" == "prod" && -f "${ROOT}/backend/.env.production" ]]; then
  ENV_FILE="${ROOT}/backend/.env.production"
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

BASE_URL="${API_BASE_URL:-http://127.0.0.1:8000}"
READONLY_PGOPTIONS="-c default_transaction_read_only=on"

section() {
  echo ""
  echo "== $1 =="
}

run_or_warn() {
  local label="$1"
  shift
  if ! "$@"; then
    echo "WARN: $label failed (command: $*)"
  fi
}

normalize_list() {
  local raw="$1"
  printf "%s" "$raw" | tr ', ' '\n' | sed '/^$/d' | sort
}

join_lines() {
  if [[ -z "$1" ]]; then
    echo "(none)"
    return
  fi
  printf "%s\n" "$1" | paste -sd ", " -
}

is_local_db_url() {
  case "$1" in
    *localhost*|*127.0.0.1*|*::1*) return 0 ;;
    *) return 1 ;;
  esac
}

build_in_list() {
  local lines="$1"
  local out=""
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ ! "$name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
      echo "Invalid bucket name for SQL: $name" >&2
      return 1
    fi
    out+="'$name',"
  done <<< "$lines"
  printf "%s" "${out%,}"
}

section "Env status (profile)"
if [[ -f "$ENV_FILE" ]]; then
  echo "Profile: $PROFILE"
  echo "Env file: $(basename "$ENV_FILE")"
else
  echo "Profile: $PROFILE"
  echo "Env file: (missing)"
fi

section "Backend health"
run_or_warn "healthz" curl -fsS "${BASE_URL%/}/healthz"
run_or_warn "readyz" curl -fsS "${BASE_URL%/}/readyz"

section "Storage bucket visibility"
if ! command -v psql >/dev/null 2>&1; then
  echo "Skip storage check (psql missing)"
  exit 0
fi
if [[ -z "${SUPABASE_DB_URL:-}" ]]; then
  echo "Skip storage check (SUPABASE_DB_URL missing)"
  exit 0
fi
if [[ -z "${EXPECTED_PUBLIC_BUCKETS:-}" || -z "${EXPECTED_PRIVATE_BUCKETS:-}" ]]; then
  echo "Missing EXPECTED_PUBLIC_BUCKETS or EXPECTED_PRIVATE_BUCKETS."
  echo "Example:"
  echo "  EXPECTED_PUBLIC_BUCKETS=public-media,brand"
  echo "  EXPECTED_PRIVATE_BUCKETS=audio_private,course-media,lesson-media,welcome-cards"
  exit 1
fi

expected_public="$(normalize_list "$EXPECTED_PUBLIC_BUCKETS")"
expected_private="$(normalize_list "$EXPECTED_PRIVATE_BUCKETS")"

if dupes=$(printf "%s\n%s\n" "$expected_public" "$expected_private" | sort | uniq -d); [[ -n "$dupes" ]]; then
  echo "FAIL: buckets listed as both public and private: $(join_lines "$dupes")"
  exit 1
fi

if ! actual_public=$(PGOPTIONS="$READONLY_PGOPTIONS" psql "$SUPABASE_DB_URL" -At -c "select id from storage.buckets where public = true order by id;"); then
  echo "FAIL: storage query for public buckets failed"
  exit 1
fi
if ! actual_private=$(PGOPTIONS="$READONLY_PGOPTIONS" psql "$SUPABASE_DB_URL" -At -c "select id from storage.buckets where public = false order by id;"); then
  echo "FAIL: storage query for private buckets failed"
  exit 1
fi
if ! actual_all=$(PGOPTIONS="$READONLY_PGOPTIONS" psql "$SUPABASE_DB_URL" -At -c "select id from storage.buckets order by id;"); then
  echo "FAIL: storage query for bucket list failed"
  exit 1
fi

expected_all=$(printf "%s\n%s\n" "$expected_public" "$expected_private" | sort)
actual_all_sorted=$(printf "%s\n" "$actual_all" | sed '/^$/d' | sort)
actual_public_sorted=$(printf "%s\n" "$actual_public" | sed '/^$/d' | sort)
actual_private_sorted=$(printf "%s\n" "$actual_private" | sed '/^$/d' | sort)

missing=$(comm -23 <(printf "%s\n" "$expected_all") <(printf "%s\n" "$actual_all_sorted"))
extra=$(comm -13 <(printf "%s\n" "$expected_all") <(printf "%s\n" "$actual_all_sorted"))
if [[ -n "$missing" || -n "$extra" ]]; then
  echo "FAIL: bucket list mismatch"
  echo "Missing: $(join_lines "$missing")"
  echo "Extra: $(join_lines "$extra")"
  exit 1
fi

if [[ "$actual_public_sorted" != "$expected_public" ]]; then
  echo "FAIL: public buckets mismatch"
  echo "Expected public: $(join_lines "$expected_public")"
  echo "Actual public: $(join_lines "$actual_public_sorted")"
  exit 1
fi

if [[ "$actual_private_sorted" != "$expected_private" ]]; then
  echo "FAIL: private buckets mismatch"
  echo "Expected private: $(join_lines "$expected_private")"
  echo "Actual private: $(join_lines "$actual_private_sorted")"
  exit 1
fi

echo "OK: public buckets -> $(join_lines "$actual_public_sorted")"

auto_fix="${ALLOW_STORAGE_MUTATIONS:-}"
if [[ "$auto_fix" == "1" || "$auto_fix" == "true" ]]; then
  if is_local_db_url "$SUPABASE_DB_URL"; then
    public_in_list=$(build_in_list "$expected_public")
    private_in_list=$(build_in_list "$expected_private")
    if [[ -n "$public_in_list" ]]; then
      psql "$SUPABASE_DB_URL" -c "update storage.buckets set public = true where id in (${public_in_list});" >/dev/null
    fi
    if [[ -n "$private_in_list" ]]; then
      psql "$SUPABASE_DB_URL" -c "update storage.buckets set public = false where id in (${private_in_list});" >/dev/null
    fi
    echo "Applied local storage visibility updates."
  else
    echo "Skip storage mutation: SUPABASE_DB_URL not local"
  fi
fi
