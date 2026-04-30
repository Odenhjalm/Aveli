from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

import pytest

from app import auth, db, schemas
from app.main import app
from app.repositories import courses as courses_repo
from app.routes import home as home_routes

pytestmark = pytest.mark.anyio("asyncio")


@pytest.fixture(autouse=True)
def _clear_dependency_overrides():
    yield
    app.dependency_overrides.clear()


async def _override_app_entry(user_id: str) -> None:
    async def _fake_require_app_entry() -> dict[str, object]:
        return {
            "id": user_id,
            "email": f"{user_id}@example.com",
            "onboarding_state": "completed",
            "role": "learner",
        }

    app.dependency_overrides[auth.require_app_entry] = _fake_require_app_entry


async def _ensure_pool_open() -> None:
    if db.pool.closed:  # type: ignore[attr-defined]
        await db.pool.open(wait=True)  # type: ignore[attr-defined]


async def _insert_auth_subject(
    *,
    user_id: str,
    email: str,
    role: str = "learner",
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into auth.users (
                    id,
                    email,
                    encrypted_password,
                    created_at,
                    updated_at
                )
                values (%s::uuid, %s, 'test-hash', now(), now())
                """,
                (user_id, email.strip().lower()),
            )
            await cur.execute(
                """
                insert into app.auth_subjects (
                    user_id,
                    email,
                    role,
                    onboarding_state
                )
                values (%s::uuid, %s, %s, 'completed')
                """,
                (user_id, email.strip().lower(), role),
            )
        await conn.commit()


async def _insert_course(
    *,
    teacher_id: str,
    title: str,
    group_position: int = 0,
    required_enrollment_source: str = "purchase",
) -> dict[str, str]:
    course_id = str(uuid4())
    slug = f"home-entry-{uuid4().hex[:8]}"
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.courses (
                    id,
                    teacher_id,
                    title,
                    slug,
                    course_group_id,
                    group_position,
                    required_enrollment_source,
                    visibility,
                    content_ready,
                    price_amount_cents,
                    sellable,
                    drip_enabled,
                    drip_interval_days
                )
                values (
                    %s::uuid,
                    %s::uuid,
                    %s,
                    %s,
                    %s::uuid,
                    %s,
                    %s::app.course_enrollment_source,
                    'public',
                    true,
                    null,
                    false,
                    false,
                    null
                )
                """,
                (
                    course_id,
                    teacher_id,
                    title,
                    slug,
                    str(uuid4()),
                    group_position,
                    required_enrollment_source,
                ),
            )
        await conn.commit()
    return {"id": course_id, "slug": slug, "title": title}


async def _insert_lessons(course_id: str, *, count: int) -> list[str]:
    lesson_ids = [str(uuid4()) for _ in range(count)]
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for index, lesson_id in enumerate(lesson_ids, start=1):
                await cur.execute(
                    """
                    insert into app.lessons (
                        id,
                        course_id,
                        lesson_title,
                        position
                    )
                    values (%s::uuid, %s::uuid, %s, %s)
                    """,
                    (lesson_id, course_id, f"Lesson {index}", index),
                )
        await conn.commit()
    return lesson_ids


async def _insert_enrollment(
    *,
    user_id: str,
    course_id: str,
    source: str = "purchase",
    granted_at: datetime,
    current_unlock_position: int,
) -> str:
    enrollment_id = str(uuid4())
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        try:
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "select set_config('app.canonical_enrollment_function_context', 'on', true)"
                )
                await cur.execute(
                    """
                    insert into app.course_enrollments (
                        id,
                        user_id,
                        course_id,
                        source,
                        granted_at,
                        drip_started_at,
                        current_unlock_position
                    )
                    values (
                        %s::uuid,
                        %s::uuid,
                        %s::uuid,
                        %s::app.course_enrollment_source,
                        %s::timestamptz,
                        %s::timestamptz,
                        %s
                    )
                    """,
                    (
                        enrollment_id,
                        user_id,
                        course_id,
                        source,
                        granted_at,
                        granted_at,
                        current_unlock_position,
                    ),
                )
                await cur.execute(
                    "select set_config('app.canonical_enrollment_function_context', 'off', true)"
                )
            await conn.commit()
        except Exception:
            await conn.rollback()
            raise
    return enrollment_id


async def _insert_completion(
    *,
    user_id: str,
    course_id: str,
    lesson_id: str,
    completed_at: datetime,
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lesson_completions (
                    user_id,
                    course_id,
                    lesson_id,
                    completed_at,
                    completion_source
                )
                values (
                    %s::uuid,
                    %s::uuid,
                    %s::uuid,
                    %s::timestamptz,
                    'manual'
                )
                """,
                (user_id, course_id, lesson_id, completed_at),
            )
        await conn.commit()


async def _cleanup_graph(*, user_ids: list[str], course_ids: list[str]) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for course_id in course_ids:
                await cur.execute(
                    "delete from app.lesson_completions where course_id = %s::uuid",
                    (course_id,),
                )
                await cur.execute(
                    "delete from app.course_enrollments where course_id = %s::uuid",
                    (course_id,),
                )
                await cur.execute(
                    "delete from app.lessons where course_id = %s::uuid",
                    (course_id,),
                )
                await cur.execute(
                    "delete from app.courses where id = %s::uuid",
                    (course_id,),
                )
            for user_id in user_ids:
                await cur.execute(
                    "delete from app.auth_subjects where user_id = %s::uuid",
                    (user_id,),
                )
                await cur.execute(
                    "delete from auth.users where id = %s::uuid",
                    (user_id,),
                )
        await conn.commit()


def _assert_home_entry_course_shape(item: dict[str, object]) -> None:
    assert set(item) == {
        "course_id",
        "slug",
        "title",
        "cover_media",
        "progress",
        "next_lesson",
        "cta",
        "status",
    }
    assert set(item["cover_media"]) == {"media_id", "state", "resolved_url"}
    assert set(item["progress"]) == {
        "state",
        "completed_lesson_count",
        "total_lesson_count",
        "available_lesson_count",
        "percent",
        "last_activity_at",
    }
    assert set(item["next_lesson"]) == {"id", "lesson_title", "position"}
    assert set(item["cta"]) == {
        "type",
        "label",
        "enabled",
        "action",
        "reason_code",
        "reason_text",
    }
    assert set(item["cta"]["action"]) == {"type", "lesson_id"}
    assert set(item["status"]) == {"eligibility", "reason_code"}
    assert "storage_path" not in str(item)
    assert "signed_url" not in str(item)


async def test_home_entry_view_requires_auth(async_client, monkeypatch) -> None:
    async def _fail_read_home_entry_view(user_id: str):
        del user_id
        raise AssertionError("service must not run without app-entry auth")

    monkeypatch.setattr(
        home_routes.home_entry_view_service,
        "read_home_entry_view",
        _fail_read_home_entry_view,
        raising=True,
    )

    response = await async_client.get("/home/entry-view")

    assert response.status_code == 401


async def test_home_entry_view_route_returns_empty_state(async_client) -> None:
    user_id = str(uuid4())
    await _override_app_entry(user_id)

    response = await async_client.get("/home/entry-view")

    assert response.status_code == 200, response.text
    assert response.json() == {"ongoing_courses": []}


async def test_home_entry_view_route_calls_home_entry_service_only(
    async_client,
    monkeypatch,
) -> None:
    user_id = str(uuid4())
    await _override_app_entry(user_id)
    calls: list[str] = []

    async def _fake_read_home_entry_view(candidate_user_id: str):
        calls.append(candidate_user_id)
        return schemas.HomeEntryViewResponse(ongoing_courses=[])

    monkeypatch.setattr(
        home_routes.home_entry_view_service,
        "read_home_entry_view",
        _fake_read_home_entry_view,
        raising=True,
    )

    response = await async_client.get("/home/entry-view")

    assert response.status_code == 200, response.text
    assert response.json() == {"ongoing_courses": []}
    assert calls == [user_id]


async def test_home_entry_read_model_excludes_source_mismatch() -> None:
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_ids: list[str] = []
    try:
        await _insert_auth_subject(
            user_id=user_id,
            email=f"home_entry_user_{uuid4().hex[:8]}@example.com",
        )
        await _insert_auth_subject(
            user_id=teacher_id,
            email=f"home_entry_teacher_{uuid4().hex[:8]}@example.com",
            role="teacher",
        )
        course = await _insert_course(teacher_id=teacher_id, title="Mismatch")
        course_ids.append(course["id"])
        await _insert_lessons(course["id"], count=2)
        await _insert_enrollment(
            user_id=user_id,
            course_id=course["id"],
            source="intro",
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=2,
        )

        rows = await courses_repo.list_home_entry_ongoing_course_rows(
            user_id=user_id,
        )

        assert rows == []
    finally:
        await _cleanup_graph(user_ids=[user_id, teacher_id], course_ids=course_ids)


async def test_home_entry_view_selects_first_unlocked_incomplete_lesson(
    async_client,
) -> None:
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_ids: list[str] = []
    try:
        await _insert_auth_subject(
            user_id=user_id,
            email=f"home_entry_next_{uuid4().hex[:8]}@example.com",
        )
        await _insert_auth_subject(
            user_id=teacher_id,
            email=f"home_entry_next_teacher_{uuid4().hex[:8]}@example.com",
            role="teacher",
        )
        course = await _insert_course(teacher_id=teacher_id, title="Completion Aware")
        course_ids.append(course["id"])
        lessons = await _insert_lessons(course["id"], count=3)
        await _insert_enrollment(
            user_id=user_id,
            course_id=course["id"],
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=3,
        )
        await _insert_completion(
            user_id=user_id,
            course_id=course["id"],
            lesson_id=lessons[0],
            completed_at=datetime(2026, 1, 2, tzinfo=timezone.utc),
        )
        await _insert_completion(
            user_id=user_id,
            course_id=course["id"],
            lesson_id=lessons[2],
            completed_at=datetime(2026, 1, 3, tzinfo=timezone.utc),
        )
        await _override_app_entry(user_id)

        response = await async_client.get("/home/entry-view")

        assert response.status_code == 200, response.text
        payload = response.json()
        assert len(payload["ongoing_courses"]) == 1
        item = payload["ongoing_courses"][0]
        _assert_home_entry_course_shape(item)
        assert item["course_id"] == course["id"]
        assert item["progress"]["state"] == "in_progress"
        assert item["progress"]["completed_lesson_count"] == 2
        assert item["progress"]["total_lesson_count"] == 3
        assert item["progress"]["available_lesson_count"] == 3
        assert item["progress"]["percent"] == pytest.approx(2 / 3)
        assert item["next_lesson"]["id"] == lessons[1]
        assert item["next_lesson"]["position"] == 2
        assert item["cta"] == {
            "type": "continue",
            "label": "Forts\u00e4tt",
            "enabled": True,
            "action": {"type": "lesson", "lesson_id": lessons[1]},
            "reason_code": None,
            "reason_text": None,
        }
        assert item["status"] == {"eligibility": "ongoing", "reason_code": None}
    finally:
        await _cleanup_graph(user_ids=[user_id, teacher_id], course_ids=course_ids)


async def test_home_entry_read_model_excludes_fully_completed_course() -> None:
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_ids: list[str] = []
    try:
        await _insert_auth_subject(
            user_id=user_id,
            email=f"home_entry_complete_{uuid4().hex[:8]}@example.com",
        )
        await _insert_auth_subject(
            user_id=teacher_id,
            email=f"home_entry_complete_teacher_{uuid4().hex[:8]}@example.com",
            role="teacher",
        )
        course = await _insert_course(teacher_id=teacher_id, title="Complete")
        course_ids.append(course["id"])
        lessons = await _insert_lessons(course["id"], count=2)
        await _insert_enrollment(
            user_id=user_id,
            course_id=course["id"],
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=2,
        )
        for index, lesson_id in enumerate(lessons, start=1):
            await _insert_completion(
                user_id=user_id,
                course_id=course["id"],
                lesson_id=lesson_id,
                completed_at=datetime(2026, 1, index, tzinfo=timezone.utc),
            )

        rows = await courses_repo.list_home_entry_ongoing_course_rows(
            user_id=user_id,
        )

        assert rows == []
    finally:
        await _cleanup_graph(user_ids=[user_id, teacher_id], course_ids=course_ids)


async def test_home_entry_read_model_excludes_locked_only_course() -> None:
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_ids: list[str] = []
    try:
        await _insert_auth_subject(
            user_id=user_id,
            email=f"home_entry_locked_{uuid4().hex[:8]}@example.com",
        )
        await _insert_auth_subject(
            user_id=teacher_id,
            email=f"home_entry_locked_teacher_{uuid4().hex[:8]}@example.com",
            role="teacher",
        )
        course = await _insert_course(teacher_id=teacher_id, title="Locked")
        course_ids.append(course["id"])
        await _insert_lessons(course["id"], count=2)
        await _insert_enrollment(
            user_id=user_id,
            course_id=course["id"],
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=0,
        )

        rows = await courses_repo.list_home_entry_ongoing_course_rows(
            user_id=user_id,
        )

        assert rows == []
    finally:
        await _cleanup_graph(user_ids=[user_id, teacher_id], course_ids=course_ids)


async def test_home_entry_read_model_ranks_deterministically_and_limits_to_two() -> None:
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_ids: list[str] = []
    try:
        await _insert_auth_subject(
            user_id=user_id,
            email=f"home_entry_rank_{uuid4().hex[:8]}@example.com",
        )
        await _insert_auth_subject(
            user_id=teacher_id,
            email=f"home_entry_rank_teacher_{uuid4().hex[:8]}@example.com",
            role="teacher",
        )
        first = await _insert_course(teacher_id=teacher_id, title="Rank First")
        second = await _insert_course(teacher_id=teacher_id, title="Rank Second")
        third = await _insert_course(teacher_id=teacher_id, title="Rank Third")
        course_ids.extend([first["id"], second["id"], third["id"]])
        first_lessons = await _insert_lessons(first["id"], count=2)
        second_lessons = await _insert_lessons(second["id"], count=2)
        third_lessons = await _insert_lessons(third["id"], count=2)
        await _insert_enrollment(
            user_id=user_id,
            course_id=first["id"],
            granted_at=datetime(2026, 1, 5, tzinfo=timezone.utc),
            current_unlock_position=2,
        )
        await _insert_enrollment(
            user_id=user_id,
            course_id=second["id"],
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=2,
        )
        await _insert_enrollment(
            user_id=user_id,
            course_id=third["id"],
            granted_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            current_unlock_position=2,
        )
        await _insert_completion(
            user_id=user_id,
            course_id=second["id"],
            lesson_id=second_lessons[0],
            completed_at=datetime(2026, 1, 4, tzinfo=timezone.utc),
        )
        await _insert_completion(
            user_id=user_id,
            course_id=third["id"],
            lesson_id=third_lessons[0],
            completed_at=datetime(2026, 1, 3, tzinfo=timezone.utc),
        )

        rows = await courses_repo.list_home_entry_ongoing_course_rows(
            user_id=user_id,
            limit=2,
        )

        assert [row["course_id"] for row in rows] == [first["id"], second["id"]]
        assert [row["next_lesson_id"] for row in rows] == [
            first_lessons[0],
            second_lessons[1],
        ]
        assert len(rows) == 2
    finally:
        await _cleanup_graph(user_ids=[user_id, teacher_id], course_ids=course_ids)


def test_home_entry_view_service_does_not_use_forbidden_course_helpers() -> None:
    source = Path("backend/app/services/home_entry_view_service.py").read_text(
        encoding="utf-8"
    )

    assert "_course_entry_next_recommended_raw" not in source
    assert "_course_entry_lesson_projections" not in source
    assert "list_my_courses" not in source
    assert "frontend" not in source.lower()


def test_home_entry_schemas_forbid_extra_frontend_fields() -> None:
    with pytest.raises(ValueError):
        schemas.HomeEntryViewResponse(
            ongoing_courses=[],
            frontend_fallback=True,
        )

    with pytest.raises(ValueError):
        schemas.HomeEntryCTA(
            type="continue",
            label="Forts\u00e4tt",
            enabled=True,
            action={"type": "lesson", "lesson_id": str(uuid4())},
            navigation_fallback="/courses/example",
        )

    with pytest.raises(ValueError):
        schemas.HomeEntryOngoingCourse(
            course_id=str(uuid4()),
            slug="example",
            title="Example",
            cover_media={"media_id": None, "state": "missing", "resolved_url": None},
            progress={
                "state": "not_started",
                "completed_lesson_count": 0,
                "total_lesson_count": 2,
                "available_lesson_count": 1,
                "percent": 0.0,
                "last_activity_at": None,
            },
            next_lesson={
                "id": str(uuid4()),
                "lesson_title": "Lesson 1",
                "position": 1,
            },
            cta={
                "type": "continue",
                "label": "Forts\u00e4tt",
                "enabled": True,
                "action": {"type": "lesson", "lesson_id": str(uuid4())},
                "reason_code": None,
                "reason_text": None,
            },
            status={"eligibility": "ongoing", "reason_code": None},
        )
