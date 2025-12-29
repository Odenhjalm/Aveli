#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEVICE="${FLUTTER_INTEGRATION_DEVICE:-chrome}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"

echo "Running Flutter integration tests on device: ${DEVICE}"
flutter test integration_test -d "$DEVICE"
