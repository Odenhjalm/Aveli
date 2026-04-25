from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

import backend.bootstrap.run_server as run_server_module


def _load_run_server():
    return importlib.reload(run_server_module)


def _set_local_runtime_env(monkeypatch: pytest.MonkeyPatch, run_server) -> None:
    monkeypatch.setenv("APP_ENV", "local")
    monkeypatch.setenv("MCP_MODE", "local")
    for key in run_server.CLOUD_RUNTIME_ENV_KEYS:
        monkeypatch.delenv(key, raising=False)


def _configure_gate_fixture(
    monkeypatch: pytest.MonkeyPatch,
    run_server,
    tmp_path: Path,
    *,
    env_text: str,
    mcp_text: str,
) -> Path:
    fixture_root = tmp_path / "fixture"
    (fixture_root / ".vscode").mkdir(parents=True)
    (fixture_root / "ops").mkdir(parents=True)

    env_path = fixture_root / ".env"
    mcp_path = fixture_root / ".vscode" / "mcp.json"

    env_path.write_text(env_text, encoding="utf-8")
    mcp_path.write_text(mcp_text, encoding="utf-8")

    monkeypatch.setattr(run_server, "ROOT_DIR", fixture_root)
    monkeypatch.setattr(run_server, "ROOT_ENV_PATH", env_path)
    monkeypatch.setattr(
        run_server,
        "MCP_BOOTSTRAP_GATE_PATH",
        fixture_root / "ops" / "mcp_bootstrap_gate.ps1",
    )

    return mcp_path


def test_mcp_gate_process_runs_with_passthrough_output(monkeypatch) -> None:
    run_server = _load_run_server()
    recorded: dict[str, object] = {}

    def fake_run(command, *, cwd, check):
        recorded["command"] = command
        recorded["cwd"] = cwd
        recorded["check"] = check
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(run_server.sys, "platform", "win32")
    monkeypatch.setattr(run_server.subprocess, "run", fake_run)

    run_server._run_mcp_bootstrap_gate()

    assert recorded == {
        "command": [
            "powershell.exe",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(run_server.MCP_BOOTSTRAP_GATE_PATH),
        ],
        "cwd": str(run_server.ROOT_DIR),
        "check": False,
    }


def test_mcp_gate_loads_root_env_without_mutating_mcp_config(monkeypatch, tmp_path: Path) -> None:
    run_server = _load_run_server()
    monkeypatch.delenv("CONTEXT7_TOKEN", raising=False)
    monkeypatch.setattr(run_server.sys, "platform", "win32")

    original_text = '{\n  "servers": {\n    "context7": {\n      "headers": {\n        "Authorization": "Bearer ${CONTEXT7_TOKEN}"\n      }\n    }\n  }\n}\n'
    mcp_path = _configure_gate_fixture(
        monkeypatch,
        run_server,
        tmp_path,
        env_text="CONTEXT7_TOKEN=ctx_abcdefghijklmnopqrstuvwxyz\n",
        mcp_text=original_text,
    )

    observed: dict[str, object] = {}

    def fake_run(command, *, cwd, check):
        observed["command"] = command
        observed["cwd"] = cwd
        observed["check"] = check
        observed["env_value"] = os.environ.get("CONTEXT7_TOKEN")
        observed["mcp_text"] = mcp_path.read_text(encoding="utf-8")
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(run_server.subprocess, "run", fake_run)

    run_server._run_mcp_bootstrap_gate()

    assert observed["env_value"] == "ctx_abcdefghijklmnopqrstuvwxyz"
    assert observed["mcp_text"] == original_text
    assert mcp_path.read_text(encoding="utf-8") == original_text


def test_mcp_gate_still_invokes_subprocess_when_placeholder_env_is_missing(
    monkeypatch,
    tmp_path: Path,
) -> None:
    run_server = _load_run_server()
    monkeypatch.delenv("CONTEXT7_TOKEN", raising=False)
    monkeypatch.setattr(run_server.sys, "platform", "win32")

    original_text = '{\n  "servers": {\n    "context7": {\n      "headers": {\n        "Authorization": "Bearer ${CONTEXT7_TOKEN}"\n      }\n    }\n  }\n}\n'
    mcp_path = _configure_gate_fixture(
        monkeypatch,
        run_server,
        tmp_path,
        env_text="",
        mcp_text=original_text,
    )

    observed: dict[str, object] = {}

    def fake_run(command, *, cwd, check):
        observed["command"] = command
        observed["cwd"] = cwd
        observed["check"] = check
        observed["env_value"] = os.environ.get("CONTEXT7_TOKEN")
        observed["mcp_text"] = mcp_path.read_text(encoding="utf-8")
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(run_server.subprocess, "run", fake_run)

    run_server._run_mcp_bootstrap_gate()

    assert observed["env_value"] is None
    assert observed["mcp_text"] == original_text
    assert mcp_path.read_text(encoding="utf-8") == original_text


def test_mcp_gate_nonzero_exit_stops_startup(monkeypatch) -> None:
    run_server = _load_run_server()

    monkeypatch.setattr(run_server.sys, "platform", "win32")
    monkeypatch.setattr(
        run_server.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(returncode=1),
    )

    with pytest.raises(SystemExit) as exc:
        run_server._run_mcp_bootstrap_gate()

    assert exc.value.code == 1


def test_main_does_not_start_backend_when_mcp_gate_fails(monkeypatch) -> None:
    run_server = _load_run_server()
    calls: list[tuple[str, object | None]] = []

    _set_local_runtime_env(monkeypatch, run_server)
    monkeypatch.setattr(run_server, "_port", lambda: 8080)

    def fail_gate() -> None:
        calls.append(("mcp_gate", None))
        raise SystemExit(1)

    monkeypatch.setattr(run_server, "_run_mcp_bootstrap_gate", fail_gate)
    monkeypatch.setattr(
        run_server,
        "ensure_runtime_execution_ready",
        lambda: calls.append(("runtime_gate", None)),
    )
    monkeypatch.setattr(
        run_server,
        "verify_v2_runtime",
        lambda: calls.append(("baseline_verify", None)),
    )
    monkeypatch.setattr(
        run_server,
        "_apply_windows_selector_policy",
        lambda: calls.append(("selector_policy", None)),
    )
    monkeypatch.setitem(
        sys.modules,
        "uvicorn",
        SimpleNamespace(run=lambda *args, **kwargs: calls.append(("uvicorn", kwargs))),
    )

    with pytest.raises(SystemExit) as exc:
        run_server.main()

    assert exc.value.code == 1
    assert calls == [("mcp_gate", None)]


def test_main_starts_backend_after_mcp_gate_passes(monkeypatch) -> None:
    run_server = _load_run_server()
    calls: list[tuple[str, object | None]] = []

    _set_local_runtime_env(monkeypatch, run_server)
    monkeypatch.setattr(run_server, "_port", lambda: 8080)
    monkeypatch.setattr(
        run_server,
        "_run_mcp_bootstrap_gate",
        lambda: calls.append(("mcp_gate", None)),
    )
    monkeypatch.setattr(
        run_server,
        "ensure_runtime_execution_ready",
        lambda: calls.append(("runtime_gate", None)),
    )

    def fake_verify_v2_runtime():
        calls.append(("baseline_verify", None))
        return {
            "mode": "runtime",
            "profile": "local",
            "state": "verified",
            "schema_hash": "hash123",
        }

    monkeypatch.setattr(run_server, "verify_v2_runtime", fake_verify_v2_runtime)
    monkeypatch.setattr(
        run_server,
        "_apply_windows_selector_policy",
        lambda: calls.append(("selector_policy", None)),
    )
    monkeypatch.setitem(
        sys.modules,
        "uvicorn",
        SimpleNamespace(run=lambda *args, **kwargs: calls.append(("uvicorn", kwargs))),
    )

    run_server.main()

    assert calls[0] == ("mcp_gate", None)
    assert [name for name, _ in calls[:4]] == [
        "mcp_gate",
        "runtime_gate",
        "baseline_verify",
        "selector_policy",
    ]
    assert calls[-1][0] == "uvicorn"
    assert calls[-1][1]["app_dir"] == str(run_server.BACKEND_DIR)
    assert calls[-1][1]["host"] == "0.0.0.0"
    assert calls[-1][1]["port"] == 8080
    assert calls[-1][1]["reload"] is False


def test_main_skips_mcp_gate_in_production_but_keeps_runtime_verification(
    monkeypatch,
    capsys,
) -> None:
    run_server = _load_run_server()
    calls: list[tuple[str, object | None]] = []

    monkeypatch.setenv("APP_ENV", "production")
    monkeypatch.setenv("FLY_APP_NAME", "aveli")
    monkeypatch.setenv("MCP_MODE", "local")
    monkeypatch.setattr(run_server, "_port", lambda: 8080)
    monkeypatch.setattr(
        run_server,
        "_run_mcp_bootstrap_gate",
        lambda: calls.append(("mcp_gate", None)),
    )
    monkeypatch.setattr(
        run_server,
        "ensure_runtime_execution_ready",
        lambda: calls.append(("runtime_gate", None)),
    )

    def fake_verify_v2_runtime():
        calls.append(("baseline_verify", None))
        return {
            "mode": "runtime",
            "profile": "hosted_supabase",
            "state": "verified",
            "schema_hash": "hash123",
        }

    monkeypatch.setattr(run_server, "verify_v2_runtime", fake_verify_v2_runtime)
    monkeypatch.setattr(
        run_server,
        "_apply_windows_selector_policy",
        lambda: calls.append(("selector_policy", None)),
    )
    monkeypatch.setitem(
        sys.modules,
        "uvicorn",
        SimpleNamespace(run=lambda *args, **kwargs: calls.append(("uvicorn", kwargs))),
    )

    run_server.main()

    assert ("mcp_gate", None) not in calls
    assert [name for name, _ in calls[:3]] == [
        "runtime_gate",
        "baseline_verify",
        "selector_policy",
    ]
    assert calls[-1][0] == "uvicorn"
    assert calls[-1][1]["host"] == "0.0.0.0"
    assert calls[-1][1]["port"] == 8080
    assert (
        "[AVELI] Skipping local MCP bootstrap gate in production/cloud runtime"
        in capsys.readouterr().out
    )
