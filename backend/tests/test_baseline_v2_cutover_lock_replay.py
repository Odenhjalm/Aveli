from __future__ import annotations

import copy
import json
import os
from contextlib import contextmanager
from pathlib import Path
from uuid import uuid4

import psycopg
import pytest
from psycopg import sql
from psycopg.conninfo import conninfo_to_dict, make_conninfo

from backend.bootstrap import baseline_v2, baseline_v2_cutover


ROOT = Path(__file__).resolve().parents[2]
LOCK_PATH = ROOT / "backend" / "supabase" / "baseline_v2_slots.lock.json"


def _load_lock() -> dict:
    return json.loads(LOCK_PATH.read_text(encoding="utf-8"))


def _admin_conninfo() -> str:
    if not os.getenv("DATABASE_URL"):
        pytest.skip("DATABASE_URL is required for isolated Baseline V2 cutover replay tests")
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = "postgres"
    return make_conninfo(**conninfo)


def _db_conninfo(db_name: str) -> str:
    conninfo = conninfo_to_dict(os.environ["DATABASE_URL"])
    conninfo["dbname"] = db_name
    return make_conninfo(**conninfo)


@contextmanager
def _isolated_database():
    db_name = f"aveli_cutover_replay_{uuid4().hex[:12]}"
    admin_conninfo = _admin_conninfo()
    database_conninfo = _db_conninfo(db_name)

    with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
        admin_conn.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(db_name)))

    try:
        with psycopg.connect(database_conninfo, autocommit=True) as conn:
            yield conn
    finally:
        with psycopg.connect(admin_conninfo, autocommit=True) as admin_conn:
            admin_conn.execute(
                """
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = %s
                  AND pid <> pg_backend_pid()
                """,
                (db_name,),
            )
            admin_conn.execute(sql.SQL("DROP DATABASE IF EXISTS {}").format(sql.Identifier(db_name)))


def _replay_to_slot(slot_number: int) -> dict[str, object]:
    slot_paths = list(baseline_v2._slot_paths())
    with _isolated_database() as conn:
        with conn.transaction():
            baseline_v2._ensure_local_substrate(conn)
            for path in slot_paths[:slot_number]:
                conn.execute(path.read_text(encoding="utf-8"))
        cutover_state = baseline_v2_cutover._read_schema_state(conn)
        return {
            "cutover_hash": cutover_state["state_hash"],
            "counts": cutover_state["counts"],
            "runtime_hash": baseline_v2._schema_fingerprint(conn),
        }


@pytest.mark.parametrize(
    ("slot_number", "expected_cutover_hash", "expected_runtime_hash"),
    (
        (
            25,
            "e36c9b2cbb3e963401ee061807607d162c948b8f101507f65ddcf10b7b276307",
            "fc0c1b6caaf7bebbdea905a4745d7af62cdeac615d10ffad5fb93ffe600d4e28",
        ),
        (
            26,
            "e3799c21f12637d84174a638b741e9ce947e0b9b4df9800f1aa94ce3b5ab6f87",
            "aa3b2cfe71b124ae990a69c5f9541ff08841a55f65291f7558709dcc5f3eec6c",
        ),
        (
            27,
            "3cfe178bba82e151dc462b9c1de0c6785ab7cfd7743abb0e43c4cd351df79b8d",
            "a9eb67c5bcaeff49547d8e9fb065d7f6be6a8231b43b19d48c938a06521b7040",
        ),
        (
            28,
            "048bcd82cc93141413bdec1337114e35cd4254a6af8fa38e4d66baf5084f330a",
            "be4df29d0ac6c6036e933acbe1005179d8e68081923918c2b9a4a4aa6bf04711",
        ),
        (
            29,
            "2b46e1197f4228d845736eaa6561a61b5364043236a25a16855809e770e6cc64",
            "61ecf976b5e8bf124685c06cbc3394d6461a1ae16e22ce25ea157cd76c30fdfb",
        ),
    ),
)
def test_cutover_post_state_hashes_match_clean_replay(
    slot_number: int,
    expected_cutover_hash: str,
    expected_runtime_hash: str,
) -> None:
    lock = _load_lock()
    observed = _replay_to_slot(slot_number)
    slot_entry = lock["slots"][slot_number - 1]

    assert observed["cutover_hash"] == expected_cutover_hash
    assert slot_entry["post_state_hash"] == expected_cutover_hash
    assert observed["runtime_hash"] == expected_runtime_hash
    assert observed["runtime_hash"] != slot_entry["post_state_hash"]
    assert observed["counts"] == slot_entry["post_counts"]


def test_slot_25_cutover_hash_is_stable_across_clean_replays() -> None:
    first = _replay_to_slot(25)
    second = _replay_to_slot(25)

    assert first == second


def test_exact_25_slot_artifact_would_allow_24_to_25_but_current_final_artifact_blocks() -> None:
    lock = _load_lock()
    current_entries = baseline_v2_cutover._lock_slot_entries(lock)
    slot_24_state = {
        "state_hash": current_entries[23]["post_state_hash"],
        "counts": current_entries[23]["post_counts"],
    }

    with pytest.raises(
        baseline_v2_cutover.BaselineV2CutoverError,
        match="more than one unapplied slot",
    ):
        baseline_v2_cutover._build_cutover_plan(current_entries, slot_24_state)

    slot_25_artifact = copy.deepcopy(lock)
    slot_25_artifact["slots"] = slot_25_artifact["slots"][:25]
    slot_25_artifact["schema_verification"]["expected_schema_hash"] = (
        "fc0c1b6caaf7bebbdea905a4745d7af62cdeac615d10ffad5fb93ffe600d4e28"
    )
    slot_25_artifact["schema_verification"]["expected_counts"] = dict(
        slot_25_artifact["slots"][-1]["post_counts"]
    )

    slot_25_entries = baseline_v2_cutover._lock_slot_entries(slot_25_artifact)
    plan = baseline_v2_cutover._build_cutover_plan(slot_25_entries, slot_24_state)

    assert plan["action"] == "apply"
    assert plan["current_slot"]["slot"] == 24
    assert plan["target_slot"]["slot"] == 25
    assert plan["artifact_slot"]["slot"] == 25
    assert plan["applied_slot"]["filename"] == "V2_0025_custom_drip_substrate.sql"
