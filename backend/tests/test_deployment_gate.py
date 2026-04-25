from __future__ import annotations

import pytest

from backend.bootstrap import deployment_gate


@pytest.fixture(autouse=True)
def _test_session_scope():
    yield "deployment-gate"


@pytest.fixture(autouse=True)
def _temp_media_root(tmp_path):
    yield tmp_path


@pytest.fixture(autouse=True)
def _local_supabase_registration_stub():
    yield


def test_import_failure_gate_fails(monkeypatch, capsys) -> None:
    imported_modules: list[str] = []
    downstream_calls: list[str] = []
    broken_path = deployment_gate.ROOT_DIR / "backend" / "app" / "broken.py"

    def module_targets():
        yield broken_path, "app.broken"
        yield deployment_gate.ROOT_DIR / "backend" / "app" / "late.py", "app.late"

    def import_module(module_name: str) -> None:
        imported_modules.append(module_name)
        raise ImportError("boom")

    monkeypatch.setattr(deployment_gate, "_iter_app_module_targets", module_targets)
    monkeypatch.setattr(deployment_gate.importlib, "import_module", import_module)

    def baseline_check() -> None:
        downstream_calls.append("baseline")

    def runtime_check() -> None:
        downstream_calls.append("runtime")

    exit_code = deployment_gate.run_gate(
        import_check=deployment_gate.run_import_check,
        baseline_check=baseline_check,
        runtime_check=runtime_check,
    )

    assert exit_code == 1
    assert imported_modules == ["app.broken"]
    assert downstream_calls == []
    assert capsys.readouterr().out.splitlines() == [
        "[AVELI GATE] IMPORT CHECK: FAIL",
        "REASON: backend/app/broken.py (app.broken): ImportError: boom",
        "FINAL: BLOCKED",
    ]


def test_baseline_failure_gate_fails(capsys) -> None:
    calls: list[str] = []

    def import_check() -> None:
        calls.append("import")

    def baseline_check() -> None:
        calls.append("baseline")
        raise deployment_gate.DeploymentGateError("BaselineV2Error: schema mismatch")

    def runtime_check() -> None:
        calls.append("runtime")

    exit_code = deployment_gate.run_gate(
        import_check=import_check,
        baseline_check=baseline_check,
        runtime_check=runtime_check,
    )

    assert exit_code == 1
    assert calls == ["import", "baseline"]
    assert capsys.readouterr().out.splitlines() == [
        "[AVELI GATE] IMPORT CHECK: PASS",
        "[AVELI GATE] BASELINE CHECK: FAIL",
        "REASON: BaselineV2Error: schema mismatch",
        "FINAL: BLOCKED",
    ]


def test_runtime_failure_gate_fails(capsys) -> None:
    calls: list[str] = []

    def import_check() -> None:
        calls.append("import")

    def baseline_check() -> None:
        calls.append("baseline")

    def runtime_check() -> None:
        calls.append("runtime")
        raise deployment_gate.DeploymentGateError("ENV_INVALID: DATABASE_URL is missing")

    exit_code = deployment_gate.run_gate(
        import_check=import_check,
        baseline_check=baseline_check,
        runtime_check=runtime_check,
    )

    assert exit_code == 1
    assert calls == ["import", "baseline", "runtime"]
    assert capsys.readouterr().out.splitlines() == [
        "[AVELI GATE] IMPORT CHECK: PASS",
        "[AVELI GATE] BASELINE CHECK: PASS",
        "[AVELI GATE] RUNTIME CHECK: FAIL",
        "REASON: ENV_INVALID: DATABASE_URL is missing",
        "FINAL: BLOCKED",
    ]


def test_all_valid_gate_passes(capsys) -> None:
    calls: list[str] = []

    exit_code = deployment_gate.run_gate(
        import_check=lambda: calls.append("import"),
        baseline_check=lambda: calls.append("baseline"),
        runtime_check=lambda: calls.append("runtime"),
    )

    assert exit_code == 0
    assert calls == ["import", "baseline", "runtime"]
    assert capsys.readouterr().out.splitlines() == [
        "[AVELI GATE] IMPORT CHECK: PASS",
        "[AVELI GATE] BASELINE CHECK: PASS",
        "[AVELI GATE] RUNTIME CHECK: PASS",
        "[AVELI GATE] FINAL: GO",
    ]
