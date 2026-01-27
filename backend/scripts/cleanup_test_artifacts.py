#!/usr/bin/env python3
"""Delete leftover QA/test artifacts from the database.

Targets (conservative):
- Users with emails in QA domains (e.g. *@aveli.local, *@qa.wisdom)
- Courses created by QA smoke scripts (slug prefix "quiz-test-" or title "Quiz Test ...")
- Seminars created by QA smoke scripts (title "QA Session Smoke")

Safety:
- Defaults to DRY RUN (no writes).
- Requires --apply to perform deletes.

Usage:
  python scripts/cleanup_test_artifacts.py --db-url "$SUPABASE_DB_URL"
  python scripts/cleanup_test_artifacts.py --db-url "$SUPABASE_DB_URL" --apply
"""

from __future__ import annotations

import argparse
import os
import sys
import asyncio
from dataclasses import dataclass
from typing import Iterable, Sequence

import psycopg


def _ensure_db_url(url: str | None) -> str:
    if not url:
        raise SystemExit("Missing database url (--db-url or SUPABASE_DB_URL)")
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}sslmode=require"


@dataclass(frozen=True)
class DeletionTarget:
    table: str
    id: str
    label: str


def _fetch_all(cur: psycopg.Cursor, query: str, params: Sequence[object] = ()) -> list[tuple]:
    cur.execute(query, params)
    return list(cur.fetchall())


def _iter_targets(conn: psycopg.Connection) -> Iterable[DeletionTarget]:
    with conn.cursor() as cur:
        for course_id, slug, title in _fetch_all(
            cur,
            """
            SELECT id::text, slug, title
            FROM app.courses
            WHERE slug ILIKE 'quiz-test-%'
               OR title ILIKE 'Quiz Test %'
            ORDER BY created_at DESC
            """,
        ):
            yield DeletionTarget(
                table="app.courses",
                id=course_id,
                label=f"{slug} | {title}",
            )

        for seminar_id, title in _fetch_all(
            cur,
            """
            SELECT id::text, title
            FROM app.seminars
            WHERE title = 'QA Session Smoke'
            ORDER BY created_at DESC
            """,
        ):
            yield DeletionTarget(
                table="app.seminars",
                id=seminar_id,
                label=title,
            )

        for user_id, email in _fetch_all(
            cur,
            """
            SELECT id::text, email
            FROM auth.users
            WHERE lower(email) LIKE '%@aveli.local'
               OR lower(email) LIKE '%@qa.wisdom'
            ORDER BY created_at DESC
            """,
        ):
            yield DeletionTarget(
                table="auth.users",
                id=user_id,
                label=email,
            )


def _delete_targets(conn: psycopg.Connection, targets: list[DeletionTarget]) -> None:
    if not targets:
        return
    with conn.cursor() as cur:
        # Delete in an order that avoids FK issues.
        for table in ("app.courses", "app.seminars", "auth.users"):
            for target in [t for t in targets if t.table == table]:
                cur.execute(f"DELETE FROM {table} WHERE id = %s", (target.id,))
    conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--db-url",
        default=os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL"),
        help="Postgres connection url (default: SUPABASE_DB_URL or DATABASE_URL)",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform deletes (default is dry-run)",
    )
    args = parser.parse_args()

    db_url = _ensure_db_url(args.db_url)
    with psycopg.connect(db_url) as conn:
        targets = list(_iter_targets(conn))

        if not targets:
            print("No QA/test artifacts found.")
            return 0

        print("Found QA/test artifacts:")
        for t in targets:
            print(f"- {t.table} id={t.id} {t.label}")

        if not args.apply:
            print("\nDry-run only. Re-run with --apply to delete.")
            return 0

        confirm = os.environ.get("CLEANUP_TEST_DATA") == "1"
        if not confirm:
            print(
                "\nRefusing to delete without CLEANUP_TEST_DATA=1 in the environment.",
                file=sys.stderr,
            )
            return 2

        _delete_targets(conn, targets)
        try:
            from app.db import pool as async_pool
            from app.services import media_cleanup

            async def _run_media_gc():
                if async_pool.closed:
                    await async_pool.open(wait=True)
                try:
                    return await media_cleanup.garbage_collect_media()
                finally:
                    await async_pool.close()

            results = asyncio.run(_run_media_gc())
            print(
                "\nMedia GC:",
                f"lesson_audio_assets={results.get('media_assets_lesson_audio_deleted')}",
                f"course_cover_assets={results.get('media_assets_course_cover_deleted')}",
                f"media_objects={results.get('media_objects_deleted')}",
            )
        except Exception as exc:
            print(f"\n[cleanup] warning: media GC failed: {exc}", file=sys.stderr)

        print(f"\nDeleted {len(targets)} records.")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
