from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from .. import schemas
from ..repositories import courses as courses_repo
from . import courses_service

_HOME_ENTRY_MAX_ONGOING_COURSES = 2
_HOME_ENTRY_CONTINUE_LABEL = "Forts\u00e4tt"


def _int_value(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _progress_percent(*, completed: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return completed / total


def _cover_media_payload(
    *,
    cover_media_id: str | None,
    cover: Mapping[str, Any] | None,
) -> schemas.HomeEntryCoverMedia:
    if cover is not None:
        media_id = str(cover.get("media_id") or cover_media_id or "").strip() or None
        state = str(cover.get("state") or "").strip().lower()
        resolved_url = str(cover.get("resolved_url") or "").strip() or None
        if media_id and state == "ready" and resolved_url:
            return schemas.HomeEntryCoverMedia(
                media_id=media_id,
                state="ready",
                resolved_url=resolved_url,
            )

    normalized_media_id = str(cover_media_id or "").strip() or None
    return schemas.HomeEntryCoverMedia(
        media_id=normalized_media_id,
        state="unavailable" if normalized_media_id else "missing",
        resolved_url=None,
    )


async def _resolve_cover_media(row: Mapping[str, Any]) -> schemas.HomeEntryCoverMedia:
    course_id = str(row.get("course_id") or "").strip()
    cover_media_id = str(row.get("cover_media_id") or "").strip() or None
    cover = await courses_service.resolve_course_cover(
        course_id=course_id,
        cover_media_id=cover_media_id,
    )
    return _cover_media_payload(cover_media_id=cover_media_id, cover=cover)


async def _ongoing_course_payload(
    row: Mapping[str, Any],
) -> schemas.HomeEntryOngoingCourse:
    completed_lesson_count = _int_value(row.get("completed_lesson_count"))
    total_lesson_count = _int_value(row.get("total_lesson_count"))
    available_lesson_count = _int_value(row.get("available_lesson_count"))
    next_lesson_id = str(row.get("next_lesson_id") or "").strip()

    return schemas.HomeEntryOngoingCourse(
        course_id=row["course_id"],
        slug=str(row["slug"]),
        title=str(row["title"]),
        cover_media=await _resolve_cover_media(row),
        progress=schemas.HomeEntryProgress(
            state="in_progress" if completed_lesson_count > 0 else "not_started",
            completed_lesson_count=completed_lesson_count,
            total_lesson_count=total_lesson_count,
            available_lesson_count=available_lesson_count,
            percent=_progress_percent(
                completed=completed_lesson_count,
                total=total_lesson_count,
            ),
            last_activity_at=row.get("last_activity_at"),
        ),
        next_lesson=schemas.HomeEntryNextLesson(
            id=next_lesson_id,
            lesson_title=str(row["next_lesson_title"]),
            position=_int_value(row.get("next_lesson_position")),
        ),
        cta=schemas.HomeEntryCTA(
            type="continue",
            label=_HOME_ENTRY_CONTINUE_LABEL,
            enabled=True,
            action=schemas.HomeEntryCTAAction(
                type="lesson",
                lesson_id=next_lesson_id,
            ),
            reason_code=None,
            reason_text=None,
        ),
        status=schemas.HomeEntryStatus(
            eligibility="ongoing",
            reason_code=None,
        ),
    )


async def read_home_entry_view(user_id: str) -> schemas.HomeEntryViewResponse:
    rows: Sequence[Mapping[str, Any]] = await courses_repo.list_home_entry_ongoing_course_rows(
        user_id=str(user_id),
        limit=_HOME_ENTRY_MAX_ONGOING_COURSES,
    )
    ongoing_courses = [
        await _ongoing_course_payload(row)
        for row in list(rows)[:_HOME_ENTRY_MAX_ONGOING_COURSES]
    ]
    return schemas.HomeEntryViewResponse(ongoing_courses=ongoing_courses)
