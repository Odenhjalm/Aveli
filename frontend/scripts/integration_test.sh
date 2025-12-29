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
mapfile -t tests < <(find integration_test -maxdepth 1 -name '*_test.dart' -print | sort)
if [[ "${#tests[@]}" -eq 0 ]]; then
  echo "No integration_test/*_test.dart files found." >&2
  exit 1
fi

for test_file in "${tests[@]}"; do
  echo ""
  echo "== ${test_file} =="
  if [[ -z "${DISPLAY:-}" ]] && command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a flutter test "$test_file" -d "$DEVICE"
  else
    flutter test "$test_file" -d "$DEVICE"
  fi
done
