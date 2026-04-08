#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> Delegating baseline bootstrap to backend/supabase/baseline_slots replay"
exec "$ROOT_DIR/backend/scripts/replay_baseline.sh"
