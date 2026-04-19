from __future__ import annotations

import os
import runpy
import sys
from pathlib import Path

from backend.bootstrap.baseline_v2 import BaselineV2Error, verify_v2_runtime
from backend.bootstrap.load_env import load_env
from backend.scripts.bootstrap_gate import ensure_runtime_execution_ready


ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"


def _prepare_app_imports() -> None:
    for candidate in (str(ROOT_DIR), str(BACKEND_DIR)):
        if candidate not in sys.path:
            sys.path.insert(0, candidate)


def main() -> None:
    load_env()
    _prepare_app_imports()

    print("[AVELI] Bootstrapping worker...")

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

    os.environ.setdefault("RUN_MEDIA_WORKER", "true")
    os.environ.setdefault("RUN_COURSE_DRIP_WORKER", "true")
    runpy.run_module("app.services.mvp_worker", run_name="__main__")


if __name__ == "__main__":
    main()
