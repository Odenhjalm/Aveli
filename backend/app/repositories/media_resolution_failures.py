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
