from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from psycopg import errors
from psycopg.rows import dict_row

ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.db import pool
from app.utils.media_paths import normalize_storage_path, storage_path_has_bucket_prefix


TABLES: tuple[str, ...] = ("app.media_objects", "app.lesson_media")


async def _migrate_table(table_name: str) -> tuple[int, int, int]:
    fixed = 0
    skipped = 0
    conflicts = 0

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                SELECT id, storage_bucket, storage_path
                FROM {table_name}
                WHERE storage_path IS NOT NULL
                """
            )
            rows = await cur.fetchall()

            for row in rows:
                row_id = row.get("id")
                storage_bucket = str(row.get("storage_bucket") or "").strip().strip("/")
                storage_path = str(row.get("storage_path") or "")

                if not storage_path_has_bucket_prefix(storage_bucket, storage_path):
                    skipped += 1
                    continue

                try:
                    normalized = normalize_storage_path(storage_bucket, storage_path)
                except ValueError:
                    skipped += 1
                    print(
                        f"Skipped {table_name} id={row_id}: invalid storage_path={storage_path!r}"
                    )
                    continue

                await cur.execute("SAVEPOINT storage_path_fix")
                try:
                    await cur.execute(
                        f"UPDATE {table_name} SET storage_path = %s WHERE id = %s",
                        (normalized, row_id),
                    )
                except errors.UniqueViolation:
                    await cur.execute("ROLLBACK TO SAVEPOINT storage_path_fix")
                    conflicts += 1
                    print(
                        f"Conflict {table_name} id={row_id}: "
                        f"{storage_path!r} -> {normalized!r}"
                    )
                else:
                    await cur.execute("RELEASE SAVEPOINT storage_path_fix")
                    fixed += 1
                    print(f"Fixed {table_name} id={row_id}: {storage_path!r} -> {normalized!r}")

            await conn.commit()

    return fixed, skipped, conflicts


async def migrate() -> None:
    if pool.closed:
        await pool.open(wait=True)

    total_fixed = 0
    total_skipped = 0
    total_conflicts = 0
    try:
        for table_name in TABLES:
            fixed, skipped, conflicts = await _migrate_table(table_name)
            total_fixed += fixed
            total_skipped += skipped
            total_conflicts += conflicts
            print(
                f"{table_name}: fixed={fixed} skipped={skipped} conflicts={conflicts}"
            )
    finally:
        await pool.close()

    print(
        "Migration complete: "
        f"fixed={total_fixed} skipped={total_skipped} conflicts={total_conflicts}"
    )


if __name__ == "__main__":
    asyncio.run(migrate())
