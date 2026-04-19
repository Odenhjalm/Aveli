#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Delegating baseline bootstrap to canonical Baseline V2 replay"
exec "$ROOT_DIR/backend/scripts/replay_v2.sh"
