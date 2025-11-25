#!/usr/bin/env bash
set -euo pipefail

if ! command -v dart >/dev/null 2>&1; then
  echo "dart command not found" >&2
  exit 1
fi

echo "> dart format lib test bin tool"
dart format lib test bin tool
