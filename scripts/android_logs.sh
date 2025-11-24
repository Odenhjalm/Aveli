#!/usr/bin/env bash
set -euo pipefail

mkdir -p logs

flutter clean
flutter pub get
flutter run --verbose > logs/flutter_verbose.txt
adb logcat -d > logs/adb_logcat.txt
