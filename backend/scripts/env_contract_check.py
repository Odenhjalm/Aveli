#!/usr/bin/env python3
"""Validate backend/.env against required key contract.

Environment-aware:
- Development: warns for optional DB/JWT keys.
- Production: requires DB/JWT + live Stripe keys.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = ROOT / "backend" / ".env"
REQUIRED_PATH = ROOT / "ENV_REQUIRED_KEYS.txt"


def _parse_env(path: Path) -> dict[str, str]:
    data: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        if key:
            data[key] = value
    return data


def _load_required(path: Path) -> list[str]:
    keys: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        keys.append(line)
    return keys


def _env_value(env_map: dict[str, str], key: str) -> str:
    return os.environ.get(key) or env_map.get(key, "")


def main() -> int:
    if not ENV_PATH.exists():
        print("ERROR: backend/.env missing (required for env contract check).", file=sys.stderr)
        return 1
    if not REQUIRED_PATH.exists():
        print("ERROR: ENV_REQUIRED_KEYS.txt missing.", file=sys.stderr)
        return 1

    env_map = _parse_env(ENV_PATH)
    required_keys = _load_required(REQUIRED_PATH)

    app_env = (
        _env_value(env_map, "APP_ENV")
        or _env_value(env_map, "ENV")
        or _env_value(env_map, "ENVIRONMENT")
    )
    env_lower = app_env.lower() if app_env else ""
    if env_lower in {"prod", "production", "live"}:
        mode = "production"
    else:
        mode = "development"
        if not env_lower:
            print("WARN: APP_ENV/ENV not set; assuming development.", file=sys.stderr)

    prod_only = {
        "SUPABASE_DB_URL",
        "JWT_SECRET",
        "JWT_ALGORITHM",
        "JWT_EXPIRES_MINUTES",
        "JWT_REFRESH_EXPIRES_MINUTES",
        "STRIPE_LIVE_SECRET_KEY",
        "STRIPE_LIVE_PUBLISHABLE_KEY",
        "STRIPE_LIVE_WEBHOOK_SECRET",
        "STRIPE_LIVE_BILLING_WEBHOOK_SECRET",
    }

    missing_required = [key for key in required_keys if not _env_value(env_map, key)]
    missing_prod = []
    missing_optional = []

    if mode == "production":
        missing_prod = [key for key in sorted(prod_only) if not _env_value(env_map, key)]
    else:
        missing_optional = [key for key in sorted(prod_only) if not _env_value(env_map, key)]

    if missing_required:
        print("FAIL: Missing required keys:")
        for key in missing_required:
            print(f"- {key}")

    if missing_prod:
        print("FAIL: Missing production-only keys:")
        for key in missing_prod:
            print(f"- {key}")

    if missing_optional:
        print("WARN: Optional keys missing for development:")
        for key in missing_optional:
            print(f"- {key}")

    if missing_required or missing_prod:
        return 1

    print(f"PASS: env contract satisfied ({mode}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
