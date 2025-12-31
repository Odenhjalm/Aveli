#!/usr/bin/env python3
"""Verify Supabase credentials from backend/.env."""
from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlparse

try:
    import httpx
except Exception:  # pragma: no cover - dependency guard
    print("ERROR: httpx library not available; run `poetry install`", file=sys.stderr)
    raise SystemExit(1)

try:
    import psycopg
except Exception:  # pragma: no cover - dependency guard
    print("ERROR: psycopg library not available; run `poetry install`", file=sys.stderr)
    raise SystemExit(1)


ROOT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT_DIR / "backend" / ".env"


def _die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_env() -> dict[str, str]:
    if not ENV_FILE.exists():
        _die("backend/.env missing – create it from backend/.env.example")
    env: dict[str, str] = {}
    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value and value[0] == value[-1] and value[0] in ("\"", "'"):
            value = value[1:-1]
        env[key] = value
    return env


def is_jwt(value: str) -> bool:
    parts = value.split(".")
    return len(parts) == 3 and all(part.strip() for part in parts)


def derive_project_ref(url: str) -> str:
    try:
        host = urlparse(url).hostname or ""
    except Exception:
        return ""
    return host.split(".")[0] if host else ""


def main() -> None:
    env = load_env()
    errors: list[str] = []

    def require(key: str) -> str:
        value = env.get(key, "").strip()
        if not value:
            errors.append(f"{key} is missing in backend/.env")
        return value

    supabase_url = require("SUPABASE_URL")
    anon_key = require("SUPABASE_ANON_KEY")
    service_key = require("SUPABASE_SERVICE_ROLE_KEY")
    db_url = require("SUPABASE_DB_URL")

    project_ref = ""
    if supabase_url:
        project_ref = derive_project_ref(supabase_url)
        if not project_ref:
            errors.append("SUPABASE_URL is not a valid Supabase URL")

    configured_ref = env.get("SUPABASE_PROJECT_REF", "").strip()
    if project_ref and configured_ref and project_ref != configured_ref:
        errors.append("SUPABASE_PROJECT_REF does not match SUPABASE_URL")

    if anon_key and not is_jwt(anon_key):
        errors.append("SUPABASE_ANON_KEY does not look like a JWT")
    if service_key and not is_jwt(service_key):
        errors.append("SUPABASE_SERVICE_ROLE_KEY does not look like a JWT")

    storage_ok = False
    if supabase_url and service_key:
        storage_url = supabase_url.rstrip("/") + "/storage/v1/bucket"
        try:
            resp = httpx.get(
                storage_url,
                headers={
                    "apikey": service_key,
                    "Authorization": f"Bearer {service_key}",
                },
                timeout=10,
            )
            storage_ok = resp.status_code == 200
            if not storage_ok:
                errors.append(f"Supabase storage request failed (status {resp.status_code})")
        except Exception:
            errors.append("Supabase storage request failed")

    db_ok = False
    if db_url:
        try:
            with psycopg.connect(db_url, connect_timeout=5) as conn:
                with conn.cursor() as cur:
                    cur.execute("select 1;")
                    cur.fetchone()
            db_ok = True
        except Exception:
            errors.append("SUPABASE_DB_URL connection failed")

    print("==> Supabase env verification")
    print(f"- SUPABASE_URL: {'set' if supabase_url else 'missing'}")
    if project_ref:
        print(f"- Project ref: {project_ref}")
    print(f"- SUPABASE_ANON_KEY: {'set' if anon_key else 'missing'}")
    print(f"- SUPABASE_SERVICE_ROLE_KEY: {'set' if service_key else 'missing'}")
    print(f"- Storage list: {'ok' if storage_ok else 'failed'}")
    print(f"- DB connection: {'ok' if db_ok else 'failed'}")

    if errors:
        print("Supabase verification: FAIL")
        for err in errors:
            print(f"  - {err}")
        raise SystemExit(1)

    print("Supabase verification: PASS")


if __name__ == "__main__":
    main()
