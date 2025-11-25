#!/usr/bin/env python3
"""Detect and resolve slug conflicts across database tables.

The script looks up every table that contains a column named `slug`, groups
rows by slug value, and for duplicates generates a unique replacement by
appending a short identifier. By default it only prints the changes; pass
`--apply` to persist updates.

Usage examples
--------------

* Dry-run using DATABASE_URL from the environment:

    python scripts/fix_slug_conflict.py

* Apply fixes against an explicit database URL:

    python scripts/fix_slug_conflict.py --apply \
        --database-url postgresql://user:pass@localhost:5432/wisdom

Notes
-----

* The script assumes each table has a primary key column named `id`.
* Only tables in schemas other than `pg_catalog` / `information_schema` are
  inspected. Override with `--include-schema` if you need additional schemas.
* Slugs are updated by appending `-{random}` (8 hex chars) until a unique value
  is found for that table; no cross-table uniqueness is attempted.
"""

from __future__ import annotations

import argparse
import os
import sys
import textwrap
import uuid
from dataclasses import dataclass
from typing import Iterable, List

import psycopg


@dataclass
class ConflictEntry:
    table: str
    schema: str
    slug: str
    row_ids: List[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect and optionally fix slug conflicts across tables",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            By default the script performs a dry-run and prints the UPDATE
            statements it would execute. Use `--apply` to persist changes.

            The connection string is read from the `DATABASE_URL` environment
            variable unless `--database-url` is supplied.
            """
        ),
    )
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL"),
        help="Postgres connection string (fallback to $DATABASE_URL)",
    )
    parser.add_argument(
        "--include-schema",
        action="append",
        help="Schemas to include (defaults to all except pg_catalog/information_schema)",
    )
    parser.add_argument(
        "--exclude-schema",
        action="append",
        default=["pg_catalog", "information_schema"],
        help="Schemas to exclude (default: pg_catalog, information_schema)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist updates instead of dry-run",
    )
    return parser.parse_args()


def fetch_slug_conflicts(
    conn: psycopg.Connection,
    include_schema: Iterable[str] | None,
    exclude_schema: Iterable[str],
) -> List[ConflictEntry]:
    clauses = ["c.column_name = 'slug'"]
    params: List[Iterable[str]] = []
    if include_schema:
        clauses.append("c.table_schema = ANY(%s)")
        params.append(list(include_schema))
    if exclude_schema:
        clauses.append("c.table_schema <> ALL(%s)")
        params.append(list(exclude_schema))

    where_sql = " WHERE " + " AND ".join(clauses)

    conflicts: List[ConflictEntry] = []
    with conn.cursor() as cur:
        table_query = (
            "SELECT DISTINCT c.table_schema, c.table_name "
            "FROM information_schema.columns c"
            f"{where_sql}"
            " ORDER BY c.table_schema, c.table_name"
        )
        table_params = tuple(params)
        if table_params:
            cur.execute(table_query, table_params)
        else:
            cur.execute(table_query)
        tables = cur.fetchall()
        for schema, table in tables:
            query = textwrap.dedent(
                f"""
                SELECT %(schema)s AS table_schema,
                       %(table)s AS table_name,
                       slug,
                       array_agg(id ORDER BY id) AS row_ids
                FROM {schema}.{table}
                GROUP BY slug
                HAVING COUNT(*) > 1
                ORDER BY slug
                """
            )
            cur.execute(query, {"schema": schema, "table": table})
            for row in cur.fetchall():
                table_schema, table_name, slug, row_ids = row
                conflicts.append(
                    ConflictEntry(
                        table=table_name,
                        schema=table_schema,
                        slug=slug,
                        row_ids=[str(rid) for rid in row_ids],
                    )
                )
    return conflicts


def generate_unique_slug(conn: psycopg.Connection, schema: str, table: str, base: str) -> str:
    """Return a slug unique within schema.table by appending a suffix."""

    suffix = uuid.uuid4().hex[:8]
    candidate = f"{base}-{suffix}"
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT 1 FROM {schema}.{table} WHERE slug = %s LIMIT 1",
            (candidate,),
        )
        if cur.fetchone():
            # Recursively try again (extremely unlikely to loop).
            return generate_unique_slug(conn, schema, table, base)
    return candidate


def apply_fixes(conn: psycopg.Connection, conflicts: List[ConflictEntry], dry_run: bool) -> None:
    if not conflicts:
        print("No slug conflicts detected. ✅")
        return

    print(f"Detected {len(conflicts)} slug conflict groups. {'Dry-run' if dry_run else 'Applying fixes'}...\n")

    for entry in conflicts:
        print(f"{entry.schema}.{entry.table}: slug '{entry.slug}' has {len(entry.row_ids)} rows")
        # Keep the first ID unchanged
        for idx, row_id in enumerate(entry.row_ids):
            if idx == 0:
                print(f"  - keeping row id={row_id}")
                continue
            new_slug = generate_unique_slug(conn, entry.schema, entry.table, entry.slug)
            print(f"  - updating id={row_id} -> slug '{new_slug}'")
            if not dry_run:
                with conn.cursor() as cur:
                    cur.execute(
                        f"UPDATE {entry.schema}.{entry.table} SET slug = %s WHERE id = %s",
                        (new_slug, row_id),
                    )
        print()

    if dry_run:
        print("Dry-run complete. Re-run with --apply to persist changes.")
    else:
        conn.commit()
        print("Slug conflicts resolved and committed. ✅")


def main() -> int:
    args = parse_args()
    if not args.database_url:
        print("Error: provide --database-url or set $DATABASE_URL", file=sys.stderr)
        return 1

    try:
        with psycopg.connect(args.database_url, autocommit=False) as conn:
            conflicts = fetch_slug_conflicts(
                conn,
                include_schema=args.include_schema,
                exclude_schema=args.exclude_schema,
            )
            apply_fixes(conn, conflicts, dry_run=not args.apply)
    except psycopg.Error as exc:
        print(f"Database error: {exc}", file=sys.stderr)
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
