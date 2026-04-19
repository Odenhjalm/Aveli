from __future__ import annotations

# --- ENV LOADING (CORRECT + ORDERED) ---
from dotenv import load_dotenv
from pathlib import Path
import os

ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"
CALLER_ENV = dict(os.environ)

# 1. Load base env (only if not already set)
load_dotenv(BACKEND_DIR / ".env", override=False)

# 2. Load local env over the base file, while preserving caller-provided env.
load_dotenv(BACKEND_DIR / ".env.local", override=True)
for key, value in CALLER_ENV.items():
    os.environ[key] = value

# DEBUG
print("[ENV] APP_ENV =", os.getenv("APP_ENV"))
print("[ENV] DATABASE_URL =", "<set>" if os.getenv("DATABASE_URL") else "")
print("[ENV] MCP_MODE =", os.getenv("MCP_MODE"))
print("[ENV] SUPABASE_URL =", os.getenv("SUPABASE_URL"))

# --- STANDARD IMPORTS ---
import asyncio
import sys

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


# --- MAIN ENTRYPOINT ---
def main() -> None:
    print("[AVELI] Bootstrapping backend...")

    # Ensure environment, DB reachability, and canonical V2 lock readiness.
    ensure_runtime_execution_ready()

    try:
        baseline_status = verify_v2_runtime()
    except BaselineV2Error as exc:
        raise SystemExit(f"[AVELI BASELINE] {exc}") from exc

    print(
        "[AVELI BASELINE] "
        f"BASELINE_MODE={baseline_status['mode']} "
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
