#!/usr/bin/env bash
set -euo pipefail

# Validate all manifests under courses/ using the importer in --dry-run mode.
# No network calls are made in --dry-run; base-url/email/password are placeholders.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$BACKEND_DIR/.." && pwd)"
source "$REPO_ROOT/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_BACKEND_PYTHON" "backend python"

BASE_URL="http://127.0.0.1:8080"
EMAIL="dryrun@example.com"
PASSWORD="not-used"

shopt -s nullglob
files=("$REPO_ROOT"/courses/*.yaml "$REPO_ROOT"/courses/*.yml "$REPO_ROOT"/courses/*.json)
shopt -u nullglob

if [ ${#files[@]} -eq 0 ]; then
  echo "No manifests found in courses/"
  exit 0
fi

echo "Validating ${#files[@]} manifest(s) in courses/"
for f in "${files[@]}"; do
  echo "\n==> $f"
  "$AVELI_BACKEND_PYTHON" "$BACKEND_DIR/scripts/import_course.py" \
    --manifest "$f" \
    --base-url "$BASE_URL" \
    --email "$EMAIL" \
    --password "$PASSWORD" \
    --dry-run
done

echo "\nAll course manifests validated successfully."
