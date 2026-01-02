#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
LOG_DIR="$ROOT_DIR/logs"

mkdir -p "$LOG_DIR"

(
  cd "$FRONTEND_DIR"
  flutter clean
  flutter pub get
  flutter run --verbose > "$LOG_DIR/flutter_verbose.txt"
)

adb logcat -d > "$LOG_DIR/adb_logcat.txt"
