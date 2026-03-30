from typing import Any


async def get_active_runtime_media_for_lesson_media(
    db: Any, lesson_media_id: str
) -> dict[str, Any] | None:
    await db.execute(
        """
        select
            rm.lesson_media_id,
            rm.lesson_id,
            rm.course_id,
            rm.media_asset_id,
            rm.media_type::text as media_type
        from app.runtime_media as rm
        where rm.lesson_media_id = %s
        limit 1
        """,
        (lesson_media_id,),
    )
    row = await db.fetchone()
    return dict(row) if row else None


async def get_active_runtime_media(
    db: Any,
    lesson_media_id: str,
) -> dict[str, Any] | None:
    return await get_active_runtime_media_for_lesson_media(
        db=db,
        lesson_media_id=lesson_media_id,
    )
