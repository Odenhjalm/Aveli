from __future__ import annotations

from typing import Any

from ..db import pool
from ..repositories import lesson_completions
from . import courses_service


class LessonCompletionServiceInvariantError(RuntimeError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail)


async def complete_lesson(
    *,
    user_id: str,
    lesson_id: str,
) -> dict[str, Any]:
    async with pool.connection() as active_conn:  # type: ignore
        access = await courses_service.read_canonical_lesson_access(
            user_id,
            lesson_id,
            conn=active_conn,
        )
        if access["lesson"] is None:
            return {"status": "lesson_not_found", "completion": None}
        if access["can_access"] is False:
            return {"status": "access_denied", "completion": None}

        course_id = str(access["lesson"].get("course_id") or "").strip()
        if not course_id:
            raise LessonCompletionServiceInvariantError(
                "lesson completion access result is missing course_id"
            )

        existing = await lesson_completions.get_lesson_completion(
            user_id=user_id,
            lesson_id=lesson_id,
            conn=active_conn,
        )
        if existing is not None:
            return {"status": "already_completed", "completion": existing}

        try:
            created = await lesson_completions.create_lesson_completion(
                user_id=user_id,
                course_id=course_id,
                lesson_id=lesson_id,
                completion_source="manual",
                conn=active_conn,
            )
        except lesson_completions.LessonCompletionAlreadyExistsError:
            existing = await lesson_completions.get_lesson_completion(
                user_id=user_id,
                lesson_id=lesson_id,
                conn=active_conn,
            )
            if existing is None:
                raise LessonCompletionServiceInvariantError(
                    "lesson completion duplicate was raised but no row was readable"
                )
            return {"status": "already_completed", "completion": existing}
        except (
            lesson_completions.LessonCompletionUnknownUserError,
            lesson_completions.LessonCompletionInvalidLessonCourseError,
            lesson_completions.LessonCompletionInvalidSourceError,
        ) as exc:
            raise LessonCompletionServiceInvariantError(
                "lesson completion repository raised an invariant violation"
            ) from exc

        await active_conn.commit()
        return {"status": "completed", "completion": created}


__all__ = [
    "LessonCompletionServiceInvariantError",
    "complete_lesson",
]
