from __future__ import annotations

from typing import Any, NoReturn, cast

from fastapi import HTTPException, status

from ..repositories import courses as courses_repo
from ..types.course_row import CourseRow, LessonRow


def _normalize_identifier(value: Any) -> str:
    return str(value or "").strip()


def _raise_course_not_found() -> NoReturn:
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Course not found",
    )


def _raise_lesson_not_found() -> NoReturn:
    raise HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail="Lesson not found",
    )


def _raise_not_course_owner() -> NoReturn:
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Not course owner",
    )


async def _get_course_or_404(course_id: str) -> CourseRow:
    normalized_course_id = _normalize_identifier(course_id)
    if not normalized_course_id:
        _raise_course_not_found()

    course = await courses_repo.get_course(course_id=normalized_course_id)
    if course is None:
        _raise_course_not_found()
    return cast(CourseRow, dict(course))


async def _get_lesson_or_404(lesson_id: str) -> LessonRow:
    normalized_lesson_id = _normalize_identifier(lesson_id)
    if not normalized_lesson_id:
        _raise_lesson_not_found()

    lesson = await courses_repo.get_lesson_structure(normalized_lesson_id)
    if lesson is None:
        _raise_lesson_not_found()
    return cast(LessonRow, dict(lesson))


async def _enforce_teacher_owns_existing_course(
    *,
    teacher_id: str,
    course_id: str,
) -> None:
    normalized_teacher_id = _normalize_identifier(teacher_id)
    normalized_course_id = _normalize_identifier(course_id)
    if not normalized_teacher_id or not normalized_course_id:
        _raise_not_course_owner()

    if not await courses_repo.is_course_owner(normalized_course_id, normalized_teacher_id):
        _raise_not_course_owner()


async def get_course_for_teacher_or_404(
    course_id: str,
    teacher_id: str,
) -> CourseRow:
    course = await _get_course_or_404(course_id)
    await _enforce_teacher_owns_existing_course(
        teacher_id=teacher_id,
        course_id=str(course["id"]),
    )
    return course


async def resolve_course_from_lesson_or_404(lesson_id: str) -> str:
    normalized_lesson_id = _normalize_identifier(lesson_id)
    if not normalized_lesson_id:
        _raise_lesson_not_found()

    _, course_id = await courses_repo.get_lesson_course_ids(normalized_lesson_id)
    normalized_course_id = _normalize_identifier(course_id or "")
    if not normalized_course_id:
        _raise_lesson_not_found()
    await _get_course_or_404(normalized_course_id)
    return normalized_course_id


async def get_lesson_for_teacher_or_404(
    lesson_id: str,
    teacher_id: str,
) -> LessonRow:
    lesson = await _get_lesson_or_404(lesson_id)
    course_id = _normalize_identifier(str(lesson.get("course_id") or ""))
    if not course_id:
        _raise_lesson_not_found()

    await get_course_for_teacher_or_404(
        course_id=course_id,
        teacher_id=teacher_id,
    )
    return lesson


async def enforce_teacher_owns_course(
    teacher_id: str,
    course_id: str,
) -> None:
    await get_course_for_teacher_or_404(
        course_id=course_id,
        teacher_id=teacher_id,
    )


__all__ = [
    "enforce_teacher_owns_course",
    "get_course_for_teacher_or_404",
    "get_lesson_for_teacher_or_404",
    "resolve_course_from_lesson_or_404",
]
