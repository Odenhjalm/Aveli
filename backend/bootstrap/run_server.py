from __future__ import annotations

import asyncio
import os
from pathlib import Path
import sys


ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"


def _apply_windows_selector_policy() -> None:
    """Use a psycopg-compatible loop policy before uvicorn bootstraps on Windows."""

    if sys.platform != "win32":
        return

    selector_policy_type = getattr(asyncio, "WindowsSelectorEventLoopPolicy", None)
    if selector_policy_type is None:
        return

    current_policy = asyncio.get_event_loop_policy()
    if isinstance(current_policy, selector_policy_type):
        return

    asyncio.set_event_loop_policy(selector_policy_type())


def _host() -> str:
    return str(os.environ.get("HOST") or "127.0.0.1").strip() or "127.0.0.1"


def _port() -> int:
    raw = str(os.environ.get("PORT") or "8080").strip()
    try:
        return int(raw)
    except ValueError as exc:  # pragma: no cover - defensive CLI guard
        raise SystemExit(f"Invalid PORT value: {raw}") from exc


def main() -> None:
    _apply_windows_selector_policy()

    # Import uvicorn only after the Windows loop policy guard is applied so the
    # backend can start deterministically on Windows without reload.
    import uvicorn

    uvicorn.run(
        "app.main:app",
        app_dir=str(BACKEND_DIR),
        host=_host(),
        port=_port(),
        reload=False,
    )


if __name__ == "__main__":
    main()
