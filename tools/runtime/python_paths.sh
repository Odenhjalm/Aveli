#!/usr/bin/env bash

_aveli_python_helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

_aveli_default_python_path() {
  local venv_root="$1"
  local unix_path="${venv_root}/bin/python"
  local windows_path="${venv_root}/Scripts/python.exe"

  if [[ -x "$unix_path" ]]; then
    printf '%s\n' "$unix_path"
    return 0
  fi

  if [[ -f "$windows_path" ]]; then
    printf '%s\n' "$windows_path"
    return 0
  fi

  printf '%s\n' "$unix_path"
}

export AVELI_REPO_ROOT="${AVELI_REPO_ROOT:-${_aveli_python_helper_dir}}"
export AVELI_REPO_PYTHON="${AVELI_REPO_PYTHON:-$(_aveli_default_python_path "${AVELI_REPO_ROOT}/.venv")}"
export AVELI_BACKEND_PYTHON="${AVELI_BACKEND_PYTHON:-$(_aveli_default_python_path "${AVELI_REPO_ROOT}/backend/.venv")}"
export AVELI_SEARCH_PYTHON="${AVELI_SEARCH_PYTHON:-$(_aveli_default_python_path "${AVELI_REPO_ROOT}/.repo_index/.search_venv")}"

aveli_require_python() {
  local path="$1"
  local label="${2:-python}"

  if [[ ! -x "$path" && !( -f "$path" && "${path,,}" == *.exe ) ]]; then
    echo "ERROR: missing ${label} interpreter at ${path}" >&2
    exit 1
  fi
}
