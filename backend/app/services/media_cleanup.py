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


async def request_lifecycle_evaluation(
    *,
    media_asset_ids: Iterable[str],
    trigger_source: str,
    subject_type: str,
    subject_id: str | None = None,
) -> int:
    normalized_ids = sorted(
        {
            str(media_asset_id).strip()
            for media_asset_id in media_asset_ids
            if str(media_asset_id or "").strip()
        }
    )
    logger.info(
        "MEDIA_LIFECYCLE_EVALUATION_REQUESTED",
        extra={
            "trigger_source": trigger_source,
            "subject_type": subject_type,
            "subject_id": subject_id,
            "media_asset_ids": normalized_ids,
            "requested_count": len(normalized_ids),
        },
    )
    return len(normalized_ids)


def _empty_storage_cleanup_report() -> dict[str, list[dict[str, str]]]:
    return {"deleted": [], "remaining": []}


def _storage_cleanup_entry(
    *,
    bucket: str,
    path: str,
    reason: str | None = None,
) -> dict[str, str]:
    entry = {
        "bucket": str(bucket or settings.media_source_bucket),
        "path": _normalized_storage_key(path),
    }
    if reason:
        entry["reason"] = str(reason)
    return entry


def _merge_storage_cleanup_report(
    summary: dict[str, list[dict[str, str]]],
    report: Mapping[str, Any] | None,
) -> None:
    if not report:
        return
    summary["deleted"].extend(list(report.get("deleted") or []))
    summary["remaining"].extend(list(report.get("remaining") or []))


def _normalized_storage_key(path: str | None) -> str:
    return str(path or "").strip().lstrip("/")


def _course_cover_source_prefix(course_id: str) -> str:
    return f"media/source/cover/courses/{str(course_id or '').strip().lstrip('/')}/"


def _canonical_media_asset_bucket(
    asset: Mapping[str, Any],
    object_path: str,
    *,
    identity: str,
) -> str | None:
    normalized_path = _normalized_storage_key(object_path)

    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    if identity == "playback" and media_type == "image" and purpose in {
        "course_cover",
        "profile_media",
    }:
        return settings.media_public_bucket
    if identity == "playback" and normalized_path:
        return storage_service.canonical_source_bucket_for_media_asset(asset)
    if identity == "original" and purpose:
        return storage_service.canonical_upload_bucket_for_media_asset(asset)
    if not normalized_path:
        return None
    if normalized_path.startswith("lessons/"):
        return settings.media_public_bucket
    return settings.media_source_bucket


def _asset_delete_targets(asset: Mapping[str, Any]) -> set[tuple[str, str]]:
    targets: set[tuple[str, str]] = set()

    original_path = _normalized_storage_key(asset.get("original_object_path"))
    if original_path:
        original_bucket = _canonical_media_asset_bucket(
            asset,
            original_path,
            identity="original",
        )
        if original_bucket:
            targets.add((str(original_bucket), original_path))

    playback_path = _normalized_storage_key(asset.get("playback_object_path"))
    if playback_path:
        playback_bucket = _canonical_media_asset_bucket(
            asset,
            playback_path,
            identity="playback",
        )
        if playback_bucket:
            targets.add((str(playback_bucket), playback_path))

    return targets


def _is_lesson_storage_path(path: str | None) -> bool:
    return _normalized_storage_key(path).startswith("lessons/")


async def _storage_object_exists(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> bool:
    normalized_bucket = str(storage_bucket or settings.media_source_bucket).strip()
    normalized_path = _normalized_storage_key(storage_path)
    if not normalized_bucket or not normalized_path:
        return False

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT 1
                FROM storage.objects
                WHERE bucket_id = %s
                  AND name = %s
                LIMIT 1
                """,
                (normalized_bucket, normalized_path),
            )
            row = await cur.fetchone()
    return bool(row)


async def _shared_storage_reference_counts(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> dict[str, int]:
    normalized_bucket = str(storage_bucket or "").strip() or None
    normalized_path = _normalized_storage_key(storage_path)
    if not normalized_path:
        return {"media_objects": 0, "lesson_media": 0}

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT
                  (
                    SELECT count(*)
                    FROM app.media_objects mo
                    WHERE mo.storage_path = %s
                      AND (
                        %s::text IS NULL
                        OR mo.storage_bucket = %s::text
                        OR mo.storage_bucket IS NULL
                      )
                  ) AS media_objects,
                  (
                    SELECT count(*)
                    FROM app.lesson_media lm
                    WHERE lm.storage_path = %s
                      AND (
                        %s::text IS NULL
                        OR lm.storage_bucket = %s::text
                        OR lm.storage_bucket IS NULL
                      )
                  ) AS lesson_media
                """,
                (
                    normalized_path,
                    normalized_bucket,
                    normalized_bucket,
                    normalized_path,
                    normalized_bucket,
                    normalized_bucket,
                ),
            )
            row = await cur.fetchone()
    return {
        "media_objects": int(row.get("media_objects") or 0) if row else 0,
        "lesson_media": int(row.get("lesson_media") or 0) if row else 0,
    }


async def _should_skip_storage_delete(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> bool:
    normalized_path = _normalized_storage_key(storage_path)
    if not normalized_path:
        return True

    reasons: list[str] = []
    if _is_lesson_storage_path(normalized_path):
        reasons.append("lesson_storage_prefix")

    reference_counts = await _shared_storage_reference_counts(
        storage_bucket=storage_bucket,
        storage_path=normalized_path,
    )
    if reference_counts["media_objects"] > 0:
        reasons.append(f"media_objects={reference_counts['media_objects']}")
    if reference_counts["lesson_media"] > 0:
        reasons.append(f"lesson_media={reference_counts['lesson_media']}")

    if not reasons:
        return False

    joined_reasons = ",".join(reasons)
    logger.warning(
        "MEDIA_CLEANUP_SHARED_STORAGE_DETECTED bucket=%s path=%s reasons=%s",
        storage_bucket or "<missing>",
        normalized_path,
        joined_reasons,
    )
    logger.info(
        "MEDIA_CLEANUP_DELETE_SKIPPED_SHARED_REFERENCE bucket=%s path=%s reasons=%s",
        storage_bucket or "<missing>",
        normalized_path,
        joined_reasons,
    )
    return True


async def _delete_storage_targets(
    targets: Iterable[tuple[str, str]],
) -> dict[str, list[dict[str, str]]]:
    report = _empty_storage_cleanup_report()
    for bucket, path in sorted(set(targets)):
        normalized_bucket = str(bucket or settings.media_source_bucket).strip() or str(
            settings.media_source_bucket
        )
        normalized_path = _normalized_storage_key(path)
        if not normalized_path:
            continue
        if await _should_skip_storage_delete(
            storage_bucket=normalized_bucket,
            storage_path=normalized_path,
        ):
            entry = _storage_cleanup_entry(
                bucket=normalized_bucket,
                path=normalized_path,
                reason="shared_reference",
            )
            report["remaining"].append(entry)
            logger.info(
                "MEDIA_CLEANUP_STORAGE_TARGET_REMAINING",
                extra=entry,
            )
            continue

        delete_reason: str | None = None
        try:
            service = storage_service.get_storage_service(normalized_bucket)
            deleted = await service.delete_object(normalized_path)
            if deleted:
                entry = _storage_cleanup_entry(
                    bucket=normalized_bucket,
                    path=normalized_path,
                )
                report["deleted"].append(entry)
                logger.info(
                    "MEDIA_CLEANUP_STORAGE_TARGET_DELETED",
                    extra=entry,
                )
                continue
        except storage_service.StorageServiceError as exc:
            delete_reason = str(exc)
            logger.warning(
                "Storage delete failed bucket=%s path=%s: %s",
                normalized_bucket,
                normalized_path,
                exc,
            )
        except Exception as exc:  # pragma: no cover - defensive logging
            delete_reason = str(exc)
            logger.warning(
                "Unexpected storage delete failure bucket=%s path=%s: %s",
                normalized_bucket,
                normalized_path,
                exc,
            )

        if not await _storage_object_exists(
            storage_bucket=normalized_bucket,
            storage_path=normalized_path,
        ):
            entry = _storage_cleanup_entry(
                bucket=normalized_bucket,
                path=normalized_path,
            )
            report["deleted"].append(entry)
            logger.info(
                "MEDIA_CLEANUP_STORAGE_TARGET_DELETED",
                extra=entry,
            )
            continue

        entry = _storage_cleanup_entry(
            bucket=normalized_bucket,
            path=normalized_path,
            reason=delete_reason or "delete_not_confirmed",
        )
        report["remaining"].append(entry)
        logger.info(
            "MEDIA_CLEANUP_STORAGE_TARGET_REMAINING",
            extra=entry,
        )
    return report


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


async def _delete_media_object_bytes(storage_path: str, storage_bucket: str | None) -> None:
    if not storage_path:
        return

    normalized_bucket = (storage_bucket or "").strip() or None
    if normalized_bucket:
        try:
            service = storage_service.get_storage_service(normalized_bucket)
            if service.enabled:
                normalized_path = str(storage_path).lstrip("/")
                candidates: list[str] = []
                bucket_prefix = f"{normalized_bucket}/"
                if normalized_path.startswith(bucket_prefix):
                    stripped = normalized_path[len(bucket_prefix) :].lstrip("/")
                    if stripped:
                        candidates.append(stripped)
                candidates.append(normalized_path)
                for key in candidates:
                    try:
                        await service.delete_object(key)
                        break
                    except storage_service.StorageServiceError as exc:
                        logger.warning(
                            "Storage delete failed bucket=%s path=%s: %s",
                            normalized_bucket,
                            key,
                            exc,
                        )
        except Exception as exc:  # pragma: no cover - defensive
            logger.warning(
                "Failed to cleanup remote media object bucket=%s path=%s: %s",
                normalized_bucket,
                storage_path,
                exc,
            )

    _delete_local_media_object_file(storage_path, normalized_bucket)


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
                    AND NOT EXISTS (
                      SELECT 1 FROM app.profile_media_placements pmp
                      WHERE pmp.media_asset_id = ma.id
                    )
                  ORDER BY ma.id ASC
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
                    ma.ingest_format,
                    ma.playback_object_path,
                    ma.playback_format,
                    ma.state::text as state
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
                    AND (
                      (
                        ma.course_id IS NOT NULL
                        AND NOT EXISTS (
                          SELECT 1
                          FROM app.courses existing_course
                          WHERE existing_course.id = ma.course_id
                        )
                      )
                      OR (
                        ma.course_id IS NULL
                        AND ma.original_object_path LIKE 'media/source/cover/courses/%'
                        AND NOT EXISTS (
                          SELECT 1
                          FROM app.courses existing_course
                          WHERE ma.original_object_path LIKE
                            ('media/source/cover/courses/' || existing_course.id::text || '/%')
                        )
                      )
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.profile_media_placements pmp
                      WHERE pmp.media_asset_id = ma.id
                    )
                  ORDER BY ma.id ASC
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
                    ma.ingest_format,
                    ma.playback_object_path,
                    ma.playback_format,
                    ma.state::text as state
                )
                SELECT * FROM deleted
                """,
                (limit,),
            )
            rows = await cur.fetchall()
            await conn.commit()
            return [dict(row) for row in rows]


async def prune_course_cover_assets(*, course_id: str, limit: int = 100) -> int:
    """Prune unreferenced cover assets for a course, keeping the current cover id."""
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH current AS (
                  SELECT c.cover_media_id
                  FROM app.courses c
                  WHERE c.id = %s
                ),
                candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.purpose = 'course_cover'
                    AND (
                      ma.course_id = %s::uuid
                      OR (
                        ma.course_id IS NULL
                        AND ma.original_object_path LIKE %s
                      )
                    )
                    AND ma.id IS DISTINCT FROM (SELECT cover_media_id FROM current)
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.profile_media_placements pmp
                      WHERE pmp.media_asset_id = ma.id
                    )
                  ORDER BY ma.id ASC
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
                    ma.ingest_format,
                    ma.playback_object_path,
                    ma.playback_format,
                    ma.state::text as state
                )
                SELECT * FROM deleted
                """,
                (course_id, _course_cover_source_prefix(course_id) + "%", limit),
            )
            deleted_rows = await cur.fetchall()
            await conn.commit()

    deleted_assets = [dict(row) for row in deleted_rows]
    storage_report = _empty_storage_cleanup_report()
    for asset in deleted_assets:
        _merge_storage_cleanup_report(
            storage_report,
            await _delete_storage_targets(_asset_delete_targets(asset)),
        )
    logger.info(
        "MEDIA_CLEANUP_PRUNE_COURSE_COVER_SUMMARY",
        extra={
            "course_id": course_id,
            "deleted_assets": len(deleted_assets),
            "limit": limit,
            "storage_targets_deleted": len(storage_report["deleted"]),
            "storage_targets_remaining": len(storage_report["remaining"]),
        },
    )
    return len(deleted_assets)


async def delete_course_cover_assets_for_course(
    *,
    course_id: str,
    limit: int = 250,
) -> dict[str, Any]:
    """Delete all cover assets for a course once the cover has been cleared."""
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                WITH candidates AS (
                  SELECT ma.id
                  FROM app.media_assets ma
                  WHERE ma.purpose = 'course_cover'
                    AND (
                      ma.course_id = %s::uuid
                      OR (
                        ma.course_id IS NULL
                        AND ma.original_object_path LIKE %s
                      )
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id
                    )
                    AND NOT EXISTS (
                      SELECT 1 FROM app.profile_media_placements pmp
                      WHERE pmp.media_asset_id = ma.id
                    )
                  ORDER BY ma.id ASC
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
                    ma.ingest_format,
                    ma.playback_object_path,
                    ma.playback_format,
                    ma.state::text as state
                )
                SELECT * FROM deleted
                """,
                (course_id, _course_cover_source_prefix(course_id) + "%", limit),
            )
            deleted_rows = await cur.fetchall()
            await conn.commit()

    deleted_assets = [dict(row) for row in deleted_rows]
    storage_report = _empty_storage_cleanup_report()
    for asset in deleted_assets:
        _merge_storage_cleanup_report(
            storage_report,
            await _delete_storage_targets(_asset_delete_targets(asset)),
        )
    logger.info(
        "MEDIA_CLEANUP_DELETE_COURSE_COVERS_SUMMARY",
        extra={
            "course_id": course_id,
            "deleted_assets": len(deleted_assets),
            "limit": limit,
            "storage_targets_deleted": len(storage_report["deleted"]),
            "storage_targets_remaining": len(storage_report["remaining"]),
        },
    )
    return {
        "deleted_assets": len(deleted_assets),
        "storage_cleanup": storage_report,
    }


async def garbage_collect_media(*, batch_size: int = 200, max_batches: int = 10) -> dict[str, int]:
    """Best-effort cleanup for orphan media assets/objects after cascade deletes.

    Safe to run repeatedly (idempotent-ish). Intended to be called after course/module/lesson deletes.
    """
    deleted_audio_assets = 0
    deleted_cover_assets = 0
    deleted_media_objects = 0
    storage_targets_deleted = 0
    storage_targets_remaining = 0

    for _ in range(max_batches):
        batch = await _delete_unreferenced_lesson_audio_assets(limit=batch_size)
        if not batch:
            break
        deleted_audio_assets += len(batch)
        for asset in batch:
            report = await _delete_storage_targets(_asset_delete_targets(asset))
            storage_targets_deleted += len(report["deleted"])
            storage_targets_remaining += len(report["remaining"])

    for _ in range(max_batches):
        batch = await _delete_orphan_course_cover_assets_for_deleted_courses(limit=batch_size)
        if not batch:
            break
        deleted_cover_assets += len(batch)
        for asset in batch:
            report = await _delete_storage_targets(_asset_delete_targets(asset))
            storage_targets_deleted += len(report["deleted"])
            storage_targets_remaining += len(report["remaining"])

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
                        SELECT 1 FROM app.home_player_uploads hpu WHERE hpu.media_id = mo.id
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
                        SELECT 1 FROM app.home_player_uploads hpu WHERE hpu.media_id = mo.id
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
                await _delete_media_object_bytes(
                    str(storage_path),
                    str(storage_bucket) if storage_bucket else None,
                )

    summary = {
        "media_assets_lesson_audio_deleted": deleted_audio_assets,
        "media_assets_course_cover_deleted": deleted_cover_assets,
        "media_objects_deleted": deleted_media_objects,
        "storage_targets_deleted": storage_targets_deleted,
        "storage_targets_remaining": storage_targets_remaining,
    }
    logger.info(
        "MEDIA_CLEANUP_GARBAGE_COLLECT_SUMMARY",
        extra={
            **summary,
            "batch_size": batch_size,
            "max_batches": max_batches,
        },
    )
    return summary


async def delete_media_asset_and_objects(*, media_id: str) -> bool:
    """Delete a media asset and its storage objects.

    No-op when the media asset is still referenced by app.lesson_media, app.courses,
    app.home_player_uploads, or app.profile_media_placements.
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
                  AND NOT EXISTS (
                    SELECT 1 FROM app.profile_media_placements pmp
                    WHERE pmp.media_asset_id = ma.id
                  )
                RETURNING
                  ma.id,
                  ma.media_type,
                  ma.purpose,
                  ma.original_object_path,
                  ma.ingest_format,
                  ma.playback_object_path,
                  ma.playback_format,
                  ma.state::text as state
                """,
                (media_id,),
            )
            row = await cur.fetchone()
            await conn.commit()

    if not row:
        logger.info(
            "MEDIA_CLEANUP_DELETE_MEDIA_ASSET",
            extra={"media_id": media_id, "deleted": False},
        )
        return False

    asset = dict(row)
    storage_report = await _delete_storage_targets(_asset_delete_targets(asset))
    logger.info(
        "MEDIA_CLEANUP_DELETE_MEDIA_ASSET",
        extra={
            "media_id": media_id,
            "deleted": True,
            "storage_targets_deleted": len(storage_report["deleted"]),
            "storage_targets_remaining": len(storage_report["remaining"]),
        },
    )
    return True
