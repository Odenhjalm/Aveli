from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from psycopg import sql

from backend.bootstrap import baseline_v2
from backend.bootstrap.load_env import load_env

ROOT_DIR = Path(__file__).resolve().parents[2]
RELEASE_COMMAND_VALUE = "python -m backend.bootstrap.baseline_v2_cutover"
CUTOVER_STATE_HASH_ALGORITHM = (
    "backend.bootstrap.baseline_v2_cutover.app_schema_state_fingerprint_v1"
)


class BaselineV2CutoverError(RuntimeError):
    """Raised when the bounded production cutover cannot proceed safely."""


def _normalize_counts(value: dict[str, object]) -> dict[str, int]:
    return {str(key): int(item) for key, item in value.items()}


def _lock_cutover_section(lock: dict[str, Any]) -> dict[str, Any]:
    payload = lock.get("release_cutover_verification")
    if not isinstance(payload, dict):
        raise BaselineV2CutoverError("lock release_cutover_verification is missing")
    if payload.get("schema_scope") != "app_owned_schema_only":
        raise BaselineV2CutoverError(
            "lock release_cutover_verification.schema_scope must be app_owned_schema_only"
        )
    if payload.get("state_hash_algorithm") != CUTOVER_STATE_HASH_ALGORITHM:
        raise BaselineV2CutoverError(
            "lock release_cutover_verification.state_hash_algorithm is invalid"
        )
    return payload


def _lock_slot_entries(lock: dict[str, Any]) -> list[dict[str, Any]]:
    _lock_cutover_section(lock)
    slots = list(baseline_v2._lock_slots(lock))
    verification = dict(lock["schema_verification"])
    expected_runtime_counts = _normalize_counts(dict(verification["expected_counts"]))

    seen_states: dict[tuple[str, tuple[tuple[str, int], ...]], int] = {}
    entries: list[dict[str, Any]] = []
    for raw_entry in slots:
        slot_number = int(raw_entry["slot"])
        post_state_hash = raw_entry.get("post_state_hash")
        post_counts = raw_entry.get("post_counts")
        if not isinstance(post_state_hash, str) or len(post_state_hash) != 64:
            raise BaselineV2CutoverError(
                f"lock slot {slot_number} is missing post_state_hash"
            )
        if not isinstance(post_counts, dict):
            raise BaselineV2CutoverError(
                f"lock slot {slot_number} is missing post_counts"
            )

        entry = {
            "slot": slot_number,
            "filename": str(raw_entry["filename"]),
            "path": str(raw_entry["path"]),
            "sha256": str(raw_entry["sha256"]),
            "post_state_hash": post_state_hash,
            "post_counts": _normalize_counts(post_counts),
        }
        state_key = (
            entry["post_state_hash"],
            tuple(sorted(entry["post_counts"].items())),
        )
        previous_slot = seen_states.get(state_key)
        if previous_slot is not None:
            raise BaselineV2CutoverError(
                "lock slot post-state metadata must be unique for deterministic promotion; "
                f"slots {previous_slot} and {slot_number} currently collide"
            )
        seen_states[state_key] = slot_number
        entries.append(entry)

    final_entry = entries[-1]
    if final_entry["post_counts"] != expected_runtime_counts:
        raise BaselineV2CutoverError(
            "final lock slot post_counts do not match schema_verification.expected_counts"
        )

    return entries


def _runtime_target_state(lock: dict[str, Any]) -> dict[str, Any]:
    verification = dict(lock["schema_verification"])
    return {
        "schema_hash": str(verification["expected_schema_hash"]),
        "counts": _normalize_counts(dict(verification["expected_counts"])),
    }


def _state_fingerprint(conn) -> str:
    payload = {
        "enums": baseline_v2._fetchall(
            conn,
            """
            select t.typname, array_agg(e.enumlabel order by e.enumsortorder)::text[]
              from pg_type t
              join pg_namespace n on n.oid = t.typnamespace
              join pg_enum e on e.enumtypid = t.oid
             where n.nspname = 'app'
             group by t.typname
             order by t.typname
            """,
        ),
        "relations": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, c.relname, c.relkind
              from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'app'
               and c.relkind in ('r', 'v', 'S')
             order by 1, 2, 3
            """,
        ),
        "columns": baseline_v2._fetchall(
            conn,
            """
            select table_schema, table_name, column_name, ordinal_position,
                   is_nullable, data_type, udt_schema, udt_name, column_default
              from information_schema.columns
             where table_schema = 'app'
             order by table_schema, table_name, ordinal_position
            """,
        ),
        "constraints": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, cls.relname, con.conname, con.contype,
                   pg_get_constraintdef(con.oid, true), con.convalidated,
                   coalesce(obj_description(con.oid, 'pg_constraint'), '')
              from pg_constraint con
              join pg_namespace n on n.oid = con.connamespace
              left join pg_class cls on cls.oid = con.conrelid
             where n.nspname = 'app'
             order by 1, 2, 3
            """,
        ),
        "triggers": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, cls.relname, tg.tgname, pg_get_triggerdef(tg.oid, true)
              from pg_trigger tg
              join pg_class cls on cls.oid = tg.tgrelid
              join pg_namespace n on n.oid = cls.relnamespace
             where n.nspname = 'app'
               and not tg.tgisinternal
             order by 1, 2, 3
            """,
        ),
        "functions": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
                   pg_get_function_result(p.oid), pg_get_functiondef(p.oid),
                   coalesce(obj_description(p.oid, 'pg_proc'), '')
              from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'app'
             order by 1, 2, 3
            """,
        ),
        "views": baseline_v2._fetchall(
            conn,
            """
            select schemaname, viewname, definition
              from pg_views
             where schemaname = 'app'
             order by 1, 2
            """,
        ),
        "indexes": baseline_v2._fetchall(
            conn,
            """
            select schemaname, tablename, indexname, indexdef
              from pg_indexes
             where schemaname = 'app'
             order by 1, 2, 3
            """,
        ),
        "relation_comments": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, c.relname, c.relkind, coalesce(obj_description(c.oid, 'pg_class'), '')
              from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'app'
               and c.relkind in ('r', 'v', 'S')
             order by 1, 2, 3
            """,
        ),
        "column_comments": baseline_v2._fetchall(
            conn,
            """
            select n.nspname, c.relname, a.attname, a.attnum,
                   coalesce(col_description(c.oid, a.attnum), '')
              from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
              join pg_attribute a on a.attrelid = c.oid
             where n.nspname = 'app'
               and c.relkind in ('r', 'v', 'S')
               and a.attnum > 0
               and not a.attisdropped
             order by 1, 2, 4
            """,
        ),
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()


def _read_schema_state(conn) -> dict[str, Any]:
    return {
        "state_hash": _state_fingerprint(conn),
        "counts": baseline_v2._schema_counts(conn),
    }


def _state_equals(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return str(left["state_hash"]) == str(right["state_hash"]) and _normalize_counts(
        dict(left["counts"])
    ) == _normalize_counts(dict(right["counts"]))


def _determine_current_slot(
    slot_entries: list[dict[str, Any]],
    observed_state: dict[str, Any],
) -> tuple[int, dict[str, Any]]:
    matches = [
        (index, entry)
        for index, entry in enumerate(slot_entries)
        if _state_equals(
            observed_state,
            {
                "state_hash": entry["post_state_hash"],
                "counts": entry["post_counts"],
            },
        )
    ]
    if not matches:
        raise BaselineV2CutoverError(
            "production DB does not match any accepted lock slot state; "
            f"observed {observed_state}"
        )
    if len(matches) != 1:
        matching_slots = [entry["slot"] for _, entry in matches]
        raise BaselineV2CutoverError(
            "production DB matches multiple lock slots; promotion is ambiguous: "
            f"{matching_slots}"
        )
    return matches[0]


def _build_cutover_plan(
    slot_entries: list[dict[str, Any]],
    observed_state: dict[str, Any],
) -> dict[str, Any]:
    current_index, current_entry = _determine_current_slot(slot_entries, observed_state)
    final_entry = slot_entries[-1]

    if current_index == len(slot_entries) - 1:
        return {
            "action": "noop",
            "current_slot": current_entry,
            "target_slot": current_entry,
            "artifact_slot": final_entry,
            "applied_slot": None,
        }

    next_entry = slot_entries[current_index + 1]
    if next_entry["slot"] != final_entry["slot"]:
        raise BaselineV2CutoverError(
            "release artifact carries more than one unapplied slot; "
            f"DB is at slot {current_entry['slot']}, exact next slot is {next_entry['slot']}, "
            f"artifact final slot is {final_entry['slot']}"
        )

    return {
        "action": "apply",
        "current_slot": current_entry,
        "target_slot": next_entry,
        "artifact_slot": final_entry,
        "applied_slot": next_entry,
    }


def _assert_release_machine() -> None:
    if str(os.environ.get("RELEASE_COMMAND") or "").strip() != "1":
        raise BaselineV2CutoverError(
            "Baseline V2 cutover is release-command-only; RELEASE_COMMAND=1 is required"
        )


def _runtime_state_equals(left: dict[str, Any], right: dict[str, Any]) -> bool:
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


def _apply_cutover_slot(conn, slot_entry: dict[str, Any]) -> dict[str, Any]:
    path = ROOT_DIR / slot_entry["path"]
    if not path.is_file():
        raise BaselineV2CutoverError(f"cutover slot file is missing: {slot_entry['path']}")
    if baseline_v2._sha256_lf(path) != slot_entry["sha256"]:
        raise BaselineV2CutoverError(f"cutover slot file hash mismatch: {slot_entry['path']}")

    conn.execute(path.read_text(encoding="utf-8"))
    observed = _read_schema_state(conn)
    expected = {
        "state_hash": slot_entry["post_state_hash"],
        "counts": slot_entry["post_counts"],
    }
    if not _state_equals(observed, expected):
        raise BaselineV2CutoverError(
            "cutover slot verification failed for "
            f"{slot_entry['filename']}: expected {expected}, got {observed}"
        )
    return observed


def run_cutover(database_url: str | None = None) -> dict[str, Any]:
    _assert_release_machine()
    load_env()

    if str(os.environ.get("APP_ENV") or "").strip().lower() != "production":
        raise BaselineV2CutoverError(
            "Baseline V2 cutover is production-only; APP_ENV=production is required"
        )

    lock = baseline_v2.verify_v2_lock()
    slot_entries = _lock_slot_entries(lock)
    runtime_target_state = _runtime_target_state(lock)
    url = baseline_v2._database_url(database_url)
    baseline_v2.validate_runtime_database_url(url)

    with baseline_v2.psycopg.connect(url, connect_timeout=5) as conn:
        pre_state = _read_schema_state(conn)
        plan = _build_cutover_plan(slot_entries, pre_state)
        existing_tables = _list_existing_app_tables(conn)
        pre_table_counts = _table_counts(conn, existing_tables)

        if plan["action"] == "noop":
            post_state = pre_state
            changed_existing_tables: dict[str, dict[str, int]] = {}
            new_tables: list[str] = []
            new_table_counts: dict[str, int] = {}
        else:
            with conn.transaction():
                post_state = _apply_cutover_slot(conn, plan["applied_slot"])
                post_tables = _list_existing_app_tables(conn)
                changed_existing_tables = _changed_existing_tables(
                    pre_table_counts,
                    _table_counts(conn, existing_tables),
                )
                if changed_existing_tables:
                    raise BaselineV2CutoverError(
                        "existing app table row counts changed during cutover: "
                        f"{json.dumps(changed_existing_tables, sort_keys=True)}"
                    )
                new_tables = [relation for relation in post_tables if relation not in existing_tables]
                new_table_counts = _table_counts(conn, new_tables)

    runtime_status = baseline_v2.verify_v2_runtime(database_url=url)
    final_runtime_state = {
        "schema_hash": str(runtime_status["schema_hash"]),
        "counts": _normalize_counts(dict(runtime_status["counts"])),
    }
    if not _runtime_state_equals(final_runtime_state, runtime_target_state):
        raise BaselineV2CutoverError(
            "post-cutover runtime verification did not converge to the lock target: "
            f"expected {runtime_target_state}, got {final_runtime_state}"
        )

    return {
        "action": plan["action"],
        "current_slot": int(plan["current_slot"]["slot"]),
        "artifact_slot": int(plan["artifact_slot"]["slot"]),
        "target_slot": int(plan["target_slot"]["slot"]),
        "target_last_slot": str(plan["target_slot"]["filename"]),
        "applied_slots": (
            [plan["applied_slot"]["filename"]] if plan["applied_slot"] is not None else []
        ),
        "pre_state": {
            "state_hash": str(pre_state["state_hash"]),
            "counts": _normalize_counts(dict(pre_state["counts"])),
        },
        "post_state": {
            "state_hash": str(post_state["state_hash"]),
            "counts": _normalize_counts(dict(post_state["counts"])),
        },
        "existing_tables": existing_tables,
        "existing_table_row_counts_unchanged": not changed_existing_tables,
        "changed_existing_tables": changed_existing_tables,
        "new_tables": new_tables,
        "new_table_counts": new_table_counts,
        "runtime_profile": str(runtime_status["profile"]),
        "runtime_state": str(runtime_status["state"]),
        "post_runtime": final_runtime_state,
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
    print(f"CURRENT_SLOT={result['current_slot']}")
    print(f"ARTIFACT_SLOT={result['artifact_slot']}")
    print(f"TARGET_SLOT={result['target_slot']}")
    print(f"TARGET_LAST_SLOT={result['target_last_slot']}")
    print(f"APPLIED_SLOTS={json.dumps(result['applied_slots'])}")
    print(f"PRE_STATE_HASH={result['pre_state']['state_hash']}")
    print(f"PRE_COUNTS={json.dumps(result['pre_state']['counts'], sort_keys=True)}")
    print(f"POST_STATE_HASH={result['post_state']['state_hash']}")
    print(f"POST_COUNTS={json.dumps(result['post_state']['counts'], sort_keys=True)}")
    print(
        "EXISTING_TABLE_ROW_COUNTS_UNCHANGED="
        + ("1" if result["existing_table_row_counts_unchanged"] else "0")
    )
    print(f"CHANGED_EXISTING_TABLES={json.dumps(result['changed_existing_tables'], sort_keys=True)}")
    print(f"NEW_TABLES={json.dumps(result['new_tables'])}")
    print(f"NEW_TABLE_COUNTS={json.dumps(result['new_table_counts'], sort_keys=True)}")
    print(f"POST_RUNTIME_SCHEMA_HASH={result['post_runtime']['schema_hash']}")
    print(f"POST_RUNTIME_COUNTS={json.dumps(result['post_runtime']['counts'], sort_keys=True)}")
    print(f"RUNTIME_PROFILE={result['runtime_profile']}")
    print(f"RUNTIME_STATE={result['runtime_state']}")
    print("FINAL_STATE=GO")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
