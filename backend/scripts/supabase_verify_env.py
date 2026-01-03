#!/usr/bin/env python3
"""Verify Supabase environment keys and basic connectivity."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

import httpx
import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[2]
ENV_PATH = Path(os.environ.get("BACKEND_ENV_FILE", "/home/oden/Aveli/backend/.env"))

if ENV_PATH.exists():
    load_dotenv(ENV_PATH, override=False)


def _val(key: str) -> str:
    return (os.environ.get(key) or "").strip()


def _is_jwt(token: str) -> bool:
    if token.startswith("eyJ"):
        return True
    return bool(re.match(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$", token))


def _derive_project_ref(supabase_url: str) -> Optional[str]:
    parsed = urlparse(supabase_url)
    host = parsed.hostname or ""
    if host.endswith(".supabase.co"):
        return host.split(".")[0]
    return None


def _db_target(db_url: str) -> str:
    parsed = urlparse(db_url)
    host = parsed.hostname or "unknown"
    port = f":{parsed.port}" if parsed.port else ""
    dbname = parsed.path.lstrip("/") or "postgres"
    return f"{host}{port}/{dbname}"


def main() -> int:
    if not ENV_PATH.exists():
        print(f"FAIL: backend env missing at {ENV_PATH}; cannot verify Supabase config.", file=sys.stderr)
        return 1

    supabase_url = _val("SUPABASE_URL")
    if not supabase_url:
        print("FAIL: SUPABASE_URL missing.", file=sys.stderr)
        return 1

    supabase_project_ref = _val("SUPABASE_PROJECT_REF")
    derived_ref = _derive_project_ref(supabase_url)
    if not supabase_project_ref:
        if not derived_ref:
            print("FAIL: SUPABASE_PROJECT_REF missing and SUPABASE_URL hostname is not a supabase.co ref.")
            return 1
        supabase_project_ref = derived_ref
    else:
        if derived_ref and supabase_project_ref != derived_ref:
            print("FAIL: SUPABASE_PROJECT_REF does not match SUPABASE_URL hostname.")
            return 1

    publishable_key = _val("SUPABASE_PUBLISHABLE_API_KEY") or _val("SUPABASE_PUBLIC_API_KEY")
    secret_key = _val("SUPABASE_SECRET_API_KEY")
    legacy_anon = _val("SUPABASE_ANON_KEY")
    legacy_service = _val("SUPABASE_SERVICE_ROLE_KEY")

    errors: list[str] = []
    warnings: list[str] = []

    if publishable_key and not publishable_key.startswith("sb_publishable_"):
        warnings.append("SUPABASE_PUBLISHABLE_API_KEY does not match sb_publishable_ pattern")
    if secret_key and not secret_key.startswith("sb_secret_"):
        warnings.append("SUPABASE_SECRET_API_KEY does not match sb_secret_ pattern")
    if legacy_anon and not legacy_anon.startswith("eyJ"):
        warnings.append("SUPABASE_ANON_KEY is not a JWT")
    if legacy_service and not legacy_service.startswith("eyJ"):
        warnings.append("SUPABASE_SERVICE_ROLE_KEY is not a JWT")

    if not (publishable_key or secret_key or legacy_anon or legacy_service):
        errors.append("No Supabase API keys found (publishable/secret or legacy JWT keys)")

    storage_key = legacy_service or secret_key or publishable_key or legacy_anon
    if not storage_key:
        errors.append("No Supabase API key available for storage list check")
    else:
        headers = {
            "apikey": storage_key,
            "Accept": "application/json",
        }
        if _is_jwt(storage_key):
            headers["Authorization"] = f"Bearer {storage_key}"
        storage_url = supabase_url.rstrip("/") + "/storage/v1/bucket"
        try:
            with httpx.Client(timeout=10) as client:
                resp = client.get(storage_url, headers=headers)
            if resp.status_code != 200:
                snippet = resp.text[:200].replace("\n", " ")
                errors.append(
                    f"Storage list failed ({resp.status_code}): {snippet or 'empty response'}"
                )
        except httpx.HTTPError as exc:
            errors.append(f"Storage list request failed: {exc}")

    db_url = _val("SUPABASE_DB_URL")
    if db_url:
        try:
            with psycopg.connect(
                db_url,
                options="-c default_transaction_read_only=on",
                connect_timeout=5,
            ) as conn:
                with conn.cursor() as cur:
                    cur.execute("select 1")
                    cur.fetchone()
        except psycopg.Error as exc:
            target = _db_target(db_url)
            errors.append(f"DB connection failed ({target}): {exc.__class__.__name__}")

    for warning in warnings:
        print(f"WARN: {warning}")

    if errors:
        print("FAIL: Supabase verification failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print("PASS: Supabase verification passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
