#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
BOOTSTRAP_SCRIPT_DIR="$(cd "$(dirname "$BOOTSTRAP_SCRIPT_PATH")" && pwd)"

exec "$BOOTSTRAP_SCRIPT_DIR/dev_reset.sh"
