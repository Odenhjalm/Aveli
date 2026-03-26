from typing import Any

from .entitlement_service import fetch_one


async def get_active_runtime_media_for_lesson_media(
    db: Any, lesson_media_id: str
) -> dict[str, Any] | None:
    row = await fetch_one(
        db,
        """
        SELECT
            id,
            lesson_media_id,
            lesson_id,
            course_id,
            media_asset_id,
            media_object_id,
            reference_type,
            auth_scope,
            fallback_policy,
            active
        FROM app.runtime_media
        WHERE lesson_media_id = $1
          AND active = true
        LIMIT 1
        """,
        lesson_media_id,
    )
    if row is None:
        return None
    return dict(row)
