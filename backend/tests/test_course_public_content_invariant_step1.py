from __future__ import annotations

from pathlib import Path
from uuid import uuid4

import pytest

from app import db
from app.repositories import courses as courses_repo


pytestmark = pytest.mark.anyio("asyncio")


async def _ensure_pool_open() -> None:
    if db.pool.closed:  # type: ignore[attr-defined]
        await db.pool.open(wait=True)  # type: ignore[attr-defined]


async def _ensure_teacher(teacher_id: str) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.auth_subjects (user_id, email, onboarding_state, role)
                values (%s::uuid, %s, 'completed', 'teacher')
                on conflict (user_id) do update
                  set email = excluded.email,
                      onboarding_state = excluded.onboarding_state,
                      role = excluded.role
                """,
                (teacher_id, f"{teacher_id}@example.test"),
            )
            await conn.commit()


async def _cleanup_teacher_scope(teacher_id: str) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.courses where teacher_id = %s::uuid",
                (teacher_id,),
            )
            await cur.execute(
                "delete from app.course_families where teacher_id = %s::uuid",
                (teacher_id,),
            )
            await cur.execute(
                "delete from app.auth_subjects where user_id = %s::uuid",
                (teacher_id,),
            )
            await conn.commit()


async def _create_course(teacher_id: str, *, title: str) -> dict[str, object]:
    family = await courses_repo.create_course_family(
        teacher_id=teacher_id,
        name=f"Family {uuid4().hex[:8]}",
    )
    return await courses_repo.create_course(
        {
            "teacher_id": teacher_id,
            "title": title,
            "slug": f"course-{uuid4().hex[:12]}",
            "course_group_id": str(family["id"]),
            "required_enrollment_source": None,
            "price_amount_cents": None,
            "drip_enabled": False,
            "drip_interval_days": None,
        }
    )


async def _public_content_row(course_id: str) -> tuple[str, str] | None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select description, short_description
                from app.course_public_content
                where course_id = %s::uuid
                """,
                (course_id,),
            )
            row = await cur.fetchone()
    if row is None:
        return None
    return str(row[0]), str(row[1])


async def _set_public_content_delete_guard_enabled(enabled: bool) -> None:
    action = "enable" if enabled else "disable"
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                f"""
                do $$
                begin
                  if exists (
                    select 1
                    from pg_trigger tg
                    join pg_class cls on cls.oid = tg.tgrelid
                    join pg_namespace n on n.oid = cls.relnamespace
                    where n.nspname = 'app'
                      and cls.relname = 'course_public_content'
                      and tg.tgname = 'course_public_content_parented_delete_guard'
                  ) then
                    alter table app.course_public_content {action} trigger
                      course_public_content_parented_delete_guard;
                  end if;
                end $$;
                """
            )
            await conn.commit()


async def _delete_public_content_row(course_id: str) -> None:
    await _set_public_content_delete_guard_enabled(False)
    try:
        async with db.pool.connection() as conn:  # type: ignore[attr-defined]
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    """
                    delete from app.course_public_content
                    where course_id = %s::uuid
                    """,
                    (course_id,),
                )
                await conn.commit()
    finally:
        await _set_public_content_delete_guard_enabled(True)


def test_repository_has_no_global_public_content_invariant_scan() -> None:
    source = Path("backend/app/repositories/courses.py").read_text(encoding="utf-8")

    assert "_assert_course_public_content_invariant" not in source
    assert (
        "where not exists (\n            select 1\n"
        "            from app.course_public_content"
        not in source
    )


async def test_create_course_creates_course_public_content_sibling_row() -> None:
    teacher_id = str(uuid4())
    await _ensure_teacher(teacher_id)
    try:
        course = await _create_course(teacher_id, title="Sibling Row Course")
        row = await _public_content_row(str(course["id"]))

        assert row == ("", "Pending public summary")
    finally:
        await _cleanup_teacher_scope(teacher_id)


async def test_missing_public_content_is_local_and_upsert_repairs_it() -> None:
    teacher_id = str(uuid4())
    await _ensure_teacher(teacher_id)
    try:
        healthy_course = await _create_course(teacher_id, title="Healthy Course")
        broken_course = await _create_course(teacher_id, title="Broken Course")
        healthy_course_id = str(healthy_course["id"])
        broken_course_id = str(broken_course["id"])

        await _delete_public_content_row(broken_course_id)

        healthy_content = await courses_repo.get_course_public_content(healthy_course_id)
        teacher_courses = await courses_repo.list_courses(teacher_id=teacher_id)

        assert str(healthy_content["course_id"]) == healthy_course_id
        assert healthy_content["description"] == ""
        assert healthy_course_id in {str(row["id"]) for row in teacher_courses}
        assert broken_course_id not in {str(row["id"]) for row in teacher_courses}

        with pytest.raises(courses_repo.CoursePublicContentInvariantError) as exc_info:
            await courses_repo.get_course_public_content(broken_course_id)
        assert exc_info.value.course_id == broken_course_id

        repaired = await courses_repo.upsert_course_public_content(
            broken_course_id,
            description="Repaired public description",
        )

        assert str(repaired["course_id"]) == broken_course_id
        assert repaired["description"] == "Repaired public description"
        assert await _public_content_row(broken_course_id) == (
            "Repaired public description",
            "Pending public summary",
        )
    finally:
        await _set_public_content_delete_guard_enabled(True)
        await _cleanup_teacher_scope(teacher_id)
