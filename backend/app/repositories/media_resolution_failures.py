from __future__ import annotations

import logging
from typing import Any

from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import pool

logger = logging.getLogger(__name__)

_ALLOWED_MODES = {"editor_insert", "editor_preview", "student_render"}
_ALLOWED_REASONS = {
    "missing_object",
    "bucket_mismatch",
    "key_format_drift",
    "cannot_sign",
    "unsupported",
}


def _test_visibility_clause(alias: str) -> str:
    return f"app.is_test_row_visible({alias}.is_test, {alias}.test_session_id)"


def normalize_mode(value: str | None) -> str:
    normalized = (value or "").strip().lower()
    if normalized in _ALLOWED_MODES:
        return normalized
    return "student_render"


def normalize_reason(value: str | None) -> str:
    normalized = (value or "").strip().lower()
    if normalized in _ALLOWED_REASONS:
        return normalized
    return "unsupported"


async def record_media_resolution_failure(
    *,
    lesson_media_id: str | None,
    mode: str | None,
    reason: str | None,
    details: dict[str, Any] | None = None,
) -> None:
    """Best-effort insert into app.media_resolution_failures.

    The table may not exist if migrations haven't been applied yet; failures are
    intentionally swallowed so media playback does not break due to telemetry.
    """

    media_id = (lesson_media_id or "").strip() or None
    if not media_id:
        return

    normalized_mode = normalize_mode(mode)
    normalized_reason = normalize_reason(reason)
    payload = Jsonb(details or {})

    try:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    INSERT INTO app.media_resolution_failures (
                      lesson_media_id,
                      mode,
                      reason,
                      details
                    )
                    VALUES (%s, %s, %s, %s)
                    """,
                    (media_id, normalized_mode, normalized_reason, payload),
                )
                await conn.commit()
    except errors.UndefinedTable:
        logger.debug(
            "media resolution telemetry table missing; skipping insert lesson_media_id=%s",
            media_id,
        )
    except Exception:  # pragma: no cover - defensive telemetry
        logger.exception(
            "Failed to record media resolution failure lesson_media_id=%s mode=%s reason=%s",
            media_id,
            normalized_mode,
            normalized_reason,
        )


async def list_recent_media_resolution_failures(
    *,
    limit: int = 20,
    media_asset_id: str | None = None,
) -> list[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 20), 100))
    normalized_media_asset_id = str(media_asset_id or "").strip() or None
    try:
        async with pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                if normalized_media_asset_id is None:
                    query = f"""
                            SELECT
                              mrf.id,
                              mrf.created_at,
                              mrf.lesson_media_id,
                              mrf.mode,
                              mrf.reason,
                              mrf.details,
                              lm.media_asset_id,
                              lm.lesson_id,
                              l.course_id
                            FROM app.media_resolution_failures mrf
                            LEFT JOIN app.lesson_media lm ON lm.id = mrf.lesson_media_id
                            LEFT JOIN app.lessons l ON l.id = lm.lesson_id
                            WHERE ({_test_visibility_clause("lm")} OR lm.id IS NULL)
                              AND ({_test_visibility_clause("l")} OR l.id IS NULL)
                            ORDER BY mrf.created_at DESC, mrf.id DESC
                            LIMIT %s::int
                            """
                    params = (capped_limit,)
                else:
                    query = f"""
                            SELECT
                              mrf.id,
                              mrf.created_at,
                              mrf.lesson_media_id,
                              mrf.mode,
                              mrf.reason,
                              mrf.details,
                              lm.media_asset_id,
                              lm.lesson_id,
                              l.course_id
                            FROM app.media_resolution_failures mrf
                            LEFT JOIN app.lesson_media lm ON lm.id = mrf.lesson_media_id
                            LEFT JOIN app.lessons l ON l.id = lm.lesson_id
                            WHERE lm.media_asset_id = %s::uuid
                              AND ({_test_visibility_clause("lm")} OR lm.id IS NULL)
                              AND ({_test_visibility_clause("l")} OR l.id IS NULL)
                            ORDER BY mrf.created_at DESC, mrf.id DESC
                            LIMIT %s::int
                            """
                    params = (normalized_media_asset_id, capped_limit)
                await cur.execute(query, params)
                rows = await cur.fetchall()
    except errors.UndefinedTable:
        return []
    return [dict(row) for row in rows]
