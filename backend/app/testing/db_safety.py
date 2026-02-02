from __future__ import annotations

import os
import shlex
import sys
from urllib.parse import urlparse, urlunparse

_ALLOWED_TEST_HOSTS = {
    "localhost",
    "127.0.0.1",
    "::1",
    "host.docker.internal",
}

_DISALLOWED_HOST_MARKERS = (
    ".supabase.co",
    ".supabase.com",
    ".supabase.net",
    ".supabase.in",
)

_DISALLOWED_ENV_MARKERS = (
    "prod",
    "production",
    "staging",
    "live",
)


def running_under_pytest() -> bool:
    return "PYTEST_CURRENT_TEST" in os.environ or "pytest" in sys.modules


def _redact_db_url(raw: str) -> str:
    if not raw:
        return raw
    try:
        parsed = urlparse(raw)
    except Exception:
        return "<invalid database url>"

    if not parsed.password:
        return raw

    safe_netloc = parsed.netloc.replace(parsed.password, "****")
    return urlunparse(parsed._replace(netloc=safe_netloc))


def assert_safe_test_db_url(raw: str, *, source: str) -> None:
    """Fail fast if tests are pointed at Supabase or a non-local DB."""

    if not raw:
        raise RuntimeError(
            f"Tests require {source} to be set to a local Postgres URL."
        )

    raw = raw.strip()

    host = ""
    db_name = ""
    if "://" in raw:
        try:
            parsed = urlparse(raw)
        except Exception as exc:
            raise RuntimeError(
                f"Tests require {source} to be a valid database URL; got: {_redact_db_url(raw)}"
            ) from exc
        host = (parsed.hostname or "").strip().lower()
        db_name = (parsed.path or "").lstrip("/").strip().lower()
    else:
        # psycopg also accepts DSN strings like "host=localhost dbname=postgres".
        try:
            parts = shlex.split(raw)
        except ValueError:
            parts = raw.split()
        params: dict[str, str] = {}
        for part in parts:
            if "=" not in part:
                continue
            key, value = part.split("=", 1)
            params[key.strip().lower()] = value.strip().strip("'\"")
        host = params.get("host", "").strip().lower()
        db_name = params.get("dbname", "").strip().lower()

    if not host:
        raise RuntimeError(
            f"Tests require {source} to include a hostname; got: {_redact_db_url(raw)}"
        )

    # Unix socket connections are always local.
    if host.startswith("/"):
        return

    if "supabase" in host or any(marker in host for marker in _DISALLOWED_HOST_MARKERS):
        raise RuntimeError(
            "Tests are not allowed to run against Supabase databases. "
            f"{source} points to host '{host}'."
        )

    if host not in _ALLOWED_TEST_HOSTS:
        raise RuntimeError(
            "Tests are only allowed to connect to a local database. "
            f"{source} host '{host}' is not permitted."
        )

    for marker in _DISALLOWED_ENV_MARKERS:
        if marker in host or (db_name and marker in db_name):
            raise RuntimeError(
                "Tests are not allowed to run against prod/staging/live databases. "
                f"{source} contains marker '{marker}'. "
                f"Value: {_redact_db_url(raw)}"
            )
