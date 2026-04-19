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
BASELINE_V2_LOCK_FILE = ROOT_DIR / "backend" / "supabase" / "baseline_v2_slots.lock.json"

REPLAY_OWNED_SCHEMAS = ("app",)
EXTERNAL_SUBSTRATE_SCHEMAS = ("auth", "storage")
BASELINE_MODE_ENV = "BASELINE_MODE"
DEFAULT_BASELINE_MODE = "V2"
BASELINE_PROFILE_ENV = "BASELINE_PROFILE"
LOCAL_DEV_PROFILE = "local_dev"
HOSTED_SUPABASE_PROFILE = "hosted_supabase"
SUPPORTED_BASELINE_PROFILES = (LOCAL_DEV_PROFILE, HOSTED_SUPABASE_PROFILE)
ALLOW_HOSTED_BASELINE_REPLAY_ENV = "ALLOW_HOSTED_BASELINE_REPLAY"
CLOUD_RUNTIME_ENV_KEYS = ("FLY_APP_NAME", "K_SERVICE", "AWS_EXECUTION_ENV", "DYNO")
PRODUCTION_ENV_VALUES = {"prod", "production", "live"}
LOCAL_DATABASE_HOSTS = {"127.0.0.1", "localhost", "::1", "db", "host.docker.internal"}


class BaselineV2Error(RuntimeError):
    """Raised when the local DB is not an empty or valid Baseline V2 state."""


def _lf_normalized_sql_bytes(path: Path) -> bytes:
    source = path.read_text(encoding="utf-8")
    normalized = source.replace("\r\n", "\n").replace("\r", "\n")
    return normalized.encode("utf-8")


def _sha256_lf(path: Path) -> str:
    return hashlib.sha256(_lf_normalized_sql_bytes(path)).hexdigest()


def _load_v2_lock() -> dict[str, object]:
    try:
        payload = json.loads(BASELINE_V2_LOCK_FILE.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise BaselineV2Error(f"missing V2 lock file: {BASELINE_V2_LOCK_FILE}") from exc
    except json.JSONDecodeError as exc:
        raise BaselineV2Error(f"invalid V2 lock JSON: {exc}") from exc

    if not isinstance(payload, dict):
        raise BaselineV2Error("V2 lock must contain a JSON object")
    if payload.get("manifest_version") != 3:
        raise BaselineV2Error("V2 lock manifest_version must be 3")
    if payload.get("baseline_dir") != "backend/supabase/baseline_v2_slots":
        raise BaselineV2Error("V2 lock baseline_dir must be backend/supabase/baseline_v2_slots")
    if payload.get("hash_strategy") != "sha256_lf_normalized_utf8":
        raise BaselineV2Error("V2 lock hash_strategy must be sha256_lf_normalized_utf8")

    return payload


def _lock_slots(payload: dict[str, object]) -> tuple[dict[str, object], ...]:
    slots = payload.get("slots")
    if not isinstance(slots, list) or not slots:
        raise BaselineV2Error("V2 lock must contain a non-empty slots list")

    locked_slots: list[dict[str, object]] = []
    for entry in slots:
        if not isinstance(entry, dict):
            raise BaselineV2Error("each V2 lock slot entry must be an object")
        locked_slots.append(entry)

    expected_sequence = list(range(1, len(locked_slots) + 1))
    actual_sequence = [int(entry.get("slot", -1)) for entry in locked_slots]
    if actual_sequence != expected_sequence:
        raise BaselineV2Error(
            f"V2 lock slot sequence mismatch: expected {expected_sequence}, got {actual_sequence}"
        )

    return tuple(locked_slots)


def _locked_file_entries(payload: dict[str, object], key: str) -> tuple[dict[str, object], ...]:
    entries = payload.get(key)
    if not isinstance(entries, list):
        raise BaselineV2Error(f"V2 lock must contain {key}")

    locked_entries: list[dict[str, object]] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise BaselineV2Error(f"each {key} entry must be an object")
        locked_entries.append(entry)

    return tuple(locked_entries)


def _verify_locked_file_entry(
    entry: dict[str, object],
    *,
    label: str,
    expected_parent: Path | None = None,
) -> Path:
    filename = entry.get("filename")
    relative_path = entry.get("path")
    expected_hash = entry.get("sha256")

    if not isinstance(filename, str) or not filename:
        raise BaselineV2Error(f"{label} is missing filename")
    if not isinstance(relative_path, str) or not relative_path:
        raise BaselineV2Error(f"{label} is missing path")
    if not isinstance(expected_hash, str) or len(expected_hash) != 64:
        raise BaselineV2Error(f"{label} is missing sha256")

    path = ROOT_DIR / relative_path
    if expected_parent is not None and path.parent != expected_parent:
        raise BaselineV2Error(f"{label} points outside expected directory: {relative_path}")
    if path.name != filename:
        raise BaselineV2Error(f"{label} filename mismatch: {filename} != {path.name}")
    if not path.is_file():
        raise BaselineV2Error(f"{label} missing on disk: {relative_path}")

    actual_hash = _sha256_lf(path)
    if actual_hash != expected_hash:
        raise BaselineV2Error(
            f"{label} hash mismatch for {filename}: expected {expected_hash}, got {actual_hash}"
        )

    return path


def _verify_lock_model(payload: dict[str, object]) -> None:
    ownership = payload.get("replay_ownership")
    if not isinstance(ownership, dict):
        raise BaselineV2Error("V2 lock must define replay_ownership")
    if tuple(ownership.get("replay_owned_schemas", ())) != REPLAY_OWNED_SCHEMAS:
        raise BaselineV2Error("V2 lock replay_owned_schemas must be ['app']")
    if tuple(ownership.get("external_substrate_schemas", ())) != EXTERNAL_SUBSTRATE_SCHEMAS:
        raise BaselineV2Error("V2 lock external_substrate_schemas must be ['auth', 'storage']")

    profiles = payload.get("execution_profiles")
    if not isinstance(profiles, dict):
        raise BaselineV2Error("V2 lock must define execution_profiles")
    for profile in SUPPORTED_BASELINE_PROFILES:
        if profile not in profiles:
            raise BaselineV2Error(f"V2 lock is missing execution profile {profile}")

    substrate_interfaces = payload.get("substrate_interfaces")
    if not isinstance(substrate_interfaces, dict):
        raise BaselineV2Error("V2 lock must define substrate_interfaces")
    for interface_name in ("auth.users", "storage.buckets", "storage.objects"):
        interface = substrate_interfaces.get(interface_name)
        if not isinstance(interface, dict):
            raise BaselineV2Error(f"V2 lock is missing substrate interface {interface_name}")
        columns = interface.get("required_columns")
        if not isinstance(columns, list) or not columns:
            raise BaselineV2Error(f"V2 lock substrate interface {interface_name} needs columns")


def _local_substrate_paths_from_lock(payload: dict[str, object]) -> tuple[Path, ...]:
    entries = _locked_file_entries(payload, "local_dev_substrate_files")
    paths: list[Path] = []
    for index, entry in enumerate(entries, start=1):
        path = _verify_locked_file_entry(entry, label=f"local substrate file {index}")
        paths.append(path)
    return tuple(paths)


def verify_v2_lock() -> dict[str, object]:
    payload = _load_v2_lock()
    locked_slots = _lock_slots(payload)
    _verify_lock_model(payload)

    for entry in locked_slots:
        slot_number = entry["slot"]
        _verify_locked_file_entry(
            entry,
            label=f"V2 lock slot {slot_number}",
            expected_parent=BASELINE_V2_DIR,
        )

    _local_substrate_paths_from_lock(payload)

    verification = payload.get("schema_verification")
    if not isinstance(verification, dict):
        raise BaselineV2Error("V2 lock must contain schema_verification")
    if verification.get("schema_scope") != "app_owned_schema_only":
        raise BaselineV2Error("V2 lock schema_verification must use app_owned_schema_only")
    if (
        verification.get("schema_hash_algorithm")
        != "backend.bootstrap.baseline_v2.app_schema_fingerprint_v2"
    ):
        raise BaselineV2Error("V2 lock schema hash algorithm must be app_schema_fingerprint_v2")
    if not isinstance(verification.get("expected_schema_hash"), str):
        raise BaselineV2Error("V2 lock schema_verification must define expected_schema_hash")
    if not isinstance(verification.get("expected_counts"), dict):
        raise BaselineV2Error("V2 lock schema_verification must define expected_counts")

    return payload


def _schema_verification() -> dict[str, object]:
    payload = verify_v2_lock()
    verification = payload["schema_verification"]
    if not isinstance(verification, dict):
        raise BaselineV2Error("V2 lock schema_verification is invalid")
    return verification


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
    return (
        str(os.environ.get(BASELINE_MODE_ENV) or DEFAULT_BASELINE_MODE).strip().upper()
    )


def baseline_profile() -> str:
    raw_profile = os.environ.get(BASELINE_PROFILE_ENV)
    if raw_profile:
        profile = raw_profile.strip().lower()
    else:
        profile = HOSTED_SUPABASE_PROFILE if _cloud_runtime_active() else LOCAL_DEV_PROFILE

    if profile not in SUPPORTED_BASELINE_PROFILES:
        raise BaselineV2Error(
            f"unsupported {BASELINE_PROFILE_ENV}={profile!r}; "
            f"allowed profiles are {', '.join(SUPPORTED_BASELINE_PROFILES)}"
        )
    return profile


def _database_url(database_url: str | None = None) -> str:
    if database_url:
        return database_url
    load_env()
    value = os.environ.get("DATABASE_URL")
    if not value:
        raise BaselineV2Error("DATABASE_URL is missing")
    return value


def _parse_postgresql_database_url(database_url: str):
    parsed = urlsplit(database_url)
    if parsed.scheme not in {"postgresql", "postgres"}:
        raise BaselineV2Error(f"DATABASE_URL must be PostgreSQL, got {parsed.scheme!r}")
    if not parsed.hostname:
        raise BaselineV2Error("DATABASE_URL must include a hostname")
    return parsed


def _cloud_runtime_active() -> bool:
    app_env = str(os.environ.get("APP_ENV") or "").strip().lower()
    return app_env in PRODUCTION_ENV_VALUES or any(os.environ.get(key) for key in CLOUD_RUNTIME_ENV_KEYS)


def validate_runtime_database_url(database_url: str) -> None:
    parsed = _parse_postgresql_database_url(database_url)
    if _cloud_runtime_active() and parsed.hostname in LOCAL_DATABASE_HOSTS:
        raise BaselineV2Error(
            "runtime DATABASE_URL points to a local host while production/cloud runtime is active"
        )


def _require_local_database(database_url: str) -> None:
    parsed = _parse_postgresql_database_url(database_url)
    if parsed.hostname != "127.0.0.1":
        raise BaselineV2Error(
            f"V2 baseline bootstrap is local-only; DATABASE_URL host is {parsed.hostname!r}"
        )
    app_env = str(os.environ.get("APP_ENV") or "").strip().lower()
    mcp_mode = str(os.environ.get("MCP_MODE") or "").strip().lower()
    if app_env == "local" and mcp_mode == "local":
        return
    active_cloud_flags = [key for key in CLOUD_RUNTIME_ENV_KEYS if os.environ.get(key)]
    if active_cloud_flags:
        raise BaselineV2Error(
            "cloud runtime flag detected during local V2 baseline bootstrap: "
            + ", ".join(active_cloud_flags)
        )


def _fetchall(conn: psycopg.Connection, sql: str, params: tuple = ()) -> list[tuple]:
    with conn.cursor() as cur:
        cur.execute(sql, params)
        return list(cur.fetchall())


def _scalar(conn: psycopg.Connection, sql: str, params: tuple = ()) -> object:
    rows = _fetchall(conn, sql, params)
    return rows[0][0] if rows else None


def _slot_paths() -> tuple[Path, ...]:
    payload = verify_v2_lock()
    return tuple(ROOT_DIR / str(entry["path"]) for entry in _lock_slots(payload))


def _local_substrate_paths() -> tuple[Path, ...]:
    payload = verify_v2_lock()
    return _local_substrate_paths_from_lock(payload)


def _managed_schemas(conn: psycopg.Connection) -> list[str]:
    rows = _fetchall(
        conn,
        """
        select nspname
          from pg_namespace
         where nspname = any(%s)
         order by nspname
        """,
        (list(REPLAY_OWNED_SCHEMAS),),
    )
    return [str(row[0]) for row in rows]


def db_is_empty(database_url: str | None = None) -> bool:
    url = _database_url(database_url)
    _require_local_database(url)
    with psycopg.connect(url, connect_timeout=5) as conn:
        return _db_is_empty(conn)


def _db_is_empty(conn: psycopg.Connection) -> bool:
    return _managed_schemas(conn) == []


def _ensure_local_substrate(conn: psycopg.Connection) -> None:
    for substrate_file in _local_substrate_paths():
        conn.execute(substrate_file.read_text(encoding="utf-8"))


def _hosted_replay_allowed() -> bool:
    return str(os.environ.get(ALLOW_HOSTED_BASELINE_REPLAY_ENV) or "").strip() == "1"


def _assert_replay_profile_allowed(profile: str) -> None:
    if profile == LOCAL_DEV_PROFILE:
        return
    if profile == HOSTED_SUPABASE_PROFILE and _hosted_replay_allowed():
        return
    raise BaselineV2Error(
        f"hosted Supabase replay requires {ALLOW_HOSTED_BASELINE_REPLAY_ENV}=1 "
        f"and {BASELINE_PROFILE_ENV}={HOSTED_SUPABASE_PROFILE}"
    )


def _replay_v2(conn: psycopg.Connection, *, profile: str) -> None:
    _assert_replay_profile_allowed(profile)

    if not _db_is_empty(conn):
        raise BaselineV2Error(
            "refusing to replay V2 into a non-empty app-owned schema state"
        )

    try:
        with conn.transaction():
            if profile == LOCAL_DEV_PROFILE:
                _ensure_local_substrate(conn)
            else:
                _verify_substrate_interface(conn)
            for slot in _slot_paths():
                conn.execute(slot.read_text(encoding="utf-8"))
    except Exception as exc:
        raise BaselineV2Error(f"V2 replay failed atomically: {exc}") from exc


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
             where n.nspname = 'app'
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
             where table_schema = 'app'
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
             where n.nspname = 'app'
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
             where n.nspname = 'app'
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
             where n.nspname = 'app'
             order by 1, 2, 3
            """,
        ),
        "views": _fetchall(
            conn,
            """
            select schemaname, viewname, definition
              from pg_views
             where schemaname = 'app'
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
                 where n.nspname = 'app'
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
                 where n.nspname = 'app'
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
                 where n.nspname = 'app'
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


def _substrate_interfaces() -> dict[str, object]:
    payload = verify_v2_lock()
    interfaces = payload.get("substrate_interfaces")
    if not isinstance(interfaces, dict):
        raise BaselineV2Error("V2 lock substrate_interfaces is invalid")
    return interfaces


def _verify_substrate_interface(conn: psycopg.Connection) -> dict[str, object]:
    failures: list[str] = []
    observed: dict[str, object] = {}

    for relation_name, interface in _substrate_interfaces().items():
        if not isinstance(interface, dict):
            raise BaselineV2Error(f"substrate interface {relation_name} is invalid")
        if "." not in relation_name:
            raise BaselineV2Error(f"substrate interface {relation_name} is not schema-qualified")

        schema_name, table_name = relation_name.split(".", 1)
        required_columns = tuple(
            str(column) for column in interface.get("required_columns", ())
        )
        if not required_columns:
            raise BaselineV2Error(f"substrate interface {relation_name} has no required columns")

        table_exists = _scalar(conn, "select to_regclass(%s)::text", (relation_name,))
        if not table_exists:
            failures.append(f"{relation_name} is missing")
            observed[relation_name] = {"present": False, "missing_columns": list(required_columns)}
            continue

        column_rows = _fetchall(
            conn,
            """
            select column_name
              from information_schema.columns
             where table_schema = %s
               and table_name = %s
               and column_name = any(%s)
             order by column_name
            """,
            (schema_name, table_name, list(required_columns)),
        )
        present_columns = {str(row[0]) for row in column_rows}
        missing_columns = [column for column in required_columns if column not in present_columns]
        if missing_columns:
            failures.append(f"{relation_name} missing columns: {missing_columns!r}")

        observed[relation_name] = {
            "present": True,
            "required_columns": list(required_columns),
            "missing_columns": missing_columns,
        }

    if failures:
        raise BaselineV2Error("Supabase substrate interface mismatch: " + "; ".join(failures))

    return observed


def _verify_v2_schema(conn: psycopg.Connection) -> dict[str, object]:
    failures: list[str] = []
    verification = _schema_verification()
    expected_counts = {
        str(key): int(value)
        for key, value in dict(verification["expected_counts"]).items()
    }
    forbidden_legacy_columns = tuple(
        str(column) for column in verification.get("forbidden_legacy_columns", ())
    )
    expected_relations = dict(verification.get("expected_relations", {}))
    runtime_media_expectation = dict(expected_relations.get("app.runtime_media", {}))
    expected_runtime_media_relkind = str(runtime_media_expectation.get("relkind", "v"))
    required_triggers = tuple(
        dict(item) for item in verification.get("required_triggers", ())
    )
    forbidden_columns = tuple(
        dict(item) for item in verification.get("forbidden_columns", ())
    )
    expected_worker_functions = tuple(
        str(function)
        for function in verification.get("required_worker_functions", ())
    )
    expected_schema_hash = str(verification["expected_schema_hash"])
    substrate_interface = _verify_substrate_interface(conn)

    counts = _schema_counts(conn)
    if counts != expected_counts:
        failures.append(f"count mismatch: expected {expected_counts}, got {counts}")

    invalid_constraints = _fetchall(
        conn,
        """
        select n.nspname, cls.relname, con.conname
         from pg_constraint con
          join pg_namespace n on n.oid = con.connamespace
          left join pg_class cls on cls.oid = con.conrelid
         where n.nspname = 'app'
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
          where table_schema = 'app'
            and column_name = any(%s)
          order by 1, 2, 3
        """,
        (list(forbidden_legacy_columns),),
    )
    if legacy_columns:
        failures.append(f"legacy columns present: {legacy_columns!r}")

    for forbidden_column in forbidden_columns:
        column_schema = str(forbidden_column.get("schema", ""))
        column_table = str(forbidden_column.get("table", ""))
        column_name = str(forbidden_column.get("column", ""))
        column_count = _scalar(
            conn,
            """
            select count(*)
              from information_schema.columns
             where table_schema = %s
               and table_name = %s
               and column_name = %s
            """,
            (column_schema, column_table, column_name),
        )
        if column_count:
            failures.append(f"{column_schema}.{column_table}.{column_name} is present")

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
    if runtime_media_relkind != expected_runtime_media_relkind:
        failures.append(
            f"runtime_media relkind is {runtime_media_relkind!r}, "
            f"expected {expected_runtime_media_relkind!r}"
        )

    for trigger in required_triggers:
        trigger_schema = str(trigger.get("schema", ""))
        trigger_table = str(trigger.get("table", ""))
        trigger_name = str(trigger.get("trigger", ""))
        trigger_count = _scalar(
            conn,
            """
            select count(*)
              from pg_trigger tg
              join pg_class cls on cls.oid = tg.tgrelid
              join pg_namespace n on n.oid = cls.relnamespace
             where n.nspname = %s
               and cls.relname = %s
               and tg.tgname = %s
               and not tg.tgisinternal
            """,
            (trigger_schema, trigger_table, trigger_name),
        )
        if trigger_count != 1:
            failures.append(f"{trigger_schema}.{trigger_table}.{trigger_name} trigger is missing")

    observed_worker_functions = [
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
            (list(expected_worker_functions),),
        )
    ]
    if tuple(observed_worker_functions) != expected_worker_functions:
        failures.append(f"worker functions mismatch: {observed_worker_functions!r}")

    schema_hash = _schema_fingerprint(conn)
    if schema_hash != expected_schema_hash:
        failures.append(
            f"schema hash mismatch: expected {expected_schema_hash}, got {schema_hash}"
        )

    if failures:
        raise BaselineV2Error("Baseline V2 mismatch: " + "; ".join(failures))

    return {
        "schema_hash": schema_hash,
        "counts": counts,
        "substrate_interface": substrate_interface,
        "runtime_media_relkind": runtime_media_relkind,
        "forbidden_columns": [item for item in forbidden_columns],
    }


def ensure_v2_baseline(database_url: str | None = None) -> dict[str, object]:
    mode = baseline_mode()
    if mode != DEFAULT_BASELINE_MODE:
        raise BaselineV2Error(
            f"unsupported {BASELINE_MODE_ENV}={mode!r}; only {DEFAULT_BASELINE_MODE} is allowed"
        )
    profile = baseline_profile()

    url = _database_url(database_url)
    if profile == LOCAL_DEV_PROFILE:
        _require_local_database(url)
    else:
        validate_runtime_database_url(url)
        _assert_replay_profile_allowed(profile)

    with psycopg.connect(url, connect_timeout=5) as conn:
        if _db_is_empty(conn):
            _replay_v2(conn, profile=profile)
            state = "replayed"
        else:
            state = "verified"

        verification = _verify_v2_schema(conn)

    return {
        "mode": mode,
        "profile": profile,
        "state": state,
        **verification,
    }


def verify_v2_runtime(database_url: str | None = None) -> dict[str, object]:
    mode = baseline_mode()
    if mode != DEFAULT_BASELINE_MODE:
        raise BaselineV2Error(
            f"unsupported {BASELINE_MODE_ENV}={mode!r}; only {DEFAULT_BASELINE_MODE} is allowed"
        )
    profile = baseline_profile()

    verify_v2_lock()
    url = _database_url(database_url)
    validate_runtime_database_url(url)
    with psycopg.connect(
        url,
        connect_timeout=5,
        options="-c default_transaction_read_only=on",
    ) as conn:
        if _db_is_empty(conn):
            raise BaselineV2Error(
                "Baseline V2 runtime schema is empty; runtime startup will not replay"
            )
        verification = _verify_v2_schema(conn)

    return {
        "mode": mode,
        "profile": profile,
        "state": "verified",
        **verification,
    }


def main() -> int:
    try:
        status = ensure_v2_baseline()
    except Exception as exc:
        print("BASELINE_V2_STATUS=FAIL")
        print(f"FAILURE={exc}")
        return 1

    print("BASELINE_V2_STATUS=PASS")
    print(f"BASELINE_MODE={status['mode']}")
    print(f"BASELINE_PROFILE={status['profile']}")
    print(f"BASELINE_STATE={status['state']}")
    print(f"SCHEMA_HASH={status['schema_hash']}")
    print(f"COUNTS={json.dumps(status['counts'], sort_keys=True)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
