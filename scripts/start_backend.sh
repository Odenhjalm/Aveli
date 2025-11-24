#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/../backend"
source $(poetry env info --path)/bin/activate
echo "[Backend] Starting Uvicorn..."
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
