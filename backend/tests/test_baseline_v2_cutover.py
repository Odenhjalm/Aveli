from __future__ import annotations

import json
from pathlib import Path

import pytest
from psycopg import sql

from backend.bootstrap import baseline_v2_cutover

ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_v2_slots.lock.json"


def _load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def _lock_entries() -> list[dict]:
    return baseline_v2_cutover._lock_slot_entries(_load_lock())


def test_cutover_lock_matches_current_lock_final_slot() -> None:
    entries = _lock_entries()
    lock = _load_lock()

    assert entries[-1]["slot"] == len(lock["slots"])
    assert entries[-1]["filename"] == lock["slots"][-1]["filename"]
    assert entries[-1]["path"] == lock["slots"][-1]["path"]
    assert entries[-1]["sha256"] == lock["slots"][-1]["sha256"]
    assert entries[-1]["post_counts"] == lock["schema_verification"]["expected_counts"]


def test_cutover_plan_noops_when_db_already_matches_current_final_slot() -> None:
    entries = _lock_entries()
    final_slot = len(entries)
    plan = baseline_v2_cutover._build_cutover_plan(
        entries,
        {
            "state_hash": entries[-1]["post_state_hash"],
            "counts": entries[-1]["post_counts"],
        },
    )

    assert plan["action"] == "noop"
    assert plan["current_slot"]["slot"] == final_slot
    assert plan["target_slot"]["slot"] == final_slot
    assert plan["artifact_slot"]["slot"] == final_slot
    assert plan["applied_slot"] is None


def test_cutover_plan_applies_exact_next_slot_for_current_release() -> None:
    entries = _lock_entries()
    final_slot = len(entries)
    plan = baseline_v2_cutover._build_cutover_plan(
        entries,
        {
            "state_hash": entries[-2]["post_state_hash"],
            "counts": entries[-2]["post_counts"],
        },
    )

    assert plan["action"] == "apply"
    assert plan["current_slot"]["slot"] == final_slot - 1
    assert plan["target_slot"]["slot"] == final_slot
    assert plan["artifact_slot"]["slot"] == final_slot
    assert plan["applied_slot"]["filename"] == entries[-1]["filename"]


def test_cutover_plan_would_handle_hypothetical_24_to_25() -> None:
    entries = _lock_entries()
    final_slot = len(entries)
    hypothetical_entries = [
        *entries,
        {
            "slot": final_slot + 1,
            "filename": f"V2_{final_slot + 1:04d}_hypothetical.sql",
            "path": f"backend/supabase/baseline_v2_slots/V2_{final_slot + 1:04d}_hypothetical.sql",
            "sha256": "f" * 64,
            "post_state_hash": "e" * 64,
            "post_counts": {
                **entries[-1]["post_counts"],
                "tables": entries[-1]["post_counts"]["tables"] + 1,
            },
        },
    ]
    plan = baseline_v2_cutover._build_cutover_plan(
        hypothetical_entries,
        {
            "state_hash": entries[-1]["post_state_hash"],
            "counts": entries[-1]["post_counts"],
        },
    )

    assert plan["action"] == "apply"
    assert plan["current_slot"]["slot"] == final_slot
    assert plan["target_slot"]["slot"] == final_slot + 1
    assert plan["artifact_slot"]["slot"] == final_slot + 1
    assert plan["applied_slot"]["filename"] == f"V2_{final_slot + 1:04d}_hypothetical.sql"


def test_cutover_plan_rejects_db_not_at_an_exact_lock_slot() -> None:
    entries = _lock_entries()

    with pytest.raises(
        baseline_v2_cutover.BaselineV2CutoverError,
        match="does not match any accepted lock slot state",
    ):
        baseline_v2_cutover._build_cutover_plan(
            entries,
            {
                "state_hash": "deadbeef" * 8,
                "counts": dict(entries[-1]["post_counts"]),
            },
        )


def test_cutover_plan_rejects_more_than_one_unapplied_slot_gap() -> None:
    entries = _lock_entries()
    stale_entry = entries[-3]

    with pytest.raises(
        baseline_v2_cutover.BaselineV2CutoverError,
        match="more than one unapplied slot",
    ):
        baseline_v2_cutover._build_cutover_plan(
            entries,
            {
                "state_hash": stale_entry["post_state_hash"],
                "counts": stale_entry["post_counts"],
            },
        )


def test_cutover_main_requires_release_command(monkeypatch) -> None:
    monkeypatch.delenv("RELEASE_COMMAND", raising=False)

    with pytest.raises(
        baseline_v2_cutover.BaselineV2CutoverError,
        match="release-command-only",
    ):
        baseline_v2_cutover._assert_release_machine()


def test_list_existing_app_tables_never_sends_percent_i_placeholders(monkeypatch) -> None:
    captured: dict[str, object] = {}

    def _fake_fetchall(conn, query: str, params: tuple = ()) -> list[tuple[str, str]]:
        captured["query"] = query
        captured["params"] = params
        return [("app", "courses"), ("app", "course_families")]

    monkeypatch.setattr(baseline_v2_cutover.baseline_v2, "_fetchall", _fake_fetchall)

    tables = baseline_v2_cutover._list_existing_app_tables(conn=object())

    assert tables == ["app.courses", "app.course_families"]
    assert "%I" not in str(captured["query"])
    assert captured["params"] == ()


def test_qualified_table_count_uses_psycopg_composable_sql() -> None:
    captured: dict[str, object] = {}

    class _FakeCursor:
        def execute(self, query, params=None) -> None:
            captured["query"] = query
            captured["params"] = params

        def fetchone(self):
            return (7,)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

    class _FakeConnection:
        def cursor(self):
            return _FakeCursor()

    count = baseline_v2_cutover._qualified_table_count(_FakeConnection(), "app.course_families")

    assert count == 7
    assert isinstance(captured["query"], sql.Composed)
    assert captured["params"] is None


def test_cutover_mechanism_contains_no_destructive_sql_of_its_own() -> None:
    source = (ROOT / "backend" / "bootstrap" / "baseline_v2_cutover.py").read_text(
        encoding="utf-8"
    ).lower()

    assert "delete from " not in source
    assert "truncate " not in source
    assert "drop table " not in source
    assert "drop schema " not in source
