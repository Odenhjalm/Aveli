from __future__ import annotations

import importlib
import io
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Callable, Iterable

from backend.bootstrap.baseline_v2 import verify_v2_runtime
from backend.scripts.bootstrap_gate import ensure_runtime_execution_ready

ROOT_DIR = Path(__file__).resolve().parents[2]
BACKEND_DIR = ROOT_DIR / "backend"
APP_DIR = BACKEND_DIR / "app"
GATE_PREFIX = "[AVELI GATE]"


class DeploymentGateError(RuntimeError):
    """Raised when a deployment gate check blocks release."""


def _prepare_import_paths() -> None:
    for path in (ROOT_DIR, BACKEND_DIR):
        path_text = str(path)
        if path_text not in sys.path:
            sys.path.insert(0, path_text)


def _display_path(path: Path) -> str:
    try:
        return path.relative_to(ROOT_DIR).as_posix()
    except ValueError:
        return path.as_posix()


def _module_name_for_path(path: Path) -> str:
    relative = path.relative_to(APP_DIR).with_suffix("")
    parts = list(relative.parts)
    if parts[-1] == "__init__":
        parts = parts[:-1]
    return ".".join(("app", *parts)) if parts else "app"


def _iter_app_module_targets() -> Iterable[tuple[Path, str]]:
    if not APP_DIR.is_dir():
        raise DeploymentGateError(f"{_display_path(APP_DIR)} is missing")

    for path in sorted(APP_DIR.rglob("*.py"), key=lambda item: item.as_posix()):
        if "__pycache__" in path.parts:
            continue
        yield path, _module_name_for_path(path)


def run_import_check() -> None:
    _prepare_import_paths()

    for path, module_name in _iter_app_module_targets():
        try:
            importlib.import_module(module_name)
        except BaseException as exc:
            raise DeploymentGateError(
                f"{_display_path(path)} ({module_name}): "
                f"{exc.__class__.__name__}: {exc}"
            ) from exc


def run_baseline_check() -> None:
    try:
        with redirect_stdout(io.StringIO()):
            status = verify_v2_runtime()
    except Exception as exc:
        raise DeploymentGateError(f"{exc.__class__.__name__}: {exc}") from exc

    if status.get("state") != "verified":
        actual_state = status.get("state")
        raise DeploymentGateError(
            f"BASELINE_V2_STATUS=FAIL: expected state='verified', got {actual_state!r}"
        )


def _failure_from_output(output: str) -> str | None:
    for line in reversed(output.splitlines()):
        if line.startswith("FAILURE="):
            return line.split("=", 1)[1]
    return None


def run_runtime_check() -> None:
    output = io.StringIO()
    try:
        with redirect_stdout(output):
            state = ensure_runtime_execution_ready()
    except SystemExit as exc:
        reason = _failure_from_output(output.getvalue())
        if not reason:
            reason = f"runtime readiness exited with code {exc.code}"
        raise DeploymentGateError(reason) from exc
    except Exception as exc:
        raise DeploymentGateError(f"{exc.__class__.__name__}: {exc}") from exc

    if state.get("FINAL_STATE") != "GO":
        final_state = state.get("FINAL_STATE")
        reason = state.get("FAILURE") or f"unexpected FINAL_STATE={final_state!r}"
        raise DeploymentGateError(reason)


Check = Callable[[], None]


def _run_check(label: str, check: Check) -> bool:
    try:
        check()
    except DeploymentGateError as exc:
        print(f"{GATE_PREFIX} {label}: FAIL")
        print(f"REASON: {exc}")
        print("FINAL: BLOCKED")
        return False

    print(f"{GATE_PREFIX} {label}: PASS")
    return True


def run_gate(
    *,
    import_check: Check = run_import_check,
    baseline_check: Check = run_baseline_check,
    runtime_check: Check = run_runtime_check,
) -> int:
    checks: tuple[tuple[str, Check], ...] = (
        ("IMPORT CHECK", import_check),
        ("BASELINE CHECK", baseline_check),
        ("RUNTIME CHECK", runtime_check),
    )

    for label, check in checks:
        if not _run_check(label, check):
            return 1

    print(f"{GATE_PREFIX} FINAL: GO")
    return 0


def main() -> int:
    return run_gate()


if __name__ == "__main__":
    sys.exit(main())
