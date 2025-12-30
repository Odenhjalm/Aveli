#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

fail=0

note() {
  printf '%s\n' "$*"
}

flag() {
  note "ERROR: $1"
  fail=1
}

tracked_prefix_violation() {
  local prefix="$1"
  if git ls-files -z | tr '\0' '\n' | grep -E -q "^${prefix}"; then
    flag "Tracked files found under ${prefix}"
    note "Fix: git rm --cached -r ${prefix} && add ${prefix} to .gitignore"
  fi
}

tracked_file_violation() {
  local path="$1"
  if git ls-files -z -- "${path}" | tr '\0' '\n' | grep -q '.'; then
    flag "Tracked noise file detected: ${path}"
    note "Fix: git rm --cached ${path} && add ${path} to .gitignore"
  fi
}

unignored_violation() {
  local path="$1"
  local label="$2"
  if [[ -e "${path}" ]]; then
    if git check-ignore -q -- "${path}"; then
      return 0
    fi
    flag "Noise artifact exists and is not ignored: ${path} (${label})"
    note "Fix: add ${path} to .gitignore or remove the file"
  fi
}

tracked_prefix_violation "supabase/.temp/"
tracked_file_violation ".vscode/extensions.json"

unignored_violation "supabase/.temp" "Supabase CLI temp directory"
unignored_violation "supabase/.temp/cli-latest" "Supabase CLI update marker"
unignored_violation ".vscode/extensions.json" "VS Code extensions list"

if [[ "${fail}" -ne 0 ]]; then
  exit 1
fi

note "Hygiene check passed."
