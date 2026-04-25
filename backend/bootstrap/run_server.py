from __future__ import annotations

import asyncio
import os
import subprocess
import sys
from dotenv import load_dotenv
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"
MCP_BOOTSTRAP_GATE_PATH = ROOT_DIR / "ops" / "mcp_bootstrap_gate.ps1"
ROOT_ENV_PATH = ROOT_DIR / ".env"
PRODUCTION_ENV_VALUES = {"prod", "production", "live"}
CLOUD_RUNTIME_ENV_KEYS = ("FLY_APP_NAME", "K_SERVICE", "AWS_EXECUTION_ENV", "DYNO")

from backend.bootstrap.baseline_v2 import BaselineV2Error, verify_v2_runtime
from backend.scripts.bootstrap_gate import ensure_runtime_execution_ready


# --- WINDOWS EVENT LOOP FIX ---
def _apply_windows_selector_policy() -> None:
    """Ensure psycopg-compatible event loop on Windows BEFORE uvicorn starts."""
    if sys.platform != "win32":
        return

    selector_policy_type = getattr(asyncio, "WindowsSelectorEventLoopPolicy", None)
    if selector_policy_type is None:
        return

    current_policy = asyncio.get_event_loop_policy()
    if isinstance(current_policy, selector_policy_type):
        return

    asyncio.set_event_loop_policy(selector_policy_type())


# --- CONFIG HELPERS ---
def _port() -> int:
    raw = str(os.environ.get("PORT", 8080)).strip() or "8080"
    try:
        return int(raw)
    except ValueError as exc:
        raise SystemExit(f"[AVELI] Invalid PORT value: {raw}") from exc


def _load_root_env_for_mcp_gate() -> None:
    load_dotenv(ROOT_ENV_PATH, override=False)


def _cloud_runtime_active() -> bool:
    app_env = str(os.environ.get("APP_ENV") or "").strip().lower()
    mcp_mode = str(os.environ.get("MCP_MODE") or "").strip().lower()
    if app_env == "local" and mcp_mode == "local":
        return False
    return app_env in PRODUCTION_ENV_VALUES or any(
        os.environ.get(key) for key in CLOUD_RUNTIME_ENV_KEYS
    )


def _run_mcp_bootstrap_gate() -> None:
    _load_root_env_for_mcp_gate()

    command = (
        [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(MCP_BOOTSTRAP_GATE_PATH),
        ]
        if sys.platform == "win32"
        else [
            "pwsh",
            "-NoProfile",
            "-File",
            str(MCP_BOOTSTRAP_GATE_PATH),
        ]
    )

    try:
        completed = subprocess.run(command, cwd=str(ROOT_DIR), check=False)
    except OSError as exc:
        raise SystemExit(1) from exc

    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


# --- MAIN ENTRYPOINT ---
def main() -> None:
    print("[AVELI] Bootstrapping backend...")

    if _cloud_runtime_active():
        print("[AVELI] Skipping local MCP bootstrap gate in production/cloud runtime")
    else:
        _run_mcp_bootstrap_gate()

    # Ensure environment, DB reachability, and canonical V2 lock readiness.
    ensure_runtime_execution_ready()

    try:
        baseline_status = verify_v2_runtime()
    except BaselineV2Error as exc:
        raise SystemExit(f"[AVELI BASELINE] {exc}") from exc

    print(
        "[AVELI BASELINE] "
        f"BASELINE_MODE={baseline_status['mode']} "
        f"BASELINE_PROFILE={baseline_status['profile']} "
        f"BASELINE_STATE={baseline_status['state']} "
        f"SCHEMA_HASH={baseline_status['schema_hash']}"
    )

    # Windows compatibility fix
    _apply_windows_selector_policy()

    host = "0.0.0.0"
    port = _port()
    print(f"[AVELI] HOST={host} PORT={port}")

    # Start server
    import uvicorn

    uvicorn.run(
        "app.main:app",
        app_dir=str(BACKEND_DIR),
        host=host,
        port=port,
        reload=False,
    )


# --- CLI ---
if __name__ == "__main__":
    main()
