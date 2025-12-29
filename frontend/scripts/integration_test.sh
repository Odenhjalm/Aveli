#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEVICE="${FLUTTER_INTEGRATION_DEVICE:-linux}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found in PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"

if [[ "$DEVICE" == "chrome" || "$DEVICE" == "web-server" ]]; then
  echo "WARNING: web devices are not supported for integration_test; use linux for now." >&2
fi

echo "Running Flutter integration tests on device: ${DEVICE}"
if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a flutter test integration_test -d "$DEVICE"
else
  flutter test integration_test -d "$DEVICE"
fi
