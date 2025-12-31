#!/usr/bin/env python3
"""Read-only remote DB verification for Supabase."""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

try:
    import psycopg
except Exception:  # pragma: no cover - dependency guard
    print("ERROR: psycopg library not available; run `poetry install`", file=sys.stderr)
    raise SystemExit(1)


ROOT_DIR = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = ROOT_DIR / "supabase" / "migrations"


def _die(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def _get_db_url() -> str:
    return os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL") or ""


def _fetch_scalar(conn: psycopg.Connection, sql: str):
    with conn.cursor() as cur:
        cur.execute(sql)
        row = cur.fetchone()
        return row[0] if row else None


def _fetch_column(conn: psycopg.Connection, sql: str) -> list[str]:
    with conn.cursor() as cur:
        cur.execute(sql)
        return [row[0] for row in cur.fetchall()]


def _fetch_rows(conn: psycopg.Connection, sql: str) -> list[tuple]:
    with conn.cursor() as cur:
        cur.execute(sql)
        return cur.fetchall()


def main() -> None:
    db_url = _get_db_url()
    if not db_url:
        _die("SUPABASE_DB_URL or DATABASE_URL is required for remote DB verify")

    issues: list[str] = []
    payload: dict[str, object] = {}

    try:
        with psycopg.connect(
            db_url,
            connect_timeout=5,
            options="-c default_transaction_read_only=on",
        ) as conn:
            app_tables = _fetch_column(
                conn,
                "select table_name from information_schema.tables "
                "where table_schema = 'app' and table_type = 'BASE TABLE' "
                "order by table_name;",
            )
            payload["app_tables_count"] = len(app_tables)

            rls_disabled = _fetch_column(
                conn,
                "select c.relname "
                "from pg_class c "
                "join pg_namespace n on n.oid = c.relnamespace "
                "where n.nspname = 'app' and c.relkind = 'r' "
                "and c.relrowsecurity = false "
                "order by c.relname;",
            )
            payload["rls_disabled_tables"] = rls_disabled
            if rls_disabled:
                issues.append("RLS disabled for some app tables")

            no_policy = _fetch_column(
                conn,
                "select t.table_name "
                "from information_schema.tables t "
                "left join pg_policies p "
                "on p.schemaname = 'app' and p.tablename = t.table_name "
                "where t.table_schema = 'app' and t.table_type = 'BASE TABLE' "
                "group by t.table_name "
                "having count(p.policyname) = 0 "
                "order by t.table_name;",
            )
            payload["tables_without_policies"] = no_policy
            if no_policy:
                issues.append("Some app tables are missing RLS policies")

            storage_exists = _fetch_scalar(
                conn,
                "select to_regclass('storage.buckets') is not null;",
            )
            payload["storage_exists"] = bool(storage_exists)
            storage_buckets: list[tuple] = []
            storage_policies: list[tuple] = []
            storage_rls = None
            storage_issue = ""
            if storage_exists:
                storage_buckets = _fetch_rows(
                    conn,
                    "select id, public from storage.buckets order by id;",
                )
                storage_policies = _fetch_rows(
                    conn,
                    "select policyname, cmd "
                    "from pg_policies "
                    "where schemaname = 'storage' and tablename = 'objects' "
                    "order by policyname, cmd;",
                )
                storage_rls = _fetch_scalar(
                    conn,
                    "select relrowsecurity "
                    "from pg_class c "
                    "join pg_namespace n on n.oid = c.relnamespace "
                    "where n.nspname = 'storage' and c.relname = 'objects';",
                )
                public_media_public = _fetch_scalar(
                    conn,
                    "select public from storage.buckets where id = 'public-media';",
                )
                course_media_public = _fetch_scalar(
                    conn,
                    "select public from storage.buckets where id = 'course-media';",
                )
                lesson_media_public = _fetch_scalar(
                    conn,
                    "select public from storage.buckets where id = 'lesson-media';",
                )
                if public_media_public is not True:
                    storage_issue = "public-media should be public"
                elif course_media_public is not False or lesson_media_public is not False:
                    storage_issue = "course-media and lesson-media should be private"
                elif not storage_policies:
                    storage_issue = "storage.objects policies missing"
                elif storage_rls is not True:
                    storage_issue = "storage.objects RLS disabled"
            else:
                storage_issue = "storage.buckets missing"

            payload["storage_buckets"] = [
                {"id": row[0], "public": row[1]} for row in storage_buckets
            ]
            payload["storage_policies"] = [
                {"policy": row[0], "cmd": row[1]} for row in storage_policies
            ]
            payload["storage_rls"] = storage_rls
            payload["storage_issue"] = storage_issue or "ok"
            if storage_issue:
                issues.append(storage_issue)

            migrations_table_exists = _fetch_scalar(
                conn,
                "select to_regclass('supabase_migrations.schema_migrations') is not null;",
            )
            payload["schema_migrations_present"] = bool(migrations_table_exists)

            db_migrations: list[str] = []
            if migrations_table_exists:
                db_migrations = _fetch_column(
                    conn,
                    "select name from supabase_migrations.schema_migrations order by name;",
                )
            else:
                issues.append("supabase_migrations.schema_migrations missing")

            repo_migrations = []
            if MIGRATIONS_DIR.exists():
                repo_migrations = sorted(
                    path.name for path in MIGRATIONS_DIR.glob("*.sql")
                )
            else:
                issues.append("supabase/migrations directory missing")

            missing_in_db = sorted(set(repo_migrations) - set(db_migrations))
            extra_in_db = sorted(set(db_migrations) - set(repo_migrations))
            payload["migrations_missing_in_db"] = missing_in_db
            payload["migrations_extra_in_db"] = extra_in_db
            if missing_in_db or extra_in_db:
                issues.append("migration drift detected")

    except Exception as exc:
        issues.append(f"DB verification failed: {exc}")

    status = "PASS" if not issues else "FAIL"
    payload["status"] = status
    payload["issues"] = issues

    log_path = Path("/tmp") / f"aveli_remote_db_verify_{int(time.time())}.json"
    try:
        log_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    except Exception as exc:
        print(f"ERROR: failed to write log file: {exc}", file=sys.stderr)

    print("==> Remote DB verify (read-only)")
    print(f"- App tables: {payload.get('app_tables_count', 0)}")
    print(
        f"- RLS disabled tables: {len(payload.get('rls_disabled_tables', [])) or 'none'}"
    )
    print(
        f"- Tables without policies: {len(payload.get('tables_without_policies', [])) or 'none'}"
    )
    print(f"- Storage bucket sanity: {payload.get('storage_issue')}")
    print(
        f"- Migration drift: "
        f"{'yes' if payload.get('migrations_missing_in_db') or payload.get('migrations_extra_in_db') else 'no'}"
    )
    print(f"- Log file: {log_path}")

    if status == "FAIL":
        print("Remote DB verify: FAIL")
        for issue in issues:
            print(f"  - {issue}")
        raise SystemExit(1)

    print("Remote DB verify: PASS")


if __name__ == "__main__":
    main()
