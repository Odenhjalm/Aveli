from __future__ import annotations

from typing import Any

from ..repositories import courses as courses_repo
from . import courses_service
from . import intro_selection_state


async def read_intro_selection_state(
    *,
    user_id: str,
) -> dict[str, Any]:
    lock_state = await intro_selection_state.read_intro_selection_lock(user_id=user_id)
    if bool(lock_state["selection_locked"]):
        return {
            "selection_locked": True,
            "selection_lock_reason": lock_state["selection_lock_reason"],
            "eligible_courses": [],
        }

    progress_rows = await courses_repo.list_intro_selection_progress_rows(user_id=user_id)
    enrolled_intro_course_ids = {
        str(row.get("course_id") or "")
        for row in progress_rows
        if str(row.get("course_id") or "").strip()
    }

    eligible_courses = [
        dict(row)
        for row in await courses_service.list_public_courses(
            search=None,
            limit=None,
            group_position=None,
        )
        if str(row.get("required_enrollment_source") or "").strip() == "intro"
        and str(row.get("id") or "").strip() not in enrolled_intro_course_ids
    ]

    return {
        "selection_locked": False,
        "selection_lock_reason": None,
        "eligible_courses": eligible_courses,
    }


__all__ = ["read_intro_selection_state"]
