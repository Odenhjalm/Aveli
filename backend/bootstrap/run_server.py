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
print("[ENV] DATABASE_URL =", os.getenv("DATABASE_URL"))
print("[ENV] MCP_MODE =", os.getenv("MCP_MODE"))
print("[ENV] SUPABASE_URL =", os.getenv("SUPABASE_URL"))

# --- STANDARD IMPORTS ---
import asyncio
import sys

from backend.bootstrap.baseline_v2 import BaselineV2Error, ensure_v2_baseline
from backend.scripts.bootstrap_gate import ensure_local_execution_ready


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
def _host() -> str:
    return str(os.environ.get("HOST") or "127.0.0.1").strip() or "127.0.0.1"


def _port() -> int:
    raw = str(os.environ.get("PORT") or "8080").strip()
    try:
        return int(raw)
    except ValueError as exc:
        raise SystemExit(f"[AVELI] Invalid PORT value: {raw}") from exc


# --- MAIN ENTRYPOINT ---
def main() -> None:
    print("[AVELI] Bootstrapping backend...")

    # Ensure environment + DB readiness
    ensure_local_execution_ready()

    try:
        baseline_status = ensure_v2_baseline()
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

    print(f"[AVELI] HOST={_host()} PORT={_port()}")

    # Start server
    import uvicorn

    uvicorn.run(
        "app.main:app",
        app_dir=str(BACKEND_DIR),
        host=_host(),
        port=_port(),
        reload=False,
    )


# --- CLI ---
if __name__ == "__main__":
    main()
