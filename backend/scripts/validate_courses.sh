#!/usr/bin/env bash
# Purpose: Validate course manifests by invoking importer dry-run mode.
# Mutates state: No (validation only; no DB or remote writes in dry-run).
# Run context: Safe for CI and local preflight checks.
set -euo pipefail

# Validate all manifests under courses/ using the importer in --dry-run mode.
# Base-url/email/password are placeholders for argument compatibility.

BASE_URL="http://127.0.0.1:8080"
EMAIL="dryrun@example.com"
PASSWORD="not-used"

shopt -s nullglob
files=(courses/*.yaml courses/*.yml courses/*.json)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "No manifests found in courses/"
  exit 0
fi

PY_BIN="python"
if ! command -v "$PY_BIN" >/dev/null 2>&1; then
  if command -v python3 >/dev/null 2>&1; then
    PY_BIN="python3"
  fi
fi

echo "Validating ${#files[@]} manifest(s) in courses/"
for f in "${files[@]}"; do
  echo "\n==> $f"
  "$PY_BIN" scripts/import_course.py \
    --manifest "$f" \
    --base-url "$BASE_URL" \
    --email "$EMAIL" \
    --password "$PASSWORD" \
    --dry-run
done

echo "\nAll course manifests validated successfully."
