#!/usr/bin/env bash
set -euo pipefail

if git ls-files --error-unmatch backend/.env >/dev/null 2>&1; then
  echo "ERROR: backend/.env must never be tracked in git" >&2
  exit 1
fi
