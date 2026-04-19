#!/usr/bin/env bash
set -euo pipefail

echo "ERROR: Legacy baseline replay is disabled." >&2
echo "Use backend/scripts/replay_v2.sh after the V2 gate has been approved." >&2
exit 1
