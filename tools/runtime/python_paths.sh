#!/usr/bin/env bash

_aveli_python_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export AVELI_REPO_ROOT="${AVELI_REPO_ROOT:-${_aveli_python_helper_dir}}"
export AVELI_REPO_PYTHON="${AVELI_REPO_PYTHON:-${AVELI_REPO_ROOT}/.venv/bin/python}"
export AVELI_BACKEND_PYTHON="${AVELI_BACKEND_PYTHON:-${AVELI_REPO_ROOT}/backend/.venv/bin/python}"
export AVELI_SEARCH_PYTHON="${AVELI_SEARCH_PYTHON:-${AVELI_REPO_ROOT}/.repo_index/.search_venv/bin/python}"

aveli_require_python() {
  local path="$1"
  local label="${2:-python}"

  if [[ ! -x "$path" ]]; then
    echo "ERROR: missing ${label} interpreter at ${path}" >&2
    exit 1
  fi
}
