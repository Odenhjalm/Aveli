#!/usr/bin/env python3
from __future__ import annotations

import io
import os
import sys
from contextlib import redirect_stdout
from pathlib import Path
from urllib.parse import urlsplit

ROOT_DIR = Path(__file__).resolve().parents[2]

if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from backend.bootstrap.baseline_v2 import (  # noqa: E402
    BASELINE_V2_DIR,
    BASELINE_V2_LOCK_FILE,
    BASELINE_MODE_ENV,
    BaselineV2Error,
    DEFAULT_BASELINE_MODE,
    validate_runtime_database_url,
    verify_v2_lock,
)
from backend.bootstrap.load_env import load_env

BASELINE_DIR = BASELINE_V2_DIR
LOCK_FILE = BASELINE_V2_LOCK_FILE
LEGACY_BASELINE_NAME = "baseline" + "_slots"
LEGACY_LOCK_NAME = f"{LEGACY_BASELINE_NAME}.lock.json"
BASELINE_OVERRIDE_ENV_KEYS = (
    "BASELINE_DIR",
    "BASELINE_PATH",
    "BASELINE_LOCK_FILE",
    "LOCK_FILE",
    "MANIFEST_PATH",
)


def prepare_local_site_packages() -> None:
    version_dir = f"python{sys.version_info.major}.{sys.version_info.minor}"
    candidates = [
        ROOT_DIR / ".venv" / "Lib" / "site-packages",
        ROOT_DIR / ".venv" / "lib" / version_dir / "site-packages",
        ROOT_DIR / "backend" / ".venv" / "Lib" / "site-packages",
        ROOT_DIR / "backend" / ".venv" / "lib" / version_dir / "site-packages",
    ]

    # Allow `python backend/scripts/bootstrap_gate.py` to reuse the repo's installed deps.
    for candidate in candidates:
        if candidate.is_dir():
            sys.path.insert(0, str(candidate))


prepare_local_site_packages()

import psycopg


def sanitize_database_url(value: str | None) -> str:
    if not value:
        return ""

    parsed = urlsplit(value)
    host = parsed.hostname or ""
    port = f":{parsed.port}" if parsed.port else ""
    path = parsed.path or ""
    username = parsed.username or ""

    if username:
        netloc = f"{username}:***@{host}{port}"
    else:
        netloc = host + port

    return f"{parsed.scheme}://{netloc}{path}"


def load_effective_env() -> None:
    with redirect_stdout(io.StringIO()):
        load_env()


def _contains_legacy_baseline_reference(value: str) -> bool:
    normalized = value.replace("\\", "/").lower()
    return LEGACY_BASELINE_NAME in normalized or LEGACY_LOCK_NAME in normalized


def reject_legacy_baseline_inputs() -> None:
    for key in BASELINE_OVERRIDE_ENV_KEYS:
        value = os.getenv(key, "")
        if value and _contains_legacy_baseline_reference(value):
            raise RuntimeError(f"BASELINE_V2_INVALID: {key} points to archived legacy baseline")

    mode = str(os.getenv(BASELINE_MODE_ENV) or DEFAULT_BASELINE_MODE).strip().upper()
    if mode != DEFAULT_BASELINE_MODE:
        raise RuntimeError(
            f"BASELINE_V2_INVALID: {BASELINE_MODE_ENV} must be {DEFAULT_BASELINE_MODE!r}, got {mode!r}"
        )


def verify_database(database_url: str) -> str:
    with psycopg.connect(
        database_url,
        connect_timeout=5,
        options="-c default_transaction_read_only=on",
    ) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            row = cur.fetchone()

    if not row or row[0] != 1:
        raise RuntimeError("DB_UNREACHABLE: SELECT 1 returned an unexpected result")

    return "ok (SELECT 1)"


def verify_baseline() -> int:
    if not BASELINE_DIR.is_dir():
        raise RuntimeError(f"BASELINE_INVALID: missing baseline directory: {BASELINE_DIR}")

    if not LOCK_FILE.is_file():
        raise RuntimeError(f"BASELINE_INVALID: missing lockfile: {LOCK_FILE}")

    try:
        payload = verify_v2_lock()
    except BaselineV2Error as exc:
        raise RuntimeError(f"BASELINE_V2_INVALID: {exc}") from exc

    slots = payload.get("slots")
    return len(slots) if isinstance(slots, list) else 0


def _initial_state() -> dict[str, str]:
    return {
        "MCP_MODE": "",
        "DATABASE_URL": "",
        "DB_STATUS": "not_checked",
        "SLOT_COUNT": "0",
        "FINAL_STATE": "STOP",
        "FAILURE": "",
    }


def collect_status() -> tuple[dict[str, str], int]:
    state = {
        "MCP_MODE": "",
        "DATABASE_URL": "",
        "DB_STATUS": "not_checked",
        "SLOT_COUNT": "0",
        "FINAL_STATE": "STOP",
        "FAILURE": "",
    }

    try:
        load_effective_env()

        mcp_mode = os.getenv("MCP_MODE", "")
        database_url = os.getenv("DATABASE_URL", "")

        state["MCP_MODE"] = mcp_mode
        state["DATABASE_URL"] = sanitize_database_url(database_url)

        reject_legacy_baseline_inputs()
        state["SLOT_COUNT"] = str(verify_baseline())

        if mcp_mode != "local":
            raise RuntimeError(f"ENV_INVALID: MCP_MODE must be 'local', got '{mcp_mode}'")

        if "127.0.0.1" not in database_url:
            raise RuntimeError("ENV_INVALID: DATABASE_URL must contain '127.0.0.1'")

        state["DB_STATUS"] = verify_database(database_url)
        state["FINAL_STATE"] = "GO"
        return state, 0
    except Exception as exc:
        state["FAILURE"] = str(exc)
        if state["DB_STATUS"] == "not_checked":
            state["DB_STATUS"] = "failed"
        return state, 1


def collect_runtime_status() -> tuple[dict[str, str], int]:
    state = _initial_state()

    try:
        load_effective_env()

        mcp_mode = os.getenv("MCP_MODE", "")
        database_url = os.getenv("DATABASE_URL", "")

        state["MCP_MODE"] = mcp_mode
        state["DATABASE_URL"] = sanitize_database_url(database_url)

        reject_legacy_baseline_inputs()
        state["SLOT_COUNT"] = str(verify_baseline())

        if not database_url:
            raise RuntimeError("ENV_INVALID: DATABASE_URL is missing")

        try:
            validate_runtime_database_url(database_url)
        except BaselineV2Error as exc:
            raise RuntimeError(f"ENV_INVALID: {exc}") from exc

        state["DB_STATUS"] = verify_database(database_url)
        state["FINAL_STATE"] = "GO"
        return state, 0
    except Exception as exc:
        state["FAILURE"] = str(exc)
        if state["DB_STATUS"] == "not_checked":
            state["DB_STATUS"] = "failed"
        return state, 1


def print_status(state: dict[str, str], *, ready_token: str = "READY_FOR_BASELINE_REPLAY") -> None:
    print(f"MCP_MODE={state['MCP_MODE']}")
    print(f"DATABASE_URL={state['DATABASE_URL']}")
    print(f"DB_STATUS={state['DB_STATUS']}")
    print(f"SLOT_COUNT={state['SLOT_COUNT']}")
    print(f"FINAL_STATE={state['FINAL_STATE']}")
    if state["FAILURE"]:
        print(f"FAILURE={state['FAILURE']}")
    if state["FINAL_STATE"] == "GO":
        print(ready_token)
        print("BOOTSTRAP_GATE_OK=1")


def ensure_local_execution_ready() -> dict[str, str]:
    state, exit_code = collect_status()
    print_status(state)
    if exit_code != 0:
        raise SystemExit(exit_code)
    return state


def ensure_runtime_execution_ready() -> dict[str, str]:
    state, exit_code = collect_runtime_status()
    print_status(state, ready_token="READY_FOR_BASELINE_RUNTIME")
    if exit_code != 0:
        raise SystemExit(exit_code)
    return state


def main() -> int:
    state, exit_code = collect_status()
    print_status(state)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
