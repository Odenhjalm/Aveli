from __future__ import annotations

from typing import Any, Mapping, Sequence

from ..repositories import courses as courses_repo


def _is_admin_profile(profile: Mapping[str, Any] | None) -> bool:
    if not profile:
        return False
    if profile.get("is_admin"):
        return True
    role = str(profile.get("role_v2") or "").strip().lower()
    return role == "admin"


def _source_matches_course_step(*, course_step: str, enrollment_source: str) -> bool:
    normalized_step = str(course_step or "").strip().lower()
    normalized_source = str(enrollment_source or "").strip().lower()
    if normalized_step == "intro":
        return normalized_source == "intro_enrollment"
    return normalized_source == "purchase"


async def fetch_course(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> dict[str, Any] | None:
    row = await courses_repo.get_course(course_id=course_id, slug=slug)
    return dict(row) if row else None


async def fetch_course_access_subject(course_id: str) -> dict[str, Any] | None:
    return await fetch_course(course_id=course_id)


async def list_courses(
    *,
    limit: int | None = None,
    search: str | None = None,
) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_courses(limit=limit, search=search))


async def list_public_courses(
    *,
    published_only: bool = True,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[dict[str, Any]]:
    del published_only
    return list(await courses_repo.list_public_courses(search=search, limit=limit))


async def list_my_courses(user_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_my_courses(str(user_id)))


async def list_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_course_lessons(course_id))


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_lesson(lesson_id)
    return dict(row) if row else None


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    return await courses_repo.get_lesson_course_ids(lesson_id)


async def list_lesson_media(
    lesson_id: str,
    *,
    mode: str | None = None,
) -> Sequence[dict[str, Any]]:
    del mode
    return list(await courses_repo.list_lesson_media(lesson_id))


async def is_course_owner(course_id: str, user_id: str) -> bool:
    del course_id, user_id
    return False


async def is_course_teacher_or_instructor(course_id: str, user_id: str) -> bool:
    del course_id, user_id
    return False


async def is_user_enrolled(user_id: str, course_id: str) -> bool:
    return await courses_repo.is_enrolled(str(user_id), str(course_id))


async def get_course_enrollment(user_id: str, course_id: str) -> dict[str, Any] | None:
    return await courses_repo.get_course_enrollment(str(user_id), str(course_id))


async def can_user_read_course(user_id: str, course: Mapping[str, Any]) -> bool:
    course_id = str(course.get("id") or "").strip()
    if not course_id:
        return False
    enrollment = await get_course_enrollment(user_id, course_id)
    if not enrollment:
        return False
    return _source_matches_course_step(
        course_step=str(course.get("step") or ""),
        enrollment_source=str(enrollment.get("source") or ""),
    )


async def can_user_read_lesson(user_id: str, lesson: Mapping[str, Any]) -> bool:
    course_id = str(lesson.get("course_id") or "").strip()
    if not course_id:
        return False
    enrollment = await get_course_enrollment(user_id, course_id)
    if not enrollment:
        return False
    if not _source_matches_course_step(
        course_step=str((await fetch_course(course_id=course_id) or {}).get("step") or ""),
        enrollment_source=str(enrollment.get("source") or ""),
    ):
        return False
    lesson_position = int(lesson.get("position") or 0)
    current_unlock_position = int(enrollment.get("current_unlock_position") or 0)
    return lesson_position > 0 and lesson_position <= current_unlock_position


async def course_enrollment_snapshot(user_id: str, course_id: str) -> dict[str, Any]:
    course = await fetch_course(course_id=course_id)
    enrollment = await get_course_enrollment(user_id, course_id)
    can_access = False
    if course and enrollment:
        can_access = _source_matches_course_step(
            course_step=str(course.get("step") or ""),
            enrollment_source=str(enrollment.get("source") or ""),
        )
    return {
        "can_access": can_access,
        "enrollment": enrollment,
    }
