from __future__ import annotations

import json
from pathlib import Path

import pytest

from backend.bootstrap import baseline_v2_cutover

ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_v2_slots.lock.json"
CUTOVER_PATH = ROOT / "backend" / "supabase" / "baseline_v2_production_cutover.json"


def _load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def _load_cutover() -> dict:
    return json.loads(CUTOVER_PATH.read_text(encoding="utf-8"))


def test_cutover_manifest_matches_current_lock() -> None:
    lock = _load_lock()
    plan = baseline_v2_cutover._validate_cutover_plan_against_lock(lock, _load_cutover())

    assert plan["target"]["slot_count"] == len(lock["slots"])
    assert plan["target"]["last_slot"] == lock["slots"][-1]["filename"]
    assert plan["steps"][-1]["filename"] == lock["slots"][-1]["filename"]
    assert plan["steps"][-1]["path"] == lock["slots"][-1]["path"]
    assert plan["steps"][-1]["sha256"] == lock["slots"][-1]["sha256"]
    assert plan["post_conditions"]["existing_table_row_counts_unchanged"] is True
    assert plan["post_conditions"]["new_tables"] == ["app.course_families"]


def test_cutover_manifest_only_allows_exact_predecessor_or_target() -> None:
    plan = baseline_v2_cutover._validate_cutover_plan_against_lock(_load_lock(), _load_cutover())

    predecessor = {
        "schema_hash": plan["from"]["schema_hash"],
        "counts": plan["from"]["counts"],
    }
    target = {
        "schema_hash": plan["target"]["schema_hash"],
        "counts": plan["target"]["counts"],
    }
    drift = {
        "schema_hash": "deadbeef",
        "counts": dict(plan["from"]["counts"]),
    }

    assert baseline_v2_cutover._schema_state_equals(predecessor, predecessor)
    assert baseline_v2_cutover._schema_state_equals(target, target)
    assert not baseline_v2_cutover._schema_state_equals(predecessor, target)
    assert not baseline_v2_cutover._schema_state_equals(predecessor, drift)


def test_cutover_main_requires_release_command(monkeypatch) -> None:
    monkeypatch.delenv("RELEASE_COMMAND", raising=False)

    with pytest.raises(
        baseline_v2_cutover.BaselineV2CutoverError,
        match="release-command-only",
    ):
        baseline_v2_cutover._assert_release_machine()
