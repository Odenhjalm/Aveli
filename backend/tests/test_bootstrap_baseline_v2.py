from __future__ import annotations

from pathlib import Path

import pytest

from backend.bootstrap import baseline_v2


def test_baseline_mode_defaults_to_v2(monkeypatch) -> None:
    monkeypatch.delenv("BASELINE_MODE", raising=False)

    assert baseline_v2.baseline_mode() == "V2"


def test_ensure_v2_baseline_rejects_unsupported_mode(monkeypatch) -> None:
    monkeypatch.setenv("BASELINE_MODE", "legacy")

    with pytest.raises(baseline_v2.BaselineV2Error, match="unsupported BASELINE_MODE"):
        baseline_v2.ensure_v2_baseline(
            "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local"
        )


def test_v2_slot_order_is_explicit_and_complete() -> None:
    assert baseline_v2.EXPECTED_V2_SLOTS == tuple(
        path.name
        for path in sorted(Path("backend/supabase/baseline_v2_slots").glob("V2_*.sql"))
    )


def test_run_server_invokes_v2_baseline_gate() -> None:
    source = Path("backend/bootstrap/run_server.py").read_text(encoding="utf-8")

    assert "ensure_v2_baseline()" in source
    assert "BASELINE_MODE=" in source
    assert "SCHEMA_HASH=" in source
