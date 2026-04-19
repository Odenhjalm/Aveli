#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tools/runtime/python_paths.sh"
aveli_require_python "$AVELI_REPO_PYTHON" "repo python"

echo "ERROR: Legacy protected-range verifier is disabled." >&2
echo "Use the canonical Baseline V2 lock checker." >&2
exit 1
