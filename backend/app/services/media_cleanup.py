from __future__ import annotations

import logging
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from psycopg import errors
from psycopg.rows import dict_row

from ..config import settings
from ..db import pool
from ..services import storage_service

logger = logging.getLogger(__name__)


def _asset_delete_targets(asset: Mapping[str, Any]) -> set[tuple[str, str]]:
    targets: set[tuple[str, str]] = set()

    original_path = asset.get("original_object_path")
    original_bucket = asset.get("storage_bucket") or settings.media_source_bucket
    if original_path and original_bucket:
        targets.add((str(original_bucket), str(original_path)))

        if (asset.get("media_type") or "").lower() == "audio":
            normalized = str(original_path).lstrip("/")
            prefix = "media/source/audio/"
            if normalized.startswith(prefix):
                normalized = "media/derived/audio/" + normalized[len(prefix) :]
            else:
                normalized = "media/derived/audio/" + normalized
            derived_path = Path(normalized).with_suffix(".mp3").as_posix()
            targets.add((str(original_bucket), derived_path))

    streaming_path = asset.get("streaming_object_path")
    if streaming_path:
        streaming_bucket = asset.get("streaming_storage_bucket") or original_bucket
        if streaming_bucket:
            targets.add((str(streaming_bucket), str(streaming_path)))

    return targets


async def _delete_storage_targets(targets: Iterable[tuple[str, str]]) -> None:
    for bucket, path in sorted(set(targets)):
        try:
            service = storage_service.get_storage_service(bucket)
            await service.delete_object(path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Storage delete failed bucket=%s path=%s: %s",
                bucket,
                path,
                exc,
            )


def _delete_local_media_object_file(storage_path: str, storage_bucket: str | None) -> None:
    if not storage_path:
        return

    candidates: list[Path] = []
    uploads_root = Path(__file__).resolve().parents[2] / "assets" / "uploads"
    try:
        relative = Path(str(storage_path))
        if not relative.is_absolute() and ".." not in relative.parts:
            candidate = (uploads_root / relative).resolve()
            if str(candidate).startswith(str(uploads_root.resolve())):
                candidates.append(candidate)
    except Exception:  # pragma: no cover - defensive
        pass

    base_dir = Path(settings.media_root)
    if storage_bucket:
        candidates.append(base_dir / str(storage_bucket) / str(storage_path))
    candidates.append(base_dir / str(storage_path))

    seen: set[Path] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        try:
            if candidate.exists() and candidate.is_file():
                candidate.unlink()
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.warning("Failed to delete media object file %s: %s", candidate, exc)


async def _delete_unreferenced_lesson_audio_assets(*, limit: int) -> list[dict[str, Any]]:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.purpose = 'lesson_audio'
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                  ORDER BY ma.created_at ASC
                  LIMIT %s
                  FOR UPDATE SKIP LOCKED
                ),
                deleted AS (
                  DELETE FROM app.media_assets ma
                  USING candidates c
                  WHERE ma.id = c.id
                  RETURNING
                    ma.id,
                    ma.media_type,
                    ma.purpose,
                    ma.original_object_path,
                    ma.storage_bucket,
                    ma.streaming_object_path,
                    ma.streaming_storage_bucket
                )
                SELECT * FROM deleted
                """,
                (limit,),
            )
            rows = await cur.fetchall()
            await conn.commit()
            return [dict(row) for row in rows]


async def _delete_orphan_course_cover_assets_for_deleted_courses(
    *,
    limit: int,
) -> list[dict[str, Any]]:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.purpose = 'course_cover'
                    AND ma.course_id IS NULL
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                  ORDER BY ma.created_at ASC
                  LIMIT %s
                  FOR UPDATE SKIP LOCKED
                ),
                deleted AS (
                  DELETE FROM app.media_assets ma
                  USING candidates c
                  WHERE ma.id = c.id
                  RETURNING
                    ma.id,
                    ma.media_type,
                    ma.purpose,
                    ma.original_object_path,
                    ma.storage_bucket,
                    ma.streaming_object_path,
                    ma.streaming_storage_bucket
                )
                SELECT * FROM deleted
                """,
                (limit,),
            )
            rows = await cur.fetchall()
            await conn.commit()
            return [dict(row) for row in rows]


async def prune_course_cover_assets(*, course_id: str, limit: int = 100) -> int:
    """Prune cover assets for a course, keeping the current + latest cover ids."""
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH current AS (
                  SELECT c.cover_media_id
                  FROM app.courses c
                  WHERE c.id = %s
                ),
                latest AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.course_id = %s
                    AND ma.purpose = 'course_cover'
                  ORDER BY ma.created_at DESC
                  LIMIT 1
                ),
                candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.course_id = %s
                    AND ma.purpose = 'course_cover'
                    AND ma.id IS DISTINCT FROM (SELECT cover_media_id FROM current)
                    AND ma.id IS DISTINCT FROM (SELECT id FROM latest)
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                  ORDER BY ma.created_at ASC
                  LIMIT %s
                  FOR UPDATE SKIP LOCKED
                ),
                deleted AS (
                  DELETE FROM app.media_assets ma
                  USING candidates c
                  WHERE ma.id = c.id
                  RETURNING
                    ma.id,
                    ma.media_type,
                    ma.purpose,
                    ma.original_object_path,
                    ma.storage_bucket,
                    ma.streaming_object_path,
                    ma.streaming_storage_bucket
                )
                SELECT * FROM deleted
                """,
                (course_id, course_id, course_id, limit),
            )
            deleted_rows = await cur.fetchall()
            await conn.commit()

    deleted_assets = [dict(row) for row in deleted_rows]
    for asset in deleted_assets:
        await _delete_storage_targets(_asset_delete_targets(asset))
    return len(deleted_assets)


async def delete_course_cover_assets_for_course(*, course_id: str, limit: int = 250) -> int:
    """Delete all cover assets for a course once the cover has been cleared."""
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.course_id = %s
                    AND ma.purpose = 'course_cover'
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                  ORDER BY ma.created_at ASC
                  LIMIT %s
                  FOR UPDATE SKIP LOCKED
                ),
                deleted AS (
                  DELETE FROM app.media_assets ma
                  USING candidates c
                  WHERE ma.id = c.id
                  RETURNING
                    ma.id,
                    ma.media_type,
                    ma.purpose,
                    ma.original_object_path,
                    ma.storage_bucket,
                    ma.streaming_object_path,
                    ma.streaming_storage_bucket
                )
                SELECT * FROM deleted
                """,
                (course_id, limit),
            )
            deleted_rows = await cur.fetchall()
            await conn.commit()

    deleted_assets = [dict(row) for row in deleted_rows]
    for asset in deleted_assets:
        await _delete_storage_targets(_asset_delete_targets(asset))
    return len(deleted_assets)


async def garbage_collect_media(*, batch_size: int = 200, max_batches: int = 10) -> dict[str, int]:
    """Best-effort cleanup for orphan media assets/objects after cascade deletes.

    Safe to run repeatedly (idempotent-ish). Intended to be called after course/module/lesson deletes.
    """
    deleted_audio_assets = 0
    deleted_cover_assets = 0
    deleted_media_objects = 0

    for _ in range(max_batches):
        batch = await _delete_unreferenced_lesson_audio_assets(limit=batch_size)
        if not batch:
            break
        deleted_audio_assets += len(batch)
        for asset in batch:
            await _delete_storage_targets(_asset_delete_targets(asset))

    for _ in range(max_batches):
        batch = await _delete_orphan_course_cover_assets_for_deleted_courses(limit=batch_size)
        if not batch:
            break
        deleted_cover_assets += len(batch)
        for asset in batch:
            await _delete_storage_targets(_asset_delete_targets(asset))

    for _ in range(max_batches):
        async with pool.connection() as conn:  # type: ignore
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                deleted_rows = []
                queries = [
                    """
                    WITH candidates AS (
                      SELECT mo.id
                      FROM app.media_objects mo
                      WHERE NOT EXISTS (
                        SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.teacher_profile_media tpm WHERE tpm.cover_media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.meditations m WHERE m.media_id = mo.id
                      )
                      ORDER BY mo.created_at ASC
                      LIMIT %s
                      FOR UPDATE SKIP LOCKED
                    ),
                    deleted AS (
                      DELETE FROM app.media_objects mo
                      USING candidates c
                      WHERE mo.id = c.id
                      RETURNING mo.storage_path, mo.storage_bucket
                    )
                    SELECT * FROM deleted
                    """,
                    """
                    WITH candidates AS (
                      SELECT mo.id
                      FROM app.media_objects mo
                      WHERE NOT EXISTS (
                        SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.meditations m WHERE m.media_id = mo.id
                      )
                      ORDER BY mo.created_at ASC
                      LIMIT %s
                      FOR UPDATE SKIP LOCKED
                    ),
                    deleted AS (
                      DELETE FROM app.media_objects mo
                      USING candidates c
                      WHERE mo.id = c.id
                      RETURNING mo.storage_path, mo.storage_bucket
                    )
                    SELECT * FROM deleted
                    """,
                    """
                    WITH candidates AS (
                      SELECT mo.id
                      FROM app.media_objects mo
                      WHERE NOT EXISTS (
                        SELECT 1 FROM app.lesson_media lm WHERE lm.media_id = mo.id
                      )
                      AND NOT EXISTS (
                        SELECT 1 FROM app.profiles p WHERE p.avatar_media_id = mo.id
                      )
                      ORDER BY mo.created_at ASC
                      LIMIT %s
                      FOR UPDATE SKIP LOCKED
                    ),
                    deleted AS (
                      DELETE FROM app.media_objects mo
                      USING candidates c
                      WHERE mo.id = c.id
                      RETURNING mo.storage_path, mo.storage_bucket
                    )
                    SELECT * FROM deleted
                    """,
                ]
                for query in queries:
                    try:
                        await cur.execute(query, (batch_size,))
                        deleted_rows = await cur.fetchall()
                        break
                    except errors.UndefinedTable:
                        await conn.rollback()
                await conn.commit()

        if not deleted_rows:
            break
        deleted_media_objects += len(deleted_rows)
        for row in deleted_rows:
            storage_path = row.get("storage_path")
            storage_bucket = row.get("storage_bucket")
            if storage_path:
                _delete_local_media_object_file(str(storage_path), str(storage_bucket) if storage_bucket else None)

    return {
        "media_assets_lesson_audio_deleted": deleted_audio_assets,
        "media_assets_course_cover_deleted": deleted_cover_assets,
        "media_objects_deleted": deleted_media_objects,
    }


async def delete_media_asset_and_objects(*, media_id: str) -> bool:
    """Delete a media asset and its storage objects.

    No-op when the media asset is still referenced by app.lesson_media, app.courses,
    or app.home_player_uploads.
    """

    if not media_id:
        return False

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                DELETE FROM app.media_assets ma
                WHERE ma.id = %s
                  AND NOT EXISTS (
                    SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                  )
                  AND NOT EXISTS (
                    SELECT 1 FROM app.home_player_uploads hpu WHERE hpu.media_asset_id = ma.id
                  )
                RETURNING
                  ma.id,
                  ma.media_type,
                  ma.purpose,
                  ma.original_object_path,
                  ma.storage_bucket,
                  ma.streaming_object_path,
                  ma.streaming_storage_bucket
                """,
                (media_id,),
            )
            row = await cur.fetchone()
            await conn.commit()

    if not row:
        return False

    asset = dict(row)
    await _delete_storage_targets(_asset_delete_targets(asset))
    return True
