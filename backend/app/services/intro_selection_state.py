from __future__ import annotations

from typing import Any

from ..repositories import courses as courses_repo


async def read_intro_selection_lock(
    *,
    user_id: str,
) -> dict[str, Any]:
    progress_rows = await courses_repo.list_intro_selection_progress_rows(user_id=user_id)

    for row in progress_rows:
        current_unlock_position = int(row.get("current_unlock_position") or 0)
        max_lesson_position = int(row.get("max_lesson_position") or 0)
        if current_unlock_position < max_lesson_position:
            return {
                "selection_locked": True,
                "selection_lock_reason": "incomplete_drip",
            }

    for row in progress_rows:
        completed_lesson_count = int(row.get("completed_lesson_count") or 0)
        lesson_count = int(row.get("lesson_count") or 0)
        if completed_lesson_count < lesson_count:
            return {
                "selection_locked": True,
                "selection_lock_reason": "incomplete_lesson_completion",
            }

    return {
        "selection_locked": False,
        "selection_lock_reason": None,
    }


__all__ = ["read_intro_selection_lock"]
