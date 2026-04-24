from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

import pytest

from app import db
from app.repositories import lesson_completions


pytestmark = pytest.mark.anyio("asyncio")


async def _ensure_pool_open() -> None:
    if db.pool.closed:  # type: ignore[attr-defined]
        await db.pool.open(wait=True)  # type: ignore[attr-defined]


async def _insert_auth_user_and_subject(
    *,
    user_id: str,
    email: str,
    role: str,
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO auth.users (
                    id,
                    email,
                    encrypted_password,
                    created_at,
                    updated_at
                )
                VALUES (%s::uuid, %s, 'test-hash', now(), now())
                """,
                (user_id, email.strip().lower()),
            )
            await cur.execute(
                """
                INSERT INTO app.auth_subjects (
                    user_id,
                    email,
                    role,
                    onboarding_state
                )
                VALUES (%s::uuid, %s, %s, 'completed')
                """,
                (user_id, email.strip().lower(), role),
            )
        await conn.commit()


async def _insert_course(
    *,
    course_id: str,
    teacher_id: str,
    slug: str,
    title: str,
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.courses (
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
                VALUES (
                    %s::uuid,
                    %s::uuid,
                    %s,
                    %s,
                    %s::uuid,
                    0,
                    'purchase',
                    'public',
                    true,
                    NULL,
                    false,
                    false,
                    NULL
                )
                """,
                (course_id, teacher_id, title, slug, str(uuid4())),
            )
        await conn.commit()


async def _insert_lesson(
    *,
    lesson_id: str,
    course_id: str,
    position: int,
    title: str,
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                INSERT INTO app.lessons (
                    id,
                    course_id,
                    lesson_title,
                    position
                )
                VALUES (%s::uuid, %s::uuid, %s, %s)
                """,
                (lesson_id, course_id, title, position),
            )
        await conn.commit()


async def _set_completed_at(
    *,
    user_id: str,
    lesson_id: str,
    completed_at: str,
) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.lesson_completions
                   SET completed_at = %s::timestamptz
                 WHERE user_id = %s::uuid
                   AND lesson_id = %s::uuid
                """,
                (completed_at, user_id, lesson_id),
            )
        await conn.commit()


@pytest.fixture
async def seeded_completion_graph():
    user_id = str(uuid4())
    teacher_id = str(uuid4())
    course_id = str(uuid4())
    other_course_id = str(uuid4())
    lesson_one_id = str(uuid4())
    lesson_two_id = str(uuid4())

    await _insert_auth_user_and_subject(
        user_id=user_id,
        email=f"lesson_completion_user_{uuid4().hex[:8]}@example.com",
        role="learner",
    )
    await _insert_auth_user_and_subject(
        user_id=teacher_id,
        email=f"lesson_completion_teacher_{uuid4().hex[:8]}@example.com",
        role="teacher",
    )
    await _insert_course(
        course_id=course_id,
        teacher_id=teacher_id,
        slug=f"lesson-completion-{uuid4().hex[:8]}",
        title="Lesson Completion Course",
    )
    await _insert_course(
        course_id=other_course_id,
        teacher_id=teacher_id,
        slug=f"lesson-completion-other-{uuid4().hex[:8]}",
        title="Lesson Completion Other Course",
    )
    await _insert_lesson(
        lesson_id=lesson_one_id,
        course_id=course_id,
        position=1,
        title="Lesson One",
    )
    await _insert_lesson(
        lesson_id=lesson_two_id,
        course_id=course_id,
        position=2,
        title="Lesson Two",
    )

    try:
        yield {
            "user_id": user_id,
            "teacher_id": teacher_id,
            "course_id": course_id,
            "other_course_id": other_course_id,
            "lesson_one_id": lesson_one_id,
            "lesson_two_id": lesson_two_id,
        }
    finally:
        await _ensure_pool_open()
        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    "DELETE FROM app.lesson_completions WHERE course_id IN (%s::uuid, %s::uuid)",
                    (course_id, other_course_id),
                )
                await cur.execute(
                    "DELETE FROM app.lessons WHERE course_id IN (%s::uuid, %s::uuid)",
                    (course_id, other_course_id),
                )
                await cur.execute(
                    "DELETE FROM app.courses WHERE id IN (%s::uuid, %s::uuid)",
                    (course_id, other_course_id),
                )
                await cur.execute(
                    "DELETE FROM app.auth_subjects WHERE user_id = %s::uuid",
                    (user_id,),
                )
                await cur.execute(
                    "DELETE FROM app.auth_subjects WHERE user_id = %s::uuid",
                    (teacher_id,),
                )
                await cur.execute(
                    "DELETE FROM auth.users WHERE id = %s::uuid",
                    (user_id,),
                )
                await cur.execute(
                    "DELETE FROM auth.users WHERE id = %s::uuid",
                    (teacher_id,),
                )
            await conn.commit()


async def test_lesson_completion_repository_persists_and_reads_rows(
    seeded_completion_graph,
) -> None:
    created = await lesson_completions.create_lesson_completion(
        user_id=seeded_completion_graph["user_id"],
        course_id=seeded_completion_graph["course_id"],
        lesson_id=seeded_completion_graph["lesson_one_id"],
        completion_source="manual",
    )

    assert isinstance(created["id"], UUID)
    assert str(created["user_id"]) == seeded_completion_graph["user_id"]
    assert str(created["course_id"]) == seeded_completion_graph["course_id"]
    assert str(created["lesson_id"]) == seeded_completion_graph["lesson_one_id"]
    assert isinstance(created["completed_at"], datetime)
    assert created["completed_at"].tzinfo is not None
    assert created["completion_source"] == "manual"

    fetched = await lesson_completions.get_lesson_completion(
        user_id=seeded_completion_graph["user_id"],
        lesson_id=seeded_completion_graph["lesson_one_id"],
    )

    assert fetched == created

    second = await lesson_completions.create_lesson_completion(
        user_id=seeded_completion_graph["user_id"],
        course_id=seeded_completion_graph["course_id"],
        lesson_id=seeded_completion_graph["lesson_two_id"],
        completion_source="manual",
    )

    await _set_completed_at(
        user_id=seeded_completion_graph["user_id"],
        lesson_id=seeded_completion_graph["lesson_one_id"],
        completed_at="2026-01-01T00:00:00+00:00",
    )
    await _set_completed_at(
        user_id=seeded_completion_graph["user_id"],
        lesson_id=seeded_completion_graph["lesson_two_id"],
        completed_at="2026-01-02T00:00:00+00:00",
    )

    listed = await lesson_completions.list_course_lesson_completions(
        user_id=seeded_completion_graph["user_id"],
        course_id=seeded_completion_graph["course_id"],
    )

    assert [str(row["lesson_id"]) for row in listed] == [
        seeded_completion_graph["lesson_one_id"],
        seeded_completion_graph["lesson_two_id"],
    ]
    assert listed[0]["completion_source"] == "manual"
    assert listed[1]["completion_source"] == "manual"
    assert str(second["lesson_id"]) == seeded_completion_graph["lesson_two_id"]


async def test_lesson_completion_repository_duplicate_raises_and_row_count_remains_one(
    seeded_completion_graph,
) -> None:
    await lesson_completions.create_lesson_completion(
        user_id=seeded_completion_graph["user_id"],
        course_id=seeded_completion_graph["course_id"],
        lesson_id=seeded_completion_graph["lesson_one_id"],
        completion_source="manual",
    )

    with pytest.raises(lesson_completions.LessonCompletionAlreadyExistsError):
        await lesson_completions.create_lesson_completion(
            user_id=seeded_completion_graph["user_id"],
            course_id=seeded_completion_graph["course_id"],
            lesson_id=seeded_completion_graph["lesson_one_id"],
            completion_source="manual",
        )

    listed = await lesson_completions.list_course_lesson_completions(
        user_id=seeded_completion_graph["user_id"],
        course_id=seeded_completion_graph["course_id"],
    )

    assert len(listed) == 1
    assert str(listed[0]["lesson_id"]) == seeded_completion_graph["lesson_one_id"]


async def test_lesson_completion_repository_unknown_user_raises(
    seeded_completion_graph,
) -> None:
    with pytest.raises(lesson_completions.LessonCompletionUnknownUserError):
        await lesson_completions.create_lesson_completion(
            user_id=str(uuid4()),
            course_id=seeded_completion_graph["course_id"],
            lesson_id=seeded_completion_graph["lesson_one_id"],
            completion_source="manual",
        )


async def test_lesson_completion_repository_invalid_lesson_course_pair_raises(
    seeded_completion_graph,
) -> None:
    with pytest.raises(lesson_completions.LessonCompletionInvalidLessonCourseError):
        await lesson_completions.create_lesson_completion(
            user_id=seeded_completion_graph["user_id"],
            course_id=seeded_completion_graph["other_course_id"],
            lesson_id=seeded_completion_graph["lesson_one_id"],
            completion_source="manual",
        )


async def test_lesson_completion_repository_invalid_source_raises(
    seeded_completion_graph,
) -> None:
    with pytest.raises(lesson_completions.LessonCompletionInvalidSourceError):
        await lesson_completions.create_lesson_completion(
            user_id=seeded_completion_graph["user_id"],
            course_id=seeded_completion_graph["course_id"],
            lesson_id=seeded_completion_graph["lesson_one_id"],
            completion_source="not_a_valid_source",
        )
