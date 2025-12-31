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
        if value and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        env[key] = value
    return env


def is_jwt(value: str) -> bool:
    parts = value.split(".")
    return len(parts) == 3 and all(part.strip() for part in parts)


def is_publishable_key(value: str) -> bool:
    return value.startswith("sb_publishable_")


def is_secret_key(value: str) -> bool:
    return value.startswith("sb_secret_")


def derive_project_ref(url: str) -> tuple[str, str]:
    try:
        hostname = urlparse(url).hostname or ""
    except Exception:
        return "", ""
    if not hostname:
        return "", ""
    project_ref = hostname.split(".")[0] if "." in hostname else ""
    return project_ref, hostname


def format_snippet(text: str, limit: int = 200) -> str:
    snippet = " ".join(text.strip().split())
    if not snippet:
        return "<empty>"
    if len(snippet) > limit:
        return f"{snippet[:limit]}..."
    return snippet


def main() -> None:
    env = load_env()
    errors: list[str] = []

    supabase_url = env.get("SUPABASE_URL", "").strip()
    publishable_key = env.get("SUPABASE_PUBLISHABLE_API_KEY", "").strip()
    secret_key = env.get("SUPABASE_SECRET_API_KEY", "").strip()
    anon_key = env.get("SUPABASE_ANON_KEY", "").strip()
    service_key = env.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    db_url = env.get("SUPABASE_DB_URL", "").strip()
    configured_ref = env.get("SUPABASE_PROJECT_REF", "").strip()

    if not supabase_url:
        errors.append("SUPABASE_URL is missing in backend/.env")

    if not publishable_key and not secret_key:
        errors.append(
            "SUPABASE_PUBLISHABLE_API_KEY or SUPABASE_SECRET_API_KEY is required"
        )

    if publishable_key and not is_publishable_key(publishable_key):
        errors.append("SUPABASE_PUBLISHABLE_API_KEY does not look like sb_publishable_")
    if secret_key and not is_secret_key(secret_key):
        errors.append("SUPABASE_SECRET_API_KEY does not look like sb_secret_")

    if anon_key and not is_jwt(anon_key):
        errors.append("SUPABASE_ANON_KEY does not look like a JWT")
    if service_key and not is_jwt(service_key):
        errors.append("SUPABASE_SERVICE_ROLE_KEY does not look like a JWT")

    project_ref = ""
    derived_ref = ""
    hostname = ""
    if supabase_url:
        derived_ref, hostname = derive_project_ref(supabase_url)
        if not hostname:
            errors.append("SUPABASE_URL is not a valid Supabase URL")
        elif "." not in hostname:
            errors.append("SUPABASE_URL hostname does not include a project ref")
        elif not derived_ref:
            errors.append("SUPABASE_URL does not include a project ref")
        elif not hostname.startswith(f"{derived_ref}."):
            errors.append("Derived project ref does not match SUPABASE_URL hostname")

    if configured_ref:
        project_ref = configured_ref
        if derived_ref and configured_ref != derived_ref:
            errors.append("SUPABASE_PROJECT_REF does not match SUPABASE_URL hostname")
        elif not derived_ref:
            errors.append("SUPABASE_PROJECT_REF set but SUPABASE_URL is invalid")
    else:
        project_ref = derived_ref
        if supabase_url and not derived_ref:
            errors.append(
                "SUPABASE_PROJECT_REF missing and could not derive from SUPABASE_URL"
            )

    storage_status = "skipped"
    key_for_storage = ""
    storage_key_label = "missing"
    if secret_key:
        key_for_storage = secret_key
        storage_key_label = "SUPABASE_SECRET_API_KEY"
    elif service_key:
        key_for_storage = service_key
        storage_key_label = "SUPABASE_SERVICE_ROLE_KEY"
    elif publishable_key:
        key_for_storage = publishable_key
        storage_key_label = "SUPABASE_PUBLISHABLE_API_KEY"
    elif anon_key:
        key_for_storage = anon_key
        storage_key_label = "SUPABASE_ANON_KEY"

    if supabase_url and key_for_storage:
        storage_url = supabase_url.rstrip("/") + "/storage/v1/bucket"
        headers = {"apikey": key_for_storage}
        auth_token = ""
        if service_key and is_jwt(service_key):
            auth_token = service_key
        elif anon_key and is_jwt(anon_key):
            auth_token = anon_key
        elif is_jwt(key_for_storage):
            auth_token = key_for_storage
        if auth_token:
            headers["Authorization"] = f"Bearer {auth_token}"
        try:
            resp = httpx.get(
                storage_url,
                headers=headers,
                timeout=10,
            )
            if resp.status_code == 200:
                storage_status = "ok"
            else:
                storage_status = f"failed ({resp.status_code})"
                snippet = format_snippet(resp.text)
                errors.append(
                    "Supabase storage request failed "
                    f"(status {resp.status_code}): {snippet}"
                )
        except Exception as exc:
            storage_status = "failed"
            errors.append(f"Supabase storage request failed: {exc}")

    db_status = "skipped"
    if db_url:
        try:
            with psycopg.connect(
                db_url,
                connect_timeout=5,
                options="-c default_transaction_read_only=on",
            ) as conn:
                with conn.cursor() as cur:
                    cur.execute("select 1;")
                    cur.fetchone()
            db_status = "ok"
        except Exception as exc:
            db_status = "failed"
            errors.append(f"SUPABASE_DB_URL connection failed: {exc}")

    print("==> Supabase env verification")
    print(f"- SUPABASE_URL: {'set' if supabase_url else 'missing'}")
    print(f"- Project ref: {project_ref or 'missing'}")
    print(
        f"- SUPABASE_PUBLISHABLE_API_KEY: {'set' if publishable_key else 'missing'}"
    )
    print(f"- SUPABASE_SECRET_API_KEY: {'set' if secret_key else 'missing'}")
    print(f"- SUPABASE_ANON_KEY: {'set' if anon_key else 'missing'}")
    print(f"- SUPABASE_SERVICE_ROLE_KEY: {'set' if service_key else 'missing'}")
    print(f"- Storage auth key: {storage_key_label}")
    print(f"- Storage list: {storage_status}")
    print(f"- DB connection: {db_status}")

    if errors:
        print("Supabase verification: FAIL")
        for err in errors:
            print(f"  - {err}")
        raise SystemExit(1)

    print("Supabase verification: PASS")


if __name__ == "__main__":
    main()
