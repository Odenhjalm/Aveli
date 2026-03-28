#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SEARCH_PYTHON="${REPO_ROOT}/.repo_index/.search_venv/bin/python"
SEARCH_SCRIPT="${REPO_ROOT}/tools/index/search_code.py"

if [[ ! -x "${SEARCH_PYTHON}" ]]; then
  echo "ERROR: missing semantic-search interpreter at ${SEARCH_PYTHON}" >&2
  exit 1
fi

exec "${SEARCH_PYTHON}" "${SEARCH_SCRIPT}" "$@"
