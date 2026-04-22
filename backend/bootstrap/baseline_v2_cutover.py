from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

from psycopg import sql

from backend.bootstrap import baseline_v2
from backend.bootstrap.load_env import load_env

ROOT_DIR = Path(__file__).resolve().parents[2]
CUTOVER_PLAN_FILE = ROOT_DIR / "backend" / "supabase" / "baseline_v2_production_cutover.json"
RELEASE_COMMAND_VALUE = "python -m backend.bootstrap.baseline_v2_cutover"


class BaselineV2CutoverError(RuntimeError):
    """Raised when the bounded production cutover cannot proceed safely."""


def _normalize_counts(value: dict[str, object]) -> dict[str, int]:
    return {str(key): int(item) for key, item in value.items()}


def _load_cutover_plan() -> dict[str, Any]:
    try:
        payload = json.loads(CUTOVER_PLAN_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise BaselineV2CutoverError(f"missing cutover plan: {CUTOVER_PLAN_FILE}") from exc
    except json.JSONDecodeError as exc:
        raise BaselineV2CutoverError(f"invalid cutover plan JSON: {exc}") from exc

    if not isinstance(payload, dict):
        raise BaselineV2CutoverError("cutover plan must be a JSON object")
    if payload.get("manifest_version") != 1:
        raise BaselineV2CutoverError("cutover plan manifest_version must be 1")
    if payload.get("status") != "CANONICAL":
        raise BaselineV2CutoverError("cutover plan status must be CANONICAL")
    if payload.get("execution_mode") != "release_command_only":
        raise BaselineV2CutoverError("cutover plan execution_mode must be release_command_only")
    if payload.get("release_command") != RELEASE_COMMAND_VALUE:
        raise BaselineV2CutoverError("cutover plan release_command is invalid")
    if (
        payload.get("schema_hash_algorithm")
        != "backend.bootstrap.baseline_v2.app_schema_fingerprint_v2"
    ):
        raise BaselineV2CutoverError("cutover plan schema_hash_algorithm is invalid")

    target = payload.get("target")
    if not isinstance(target, dict):
        raise BaselineV2CutoverError("cutover plan target must be an object")

    from_state = payload.get("from")
    if not isinstance(from_state, dict):
        raise BaselineV2CutoverError("cutover plan from must be an object")

    steps = payload.get("steps")
    if not isinstance(steps, list) or not steps:
        raise BaselineV2CutoverError("cutover plan must contain a non-empty steps list")

    post_conditions = payload.get("post_conditions")
    if not isinstance(post_conditions, dict):
        raise BaselineV2CutoverError("cutover plan post_conditions must be an object")

    return payload


def _validate_cutover_plan_against_lock(
    lock: dict[str, Any],
    plan: dict[str, Any],
) -> dict[str, Any]:
    slots = lock.get("slots")
    if not isinstance(slots, list) or not slots:
        raise BaselineV2CutoverError("lock slots are invalid")

    target = dict(plan["target"])
    from_state = dict(plan["from"])
    steps = [dict(step) for step in plan["steps"]]
    verification = dict(lock["schema_verification"])

    expected_target_counts = _normalize_counts(dict(verification["expected_counts"]))
    target_counts = _normalize_counts(dict(target["counts"]))
    from_counts = _normalize_counts(dict(from_state["counts"]))

    if int(target["slot_count"]) != len(slots):
        raise BaselineV2CutoverError("cutover target slot_count does not match the lock")
    if str(target["last_slot"]) != str(slots[-1]["filename"]):
        raise BaselineV2CutoverError("cutover target last_slot does not match the lock")
    if str(target["schema_hash"]) != str(verification["expected_schema_hash"]):
        raise BaselineV2CutoverError("cutover target schema_hash does not match the lock")
    if target_counts != expected_target_counts:
        raise BaselineV2CutoverError("cutover target counts do not match the lock")

    previous_slot_count = int(from_state["slot_count"])
    if previous_slot_count < 1 or previous_slot_count >= int(target["slot_count"]):
        raise BaselineV2CutoverError("cutover from.slot_count must be below the target slot_count")
    if str(from_state["last_slot"]) != str(slots[previous_slot_count - 1]["filename"]):
        raise BaselineV2CutoverError("cutover from.last_slot does not match the lock")

    expected_step_slots = list(range(previous_slot_count + 1, len(slots) + 1))
    actual_step_slots = [int(step["slot"]) for step in steps]
    if actual_step_slots != expected_step_slots:
        raise BaselineV2CutoverError(
            f"cutover steps must be contiguous lock slots {expected_step_slots}, got {actual_step_slots}"
        )

    for step in steps:
        slot_number = int(step["slot"])
        lock_entry = dict(slots[slot_number - 1])
        if str(step["filename"]) != str(lock_entry["filename"]):
            raise BaselineV2CutoverError(f"cutover step {slot_number} filename does not match the lock")
        if str(step["path"]) != str(lock_entry["path"]):
            raise BaselineV2CutoverError(f"cutover step {slot_number} path does not match the lock")
        if str(step["sha256"]) != str(lock_entry["sha256"]):
            raise BaselineV2CutoverError(f"cutover step {slot_number} sha256 does not match the lock")
        post_counts = _normalize_counts(dict(step["post_counts"]))
        if slot_number == int(target["slot_count"]):
            if str(step["post_schema_hash"]) != str(target["schema_hash"]):
                raise BaselineV2CutoverError("final cutover step hash does not match the target")
            if post_counts != target_counts:
                raise BaselineV2CutoverError("final cutover step counts do not match the target")

    return {
        "from": {
            "slot_count": previous_slot_count,
            "last_slot": str(from_state["last_slot"]),
            "schema_hash": str(from_state["schema_hash"]),
            "counts": from_counts,
        },
        "target": {
            "slot_count": int(target["slot_count"]),
            "last_slot": str(target["last_slot"]),
            "schema_hash": str(target["schema_hash"]),
            "counts": target_counts,
        },
        "steps": [
            {
                "slot": int(step["slot"]),
                "filename": str(step["filename"]),
                "path": str(step["path"]),
                "sha256": str(step["sha256"]),
                "post_schema_hash": str(step["post_schema_hash"]),
                "post_counts": _normalize_counts(dict(step["post_counts"])),
            }
            for step in steps
        ],
        "post_conditions": {
            "existing_table_row_counts_unchanged": bool(
                plan["post_conditions"].get("existing_table_row_counts_unchanged")
            ),
            "new_tables": [str(item) for item in plan["post_conditions"].get("new_tables", [])],
        },
    }


def _assert_release_machine() -> None:
    if str(os.environ.get("RELEASE_COMMAND") or "").strip() != "1":
        raise BaselineV2CutoverError(
            "Baseline V2 cutover is release-command-only; RELEASE_COMMAND=1 is required"
        )


def _read_schema_state(conn) -> dict[str, Any]:
    return {
        "schema_hash": baseline_v2._schema_fingerprint(conn),
        "counts": baseline_v2._schema_counts(conn),
    }


def _schema_state_equals(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return str(left["schema_hash"]) == str(right["schema_hash"]) and _normalize_counts(
        dict(left["counts"])
    ) == _normalize_counts(dict(right["counts"]))


def _list_existing_app_tables(conn) -> list[str]:
    rows = baseline_v2._fetchall(
        conn,
        """
        select n.nspname, c.relname
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'app'
           and c.relkind = 'r'
         order by 1
        """,
    )
    return [f"{row[0]}.{row[1]}" for row in rows]


def _qualified_table_count(conn, relation: str) -> int:
    if "." not in relation:
        raise BaselineV2CutoverError(f"expected schema-qualified relation, got {relation!r}")
    schema_name, relation_name = relation.split(".", 1)
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("select count(*) from {}.{}").format(
                sql.Identifier(schema_name),
                sql.Identifier(relation_name),
            )
        )
        row = cur.fetchone()
    return int(row[0]) if row else 0


def _table_counts(conn, relations: list[str]) -> dict[str, int]:
    return {relation: _qualified_table_count(conn, relation) for relation in relations}


def _changed_existing_tables(before: dict[str, int], after: dict[str, int]) -> dict[str, dict[str, int]]:
    return {
        relation: {"before": before[relation], "after": after[relation]}
        for relation in before
        if before[relation] != after[relation]
    }


def _apply_cutover_step(conn, step: dict[str, Any]) -> dict[str, Any]:
    path = ROOT_DIR / step["path"]
    if not path.is_file():
        raise BaselineV2CutoverError(f"cutover step file is missing: {step['path']}")
    if baseline_v2._sha256_lf(path) != step["sha256"]:
        raise BaselineV2CutoverError(f"cutover step file hash mismatch: {step['path']}")

    conn.execute(path.read_text(encoding="utf-8"))
    observed = _read_schema_state(conn)
    expected = {
        "schema_hash": step["post_schema_hash"],
        "counts": step["post_counts"],
    }
    if not _schema_state_equals(observed, expected):
        raise BaselineV2CutoverError(
            "cutover step verification failed for "
            f"{step['filename']}: expected {expected}, got {observed}"
        )
    return observed


def run_cutover(database_url: str | None = None) -> dict[str, Any]:
    _assert_release_machine()
    load_env()

    if str(os.environ.get("APP_ENV") or "").strip().lower() != "production":
        raise BaselineV2CutoverError("Baseline V2 cutover is production-only; APP_ENV=production is required")

    lock = baseline_v2.verify_v2_lock()
    plan = _validate_cutover_plan_against_lock(lock, _load_cutover_plan())
    url = baseline_v2._database_url(database_url)
    baseline_v2.validate_runtime_database_url(url)

    target_state = {
        "schema_hash": plan["target"]["schema_hash"],
        "counts": plan["target"]["counts"],
    }
    predecessor_state = {
        "schema_hash": plan["from"]["schema_hash"],
        "counts": plan["from"]["counts"],
    }

    with baseline_v2.psycopg.connect(url, connect_timeout=5) as conn:
        existing_tables = _list_existing_app_tables(conn)
        pre_counts = _table_counts(conn, existing_tables)
        pre_state = _read_schema_state(conn)

        if _schema_state_equals(pre_state, target_state):
            action = "noop"
            post_state = pre_state
            post_counts = pre_counts
            changed_existing_tables: dict[str, dict[str, int]] = {}
            new_table_counts = _table_counts(conn, list(plan["post_conditions"]["new_tables"]))
        else:
            if not _schema_state_equals(pre_state, predecessor_state):
                raise BaselineV2CutoverError(
                    "production DB is not at the bounded predecessor state required by the cutover plan; "
                    f"expected {predecessor_state}, got {pre_state}"
                )

            action = "applied"
            with conn.transaction():
                for step in plan["steps"]:
                    post_state = _apply_cutover_step(conn, step)
                post_counts = _table_counts(conn, existing_tables)
                changed_existing_tables = _changed_existing_tables(pre_counts, post_counts)
                if (
                    plan["post_conditions"]["existing_table_row_counts_unchanged"]
                    and changed_existing_tables
                ):
                    raise BaselineV2CutoverError(
                        "existing app table row counts changed during cutover: "
                        f"{json.dumps(changed_existing_tables, sort_keys=True)}"
                    )
                new_table_counts = _table_counts(conn, list(plan["post_conditions"]["new_tables"]))

    runtime_status = baseline_v2.verify_v2_runtime(database_url=url)
    final_state = {
        "schema_hash": str(runtime_status["schema_hash"]),
        "counts": _normalize_counts(dict(runtime_status["counts"])),
    }
    if not _schema_state_equals(final_state, target_state):
        raise BaselineV2CutoverError(
            "post-cutover runtime verification did not converge to the lock target: "
            f"expected {target_state}, got {final_state}"
        )

    applied_slots = [step["filename"] for step in plan["steps"]] if action == "applied" else []
    return {
        "action": action,
        "pre_state": {
            "schema_hash": str(pre_state["schema_hash"]),
            "counts": _normalize_counts(dict(pre_state["counts"])),
        },
        "post_state": {
            "schema_hash": str(final_state["schema_hash"]),
            "counts": _normalize_counts(dict(final_state["counts"])),
        },
        "target_slot_count": int(plan["target"]["slot_count"]),
        "target_last_slot": str(plan["target"]["last_slot"]),
        "applied_slots": applied_slots,
        "existing_tables": existing_tables,
        "existing_table_row_counts_unchanged": not changed_existing_tables,
        "changed_existing_tables": changed_existing_tables,
        "new_table_counts": new_table_counts,
        "runtime_profile": str(runtime_status["profile"]),
        "runtime_state": str(runtime_status["state"]),
    }


def main() -> int:
    try:
        result = run_cutover()
    except Exception as exc:
        print("BASELINE_V2_CUTOVER_STATUS=FAIL")
        print(f"FAILURE={exc}")
        print("FINAL_STATE=STOP")
        return 1

    print("BASELINE_V2_CUTOVER_STATUS=PASS")
    print(f"PROMOTION_ACTION={result['action']}")
    print(f"PRE_SCHEMA_HASH={result['pre_state']['schema_hash']}")
    print(f"PRE_COUNTS={json.dumps(result['pre_state']['counts'], sort_keys=True)}")
    print(f"POST_SCHEMA_HASH={result['post_state']['schema_hash']}")
    print(f"POST_COUNTS={json.dumps(result['post_state']['counts'], sort_keys=True)}")
    print(f"TARGET_SLOT_COUNT={result['target_slot_count']}")
    print(f"TARGET_LAST_SLOT={result['target_last_slot']}")
    print(f"APPLIED_SLOTS={json.dumps(result['applied_slots'])}")
    print(
        "EXISTING_TABLE_ROW_COUNTS_UNCHANGED="
        + ("1" if result["existing_table_row_counts_unchanged"] else "0")
    )
    print(f"CHANGED_EXISTING_TABLES={json.dumps(result['changed_existing_tables'], sort_keys=True)}")
    print(f"NEW_TABLE_COUNTS={json.dumps(result['new_table_counts'], sort_keys=True)}")
    print(f"RUNTIME_PROFILE={result['runtime_profile']}")
    print(f"RUNTIME_STATE={result['runtime_state']}")
    print("FINAL_STATE=GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
