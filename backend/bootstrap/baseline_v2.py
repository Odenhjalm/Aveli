from __future__ import annotations

import hashlib
import json
import os
import sys
from pathlib import Path
from urllib.parse import urlsplit

from backend.bootstrap.load_env import load_env


ROOT_DIR = Path(__file__).resolve().parents[2]
BASELINE_V2_DIR = ROOT_DIR / "backend" / "supabase" / "baseline_v2_slots"

MANAGED_SCHEMAS = ("app", "auth", "storage")
BASELINE_MODE_ENV = "BASELINE_MODE"
DEFAULT_BASELINE_MODE = "V2"

EXPECTED_V2_SCHEMA_HASH = "89b98e02bf5babd93400e3bd4c6d8b1702cf533d5215923f687f88c9ba302110"
EXPECTED_V2_COUNTS = {
    "enums": 13,
    "tables": 30,
    "app_tables": 27,
    "views": 5,
    "fks": 37,
    "constraints": 144,
    "triggers": 11,
    "functions": 16,
}
EXPECTED_V2_SLOTS = (
    "V2_0001_foundation_enums.sql",
    "V2_0002_auth_subjects.sql",
    "V2_0003_media_assets.sql",
    "V2_0004_courses_and_public_content.sql",
    "V2_0005_lessons_content_and_access.sql",
    "V2_0006_media_placement_and_home_audio.sql",
    "V2_0007_profile_media.sql",
    "V2_0008_commerce_membership.sql",
    "V2_0009_runtime_support_inert.sql",
    "V2_0010_read_projections.sql",
    "V2_0011_auth_session_and_subject_authority.sql",
    "V2_0012_core_substrate_profiles_storage_referrals.sql",
    "V2_0013_workers.sql",
)

LEGACY_COLUMNS = ("role_v2", "is_admin", "course_step", "created_by", "is_published")
WORKER_FUNCTIONS = (
    "canonical_worker_advance_course_enrollment_drip",
    "canonical_worker_transition_media_asset",
)


class BaselineV2Error(RuntimeError):
    """Raised when the local DB is not an empty or valid Baseline V2 state."""


def _prepare_site_packages() -> None:
    version_dir = f"python{sys.version_info.major}.{sys.version_info.minor}"
    candidates = [
        ROOT_DIR / ".venv" / "Lib" / "site-packages",
        ROOT_DIR / ".venv" / "lib" / version_dir / "site-packages",
        ROOT_DIR / "backend" / ".venv" / "Lib" / "site-packages",
        ROOT_DIR / "backend" / ".venv" / "lib" / version_dir / "site-packages",
    ]
    for candidate in candidates:
        if candidate.is_dir() and str(candidate) not in sys.path:
            sys.path.insert(0, str(candidate))


_prepare_site_packages()

import psycopg  # noqa: E402


def baseline_mode() -> str:
    return str(os.environ.get(BASELINE_MODE_ENV) or DEFAULT_BASELINE_MODE).strip().upper()


def _database_url(database_url: str | None = None) -> str:
    if database_url:
        return database_url
    load_env()
    value = os.environ.get("DATABASE_URL")
    if not value:
        raise BaselineV2Error("DATABASE_URL is missing")
    return value


def _require_local_database(database_url: str) -> None:
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise BaselineV2Error(f"DATABASE_URL must be PostgreSQL, got {parsed.scheme!r}")
    if parsed.hostname != "127.0.0.1":
        raise BaselineV2Error(
            f"V2 baseline bootstrap is local-only; DATABASE_URL host is {parsed.hostname!r}"
        )
    if os.environ.get("FLY_APP_NAME") or os.environ.get("K_SERVICE"):
        raise BaselineV2Error("cloud runtime flag detected during local V2 baseline bootstrap")


def _fetchall(conn: psycopg.Connection, sql: str, params: tuple = ()) -> list[tuple]:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def _scalar(conn: psycopg.Connection, sql: str, params: tuple = ()) -> object:
    rows = _fetchall(conn, sql, params)
    return rows[0][0] if rows else None


def _slot_paths() -> tuple[Path, ...]:
    actual = tuple(path.name for path in sorted(BASELINE_V2_DIR.glob("V2_*.sql")))
    if actual != EXPECTED_V2_SLOTS:
        raise BaselineV2Error(
            f"Baseline V2 slot order mismatch: expected {EXPECTED_V2_SLOTS!r}, got {actual!r}"
        )
    return tuple(BASELINE_V2_DIR / name for name in EXPECTED_V2_SLOTS)


def _managed_schemas(conn: psycopg.Connection) -> list[str]:
    rows = _fetchall(
        conn,
        """
        select nspname
          from pg_namespace
         where nspname = any(%s)
         order by nspname
        """,
        (list(MANAGED_SCHEMAS),),
    )
    return [str(row[0]) for row in rows]


def db_is_empty(database_url: str | None = None) -> bool:
    url = _database_url(database_url)
    _require_local_database(url)
    with psycopg.connect(url, connect_timeout=5) as conn:
        return _db_is_empty(conn)


def _db_is_empty(conn: psycopg.Connection) -> bool:
    return _managed_schemas(conn) == []


def _replay_v2(conn: psycopg.Connection) -> None:
    if not _db_is_empty(conn):
        raise BaselineV2Error("refusing to replay V2 into a non-empty managed schema state")

    for slot in _slot_paths():
        try:
            conn.execute(slot.read_text(encoding="utf-8"))
            conn.commit()
        except Exception as exc:
            conn.rollback()
            raise BaselineV2Error(f"V2 replay failed in {slot.name}: {exc}") from exc


def _schema_fingerprint(conn: psycopg.Connection) -> str:
    payload = {
        "enums": _fetchall(
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
        "relations": _fetchall(
            conn,
            """
            select n.nspname, c.relname, c.relkind
              from pg_class c
              join pg_namespace n on n.oid = c.relnamespace
             where n.nspname in ('app', 'auth', 'storage')
               and c.relkind in ('r', 'v')
             order by 1, 2, 3
            """,
        ),
        "columns": _fetchall(
            conn,
            """
            select table_schema, table_name, column_name, ordinal_position,
                   is_nullable, data_type, udt_schema, udt_name, column_default
              from information_schema.columns
             where table_schema in ('app', 'auth', 'storage')
             order by table_schema, table_name, ordinal_position
            """,
        ),
        "constraints": _fetchall(
            conn,
            """
            select n.nspname, cls.relname, con.conname, con.contype,
                   pg_get_constraintdef(con.oid, true), con.convalidated
              from pg_constraint con
              join pg_namespace n on n.oid = con.connamespace
              left join pg_class cls on cls.oid = con.conrelid
             where n.nspname in ('app', 'auth', 'storage')
             order by 1, 2, 3
            """,
        ),
        "triggers": _fetchall(
            conn,
            """
            select n.nspname, cls.relname, tg.tgname, tg.tgfoid::regprocedure::text
              from pg_trigger tg
              join pg_class cls on cls.oid = tg.tgrelid
              join pg_namespace n on n.oid = cls.relnamespace
             where n.nspname in ('app', 'auth', 'storage')
               and not tg.tgisinternal
             order by 1, 2, 3
            """,
        ),
        "functions": _fetchall(
            conn,
            """
            select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
                   pg_get_function_result(p.oid)
              from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
             where n.nspname in ('app', 'auth', 'storage')
             order by 1, 2, 3
            """,
        ),
        "views": _fetchall(
            conn,
            """
            select schemaname, viewname, definition
              from pg_views
             where schemaname in ('app', 'auth', 'storage')
             order by 1, 2
            """,
        ),
    }
    return hashlib.sha256(
        json.dumps(payload, sort_keys=True, default=str).encode("utf-8")
    ).hexdigest()


def _schema_counts(conn: psycopg.Connection) -> dict[str, int]:
    return {
        "enums": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_type t
                  join pg_namespace n on n.oid = t.typnamespace
                 where n.nspname = 'app'
                   and t.typtype = 'e'
                """,
            )
            or 0
        ),
        "tables": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname in ('app', 'auth', 'storage')
                   and c.relkind = 'r'
                """,
            )
            or 0
        ),
        "app_tables": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'app'
                   and c.relkind = 'r'
                """,
            )
            or 0
        ),
        "views": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_class c
                  join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname in ('app', 'auth', 'storage')
                   and c.relkind = 'v'
                """,
            )
            or 0
        ),
        "fks": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_constraint con
                  join pg_namespace n on n.oid = con.connamespace
                 where n.nspname in ('app', 'auth', 'storage')
                   and con.contype = 'f'
                """,
            )
            or 0
        ),
        "constraints": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_constraint con
                  join pg_namespace n on n.oid = con.connamespace
                 where n.nspname in ('app', 'auth', 'storage')
                """,
            )
            or 0
        ),
        "triggers": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_trigger tg
                  join pg_class cls on cls.oid = tg.tgrelid
                  join pg_namespace n on n.oid = cls.relnamespace
                 where n.nspname = 'app'
                   and not tg.tgisinternal
                """,
            )
            or 0
        ),
        "functions": int(
            _scalar(
                conn,
                """
                select count(*)
                  from pg_proc p
                  join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'app'
                """,
            )
            or 0
        ),
    }


def _verify_v2_schema(conn: psycopg.Connection) -> dict[str, object]:
    failures: list[str] = []
    counts = _schema_counts(conn)
    if counts != EXPECTED_V2_COUNTS:
        failures.append(f"count mismatch: expected {EXPECTED_V2_COUNTS}, got {counts}")

    invalid_constraints = _fetchall(
        conn,
        """
        select n.nspname, cls.relname, con.conname
          from pg_constraint con
          join pg_namespace n on n.oid = con.connamespace
          left join pg_class cls on cls.oid = con.conrelid
         where n.nspname in ('app', 'auth', 'storage')
           and con.convalidated = false
         order by 1, 2, 3
        """,
    )
    if invalid_constraints:
        failures.append(f"invalid constraints present: {invalid_constraints!r}")

    legacy_columns = _fetchall(
        conn,
        """
        select table_schema, table_name, column_name
          from information_schema.columns
         where table_schema in ('app', 'auth', 'storage')
           and column_name = any(%s)
         order by 1, 2, 3
        """,
        (list(LEGACY_COLUMNS),),
    )
    if legacy_columns:
        failures.append(f"legacy columns present: {legacy_columns!r}")

    media_owner_id = _scalar(
        conn,
        """
        select count(*)
          from information_schema.columns
         where table_schema = 'app'
           and table_name = 'media_assets'
           and column_name = 'owner_id'
        """,
    )
    if media_owner_id:
        failures.append("media_assets.owner_id is present")

    runtime_media_relkind = _scalar(
        conn,
        """
        select c.relkind
          from pg_class c
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'app'
           and c.relname = 'runtime_media'
        """,
    )
    if runtime_media_relkind != "v":
        failures.append(f"runtime_media relkind is {runtime_media_relkind!r}, expected 'v'")

    payment_events_processed_at = _scalar(
        conn,
        """
        select count(*)
          from information_schema.columns
         where table_schema = 'app'
           and table_name = 'payment_events'
           and column_name = 'processed_at'
        """,
    )
    if payment_events_processed_at:
        failures.append("payment_events.processed_at is present")

    media_lifecycle_trigger_count = _scalar(
        conn,
        """
        select count(*)
          from pg_trigger tg
          join pg_class cls on cls.oid = tg.tgrelid
          join pg_namespace n on n.oid = cls.relnamespace
         where n.nspname = 'app'
           and cls.relname = 'media_assets'
           and tg.tgname = 'media_assets_lifecycle_contract'
           and not tg.tgisinternal
        """,
    )
    if media_lifecycle_trigger_count != 1:
        failures.append("media_assets_lifecycle_contract trigger is missing")

    worker_functions = [
        str(row[0])
        for row in _fetchall(
            conn,
            """
            select p.proname
              from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'app'
               and p.proname = any(%s)
             order by 1
            """,
            (list(WORKER_FUNCTIONS),),
        )
    ]
    if tuple(worker_functions) != WORKER_FUNCTIONS:
        failures.append(f"worker functions mismatch: {worker_functions!r}")

    schema_hash = _schema_fingerprint(conn)
    if schema_hash != EXPECTED_V2_SCHEMA_HASH:
        failures.append(
            f"schema hash mismatch: expected {EXPECTED_V2_SCHEMA_HASH}, got {schema_hash}"
        )

    if failures:
        raise BaselineV2Error("Baseline V2 mismatch: " + "; ".join(failures))

    return {
        "schema_hash": schema_hash,
        "counts": counts,
        "runtime_media_relkind": runtime_media_relkind,
        "payment_events_processed_at": bool(payment_events_processed_at),
    }


def ensure_v2_baseline(database_url: str | None = None) -> dict[str, object]:
    mode = baseline_mode()
    if mode != DEFAULT_BASELINE_MODE:
        raise BaselineV2Error(
            f"unsupported {BASELINE_MODE_ENV}={mode!r}; only {DEFAULT_BASELINE_MODE} is allowed"
        )

    url = _database_url(database_url)
    _require_local_database(url)
    with psycopg.connect(url, connect_timeout=5) as conn:
        if _db_is_empty(conn):
            _replay_v2(conn)
            state = "replayed"
        else:
            state = "verified"

        verification = _verify_v2_schema(conn)

    return {
        "mode": mode,
        "state": state,
        **verification,
    }


def main() -> int:
    try:
        status = ensure_v2_baseline()
    except Exception as exc:
        print(f"BASELINE_V2_STATUS=FAIL")
        print(f"FAILURE={exc}")
        return 1

    print("BASELINE_V2_STATUS=PASS")
    print(f"BASELINE_MODE={status['mode']}")
    print(f"BASELINE_STATE={status['state']}")
    print(f"SCHEMA_HASH={status['schema_hash']}")
    print(f"COUNTS={json.dumps(status['counts'], sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
