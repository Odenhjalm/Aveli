#!/usr/bin/env bash
# Purpose: Capture verbose Flutter and adb logs for Android debugging sessions.
# Mutates state: Yes (runs app/build steps and writes log files under logs/).
# Run context: Local troubleshooting only; not for CI.
set -euo pipefail

mkdir -p logs

flutter clean
flutter pub get
flutter run --verbose > logs/flutter_verbose.txt
adb logcat -d > logs/adb_logcat.txt
