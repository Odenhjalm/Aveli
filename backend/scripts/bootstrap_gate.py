#!/usr/bin/env python3
from __future__ import annotations

import io
import json
import os
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"
BASELINE_DIR = BACKEND_DIR / "supabase" / "baseline_slots"
LOCK_FILE = BACKEND_DIR / "supabase" / "baseline_slots.lock.json"

if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from backend.bootstrap.load_env import load_env


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


def parse_lockfile(lock_path: Path) -> tuple[list[dict[str, Any]], int]:
    try:
        payload = json.loads(lock_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"BASELINE_INVALID: baseline_slots.lock.json is invalid JSON: {exc}") from exc

    if not isinstance(payload, dict):
        raise RuntimeError("BASELINE_INVALID: baseline_slots.lock.json must contain a JSON object")

    slots = payload.get("slots")
    if not isinstance(slots, list) or not slots:
        raise RuntimeError("BASELINE_INVALID: baseline_slots.lock.json must contain a non-empty 'slots' list")

    try:
        ordered_slots = sorted(slots, key=lambda item: int(item["slot"]))
    except (KeyError, TypeError, ValueError) as exc:
        raise RuntimeError(
            "BASELINE_INVALID: each lockfile slot entry must include an integer 'slot'"
        ) from exc

    return ordered_slots, len(ordered_slots)


def verify_baseline() -> int:
    if not BASELINE_DIR.is_dir():
        raise RuntimeError(f"BASELINE_INVALID: missing baseline directory: {BASELINE_DIR}")

    if not LOCK_FILE.is_file():
        raise RuntimeError(f"BASELINE_INVALID: missing lockfile: {LOCK_FILE}")

    ordered_slots, slot_count = parse_lockfile(LOCK_FILE)

    for entry in ordered_slots:
        if not isinstance(entry, dict):
            raise RuntimeError("BASELINE_INVALID: each lockfile slot entry must be an object")

        slot_number = entry.get("slot")
        filename = entry.get("filename")
        relative_path = entry.get("path")

        if not isinstance(filename, str) or not filename:
            raise RuntimeError(f"BASELINE_INVALID: slot {slot_number} is missing 'filename'")
        if not isinstance(relative_path, str) or not relative_path:
            raise RuntimeError(f"BASELINE_INVALID: slot {slot_number} is missing 'path'")

        absolute_path = ROOT_DIR / relative_path
        if absolute_path.name != filename:
            raise RuntimeError(
                f"BASELINE_INVALID: slot {slot_number} filename mismatch: {filename} != {absolute_path.name}"
            )
        if not absolute_path.is_file():
            raise RuntimeError(f"BASELINE_INVALID: slot {slot_number} missing on disk: {absolute_path}")

    return slot_count


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

        if mcp_mode != "local":
            raise RuntimeError(f"ENV_INVALID: MCP_MODE must be 'local', got '{mcp_mode}'")

        if "127.0.0.1" not in database_url:
            raise RuntimeError("ENV_INVALID: DATABASE_URL must contain '127.0.0.1'")

        state["DB_STATUS"] = verify_database(database_url)
        state["SLOT_COUNT"] = str(verify_baseline())
        state["FINAL_STATE"] = "GO"
        return state, 0
    except Exception as exc:
        state["FAILURE"] = str(exc)
        if state["DB_STATUS"] == "not_checked":
            state["DB_STATUS"] = "failed"
        return state, 1


def print_status(state: dict[str, str]) -> None:
    print(f"MCP_MODE={state['MCP_MODE']}")
    print(f"DATABASE_URL={state['DATABASE_URL']}")
    print(f"DB_STATUS={state['DB_STATUS']}")
    print(f"SLOT_COUNT={state['SLOT_COUNT']}")
    print(f"FINAL_STATE={state['FINAL_STATE']}")
    if state["FAILURE"]:
        print(f"FAILURE={state['FAILURE']}")
    if state["FINAL_STATE"] == "GO":
        print("READY_FOR_BASELINE_REPLAY")
        print("BOOTSTRAP_GATE_OK=1")


def ensure_local_execution_ready() -> dict[str, str]:
    state, exit_code = collect_status()
    print_status(state)
    if exit_code != 0:
        raise SystemExit(exit_code)
    return state


def main() -> int:
    state, exit_code = collect_status()
    print_status(state)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
