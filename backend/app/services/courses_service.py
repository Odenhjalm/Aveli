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


def _course_expected_source(course: Mapping[str, Any] | None) -> str | None:
    if not course:
        return None
    normalized_step = str(course.get("step") or "").strip().lower()
    if normalized_step == "intro":
        return "intro_enrollment"
    if normalized_step in {"step1", "step2", "step3"}:
        return "purchase"
    return None


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
    teacher_id: str | None = None,
    limit: int | None = None,
    search: str | None = None,
) -> Sequence[dict[str, Any]]:
    del teacher_id
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


async def list_studio_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_studio_course_lessons(course_id))


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_lesson(lesson_id)
    return dict(row) if row else None


async def fetch_studio_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_studio_lesson(lesson_id)
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


async def attach_course_cover_read_contract(
    courses: dict[str, Any] | list[dict[str, Any]] | None,
) -> None:
    del courses


async def create_course(payload: dict[str, Any]) -> dict[str, Any]:
    row = await courses_repo.create_course(payload)
    return dict(row)


async def update_course(course_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
    row = await courses_repo.update_course(course_id, patch)
    return dict(row) if row else None


async def delete_course(course_id: str) -> bool:
    return await courses_repo.delete_course(course_id)


async def create_lesson(
    course_id: str,
    *,
    lesson_title: str,
    content_markdown: str,
    position: int,
    lesson_id: str | None = None,
) -> dict[str, Any]:
    row = await courses_repo.create_lesson(
        lesson_id=lesson_id,
        course_id=course_id,
        lesson_title=lesson_title,
        content_markdown=content_markdown,
        position=position,
    )
    return dict(row)


async def upsert_lesson(course_id: str, payload: dict[str, Any]) -> dict[str, Any] | None:
    existing_id = str(payload.get("id") or "").strip()
    lesson_id = existing_id or None
    if lesson_id is None:
        required_fields = {"lesson_title", "content_markdown", "position"}
        missing = sorted(field for field in required_fields if field not in payload)
        if missing:
            raise ValueError(f"missing lesson fields: {', '.join(missing)}")
        return await create_lesson(
            course_id,
            lesson_title=str(payload["lesson_title"]),
            content_markdown=str(payload["content_markdown"]),
            position=int(payload["position"]),
        )

    patch: dict[str, Any] = {}
    if "lesson_title" in payload:
        patch["lesson_title"] = payload["lesson_title"]
    if "content_markdown" in payload:
        patch["content_markdown"] = payload["content_markdown"]
    if "position" in payload:
        patch["position"] = payload["position"]
    row = await courses_repo.update_lesson(lesson_id, patch)
    return dict(row) if row else None


async def reorder_lessons(course_id: str, ordered_lesson_ids: Sequence[str]) -> None:
    return await courses_repo.reorder_lessons(course_id, ordered_lesson_ids)


async def delete_lesson(lesson_id: str) -> bool:
    return await courses_repo.delete_lesson(lesson_id)


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


def _canonical_course_state_payload(
    *,
    course: Mapping[str, Any],
    enrollment: Mapping[str, Any] | None,
    expected_source: str | None,
) -> dict[str, Any]:
    return {
        "course_id": str(course.get("id") or ""),
        "course_step": str(course.get("step") or ""),
        "required_enrollment_source": expected_source,
        "enrollment": dict(enrollment) if enrollment is not None else None,
    }


async def read_canonical_course_access(user_id: str, course_id: str) -> dict[str, Any]:
    course = await fetch_course(course_id=course_id)
    normalized_user_id = str(user_id or "").strip()
    enrollment = (
        await get_course_enrollment(normalized_user_id, course_id)
        if course is not None and normalized_user_id
        else None
    )
    expected_source = _course_expected_source(course)
    source_matches = (
        enrollment is not None
        and expected_source is not None
        and str(enrollment.get("source") or "").strip().lower() == expected_source
    )
    return {
        "course": course,
        "enrollment": enrollment,
        "expected_source": expected_source,
        "can_access": bool(source_matches),
    }


async def read_canonical_course_state(user_id: str, course_id: str) -> dict[str, Any] | None:
    access = await read_canonical_course_access(user_id, course_id)
    course = access["course"]
    if course is None:
        return None
    return _canonical_course_state_payload(
        course=course,
        enrollment=access["enrollment"],
        expected_source=access["expected_source"],
    )


async def read_canonical_lesson_access(user_id: str, lesson_id: str) -> dict[str, Any]:
    lesson = await fetch_lesson(lesson_id)
    if lesson is None:
        return {
            "lesson": None,
            "course": None,
            "enrollment": None,
            "expected_source": None,
            "current_unlock_position": 0,
            "can_access": False,
        }

    course_id = str(lesson.get("course_id") or "").strip()
    course_access = await read_canonical_course_access(user_id, course_id)
    enrollment = course_access["enrollment"]
    current_unlock_position = (
        int(enrollment.get("current_unlock_position") or 0)
        if enrollment is not None
        else 0
    )
    lesson_position = int(lesson.get("position") or 0)
    can_access = bool(
        course_access["can_access"]
        and lesson_position >= 1
        and lesson_position <= current_unlock_position
    )
    return {
        **course_access,
        "lesson": lesson,
        "current_unlock_position": current_unlock_position,
        "can_access": can_access,
    }


async def can_user_read_course(user_id: str, course: Mapping[str, Any]) -> bool:
    course_id = str(course.get("id") or "").strip()
    if not course_id:
        return False
    access = await read_canonical_course_access(user_id, course_id)
    return bool(access["can_access"])


async def can_user_read_lesson(user_id: str, lesson: Mapping[str, Any]) -> bool:
    lesson_id = str(lesson.get("id") or "").strip()
    if not lesson_id:
        return False
    access = await read_canonical_lesson_access(user_id, lesson_id)
    return bool(access["can_access"])


async def create_intro_course_enrollment(
    *,
    user_id: str,
    course_id: str,
) -> dict[str, Any]:
    course = await fetch_course(course_id=course_id)
    if course is None:
        raise LookupError("course not found")

    course_step = str(course.get("step") or "").strip().lower()
    if course_step != "intro":
        raise PermissionError("purchase enrollment required")

    enrollment = await courses_repo.create_course_enrollment(
        user_id=str(user_id),
        course_id=str(course_id),
        source="intro_enrollment",
    )
    return _canonical_course_state_payload(
        course=course,
        enrollment=enrollment,
        expected_source="intro_enrollment",
    )
