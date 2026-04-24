from __future__ import annotations

from typing import Any

from ..repositories import courses as courses_repo
from . import courses_service


async def read_intro_selection_state(
    *,
    user_id: str,
) -> dict[str, Any]:
    progress_rows = await courses_repo.list_intro_selection_progress_rows(user_id=user_id)
    enrolled_intro_course_ids = {
        str(row.get("course_id") or "")
        for row in progress_rows
        if str(row.get("course_id") or "").strip()
    }

    for row in progress_rows:
        current_unlock_position = int(row.get("current_unlock_position") or 0)
        max_lesson_position = int(row.get("max_lesson_position") or 0)
        if current_unlock_position < max_lesson_position:
            return {
                "selection_locked": True,
                "selection_lock_reason": "incomplete_drip",
                "eligible_courses": [],
            }

    for row in progress_rows:
        completed_lesson_count = int(row.get("completed_lesson_count") or 0)
        lesson_count = int(row.get("lesson_count") or 0)
        if completed_lesson_count < lesson_count:
            return {
                "selection_locked": True,
                "selection_lock_reason": "incomplete_lesson_completion",
                "eligible_courses": [],
            }

    eligible_courses = [
        dict(row)
        for row in await courses_service.list_public_courses(
            search=None,
            limit=None,
            group_position=None,
        )
        if str(row.get("required_enrollment_source") or "").strip() == "intro_enrollment"
        and str(row.get("id") or "").strip() not in enrolled_intro_course_ids
    ]

    return {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": eligible_courses,
    }


__all__ = ["read_intro_selection_state"]
