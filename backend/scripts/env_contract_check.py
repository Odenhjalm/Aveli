#!/usr/bin/env python3
"""Minimal backend env contract check.

Ensures required env files are present. Does not print secrets.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

DEFAULT_ENV_PATH = Path("/home/oden/Aveli/backend/.env")


def main() -> int:
    env_path = Path(os.environ.get("BACKEND_ENV_FILE", DEFAULT_ENV_PATH))
    overlay_path_raw = os.environ.get("BACKEND_ENV_OVERLAY_FILE", "")
    overlay_path = Path(overlay_path_raw) if overlay_path_raw else None

    if not env_path.exists():
        print(f"ERROR: backend env missing at {env_path}", file=sys.stderr)
        return 1

    if overlay_path_raw and overlay_path and not overlay_path.exists():
        print(f"WARN: overlay env missing at {overlay_path}", file=sys.stderr)

    print("PASS: env contract check")
    return 0


if __name__ == "__main__":
    sys.exit(main())
