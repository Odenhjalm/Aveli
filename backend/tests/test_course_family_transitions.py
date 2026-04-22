import asyncio
from uuid import uuid4

import pytest

from app import db
from app.services import courses_service


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


async def _cleanup_courses(course_ids: list[str]) -> None:
    exact_ids = [course_id for course_id in course_ids if course_id]
    if not exact_ids:
        return
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.courses where id = any(%s::uuid[])",
                (exact_ids,),
            )
            await conn.commit()


async def _cleanup_teacher(teacher_id: str) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.auth_subjects where user_id = %s::uuid",
                (teacher_id,),
            )
            await conn.commit()


async def _cleanup_course_families(teacher_id: str) -> None:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.course_families where teacher_id = %s::uuid",
                (teacher_id,),
            )
            await conn.commit()


async def _create_course_family(
    *,
    teacher_id: str,
    name: str | None = None,
) -> dict[str, object]:
    await _ensure_pool_open()
    return await courses_service.create_course_family(
        name=name or f"Course Family {uuid4().hex[:6]}",
        teacher_id=teacher_id,
    )


async def _create_course(
    *,
    teacher_id: str,
    course_group_id: str,
    title: str | None = None,
    slug: str | None = None,
) -> dict[str, object]:
    await _ensure_pool_open()
    return await courses_service.create_course(
        {
            "title": title or f"Course {uuid4().hex[:8]}",
            "slug": slug or f"course-{uuid4().hex[:8]}",
            "course_group_id": course_group_id,
            "price_amount_cents": None,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
        teacher_id=teacher_id,
    )


async def _family_rows(course_group_id: str) -> list[tuple[str, int]]:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select id::text, group_position
                from app.courses
                where course_group_id = %s::uuid
                order by group_position asc, id asc
                """,
                (course_group_id,),
            )
            rows = await cur.fetchall()
    return [(str(row[0]), int(row[1])) for row in rows]


async def _course_family_events(course_ids: list[str]) -> list[tuple[str, str, int | None, int | None]]:
    await _ensure_pool_open()
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select course_id::text, event_type, old_group_position, new_group_position
                from app.course_family_position_events
                where course_id = any(%s::uuid[])
                order by created_at asc, course_id asc
                """,
                (course_ids,),
            )
            rows = await cur.fetchall()
    return [
        (
            str(row[0]),
            str(row[1]),
            None if row[2] is None else int(row[2]),
            None if row[3] is None else int(row[3]),
        )
        for row in rows
    ]


async def test_create_course_appends_and_rejects_raw_position_payloads() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(teacher_id=teacher_id)
        family_id = str(family["id"])
        first = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
        )
        created_ids.append(str(first["id"]))

        second = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
        )
        created_ids.append(str(second["id"]))

        with pytest.raises(ValueError, match="append within the family automatically"):
            await courses_service.create_course(
                {
                    "title": f"Course {uuid4().hex[:8]}",
                    "slug": f"course-{uuid4().hex[:8]}",
                    "course_group_id": family_id,
                    "group_position": 99,
                    "price_amount_cents": None,
                    "drip_enabled": False,
                    "drip_interval_days": None,
                },
                teacher_id=teacher_id,
            )

        assert await _family_rows(family_id) == [
            (str(first["id"]), 0),
            (str(second["id"]), 1),
        ]
        assert await _course_family_events(created_ids) == [
            (str(first["id"]), "insert", None, 0),
            (str(second["id"]), "insert", None, 1),
        ]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_create_course_family_exists_without_courses() -> None:
    teacher_id = str(uuid4())

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(
            teacher_id=teacher_id,
            name="Standalone Family",
        )

        assert str(family["name"]) == "Standalone Family"
        assert int(family["course_count"]) == 0
        assert await _family_rows(str(family["id"])) == []
    finally:
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_rename_course_family_updates_canonical_name() -> None:
    teacher_id = str(uuid4())

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(
            teacher_id=teacher_id,
            name="Original Family",
        )

        renamed = await courses_service.rename_course_family(
            str(family["id"]),
            name="Renamed Family",
            teacher_id=teacher_id,
        )

        assert renamed is not None
        assert str(renamed["id"]) == str(family["id"])
        assert str(renamed["name"]) == "Renamed Family"
        listed = await courses_service.list_course_families(teacher_id=teacher_id)
        assert [str(item["name"]) for item in listed] == ["Renamed Family"]
    finally:
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_rename_course_family_requires_owner() -> None:
    owner_teacher_id = str(uuid4())
    other_teacher_id = str(uuid4())

    await _ensure_teacher(owner_teacher_id)
    await _ensure_teacher(other_teacher_id)
    try:
        family = await _create_course_family(
            teacher_id=owner_teacher_id,
            name="Owner Family",
        )

        with pytest.raises(PermissionError, match="Not course family owner"):
            await courses_service.rename_course_family(
                str(family["id"]),
                name="Hijacked Family",
                teacher_id=other_teacher_id,
            )
    finally:
        await _cleanup_course_families(owner_teacher_id)
        await _cleanup_course_families(other_teacher_id)
        await _cleanup_teacher(owner_teacher_id)
        await _cleanup_teacher(other_teacher_id)


async def test_delete_course_family_requires_empty_family() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(
            teacher_id=teacher_id,
            name="Non-empty Family",
        )
        family_id = str(family["id"])
        course = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"non-empty-{uuid4().hex[:8]}",
        )
        created_ids.append(str(course["id"]))

        with pytest.raises(ValueError, match="must be empty before deletion"):
            await courses_service.delete_course_family(
                family_id,
                teacher_id=teacher_id,
            )

        listed = await courses_service.list_course_families(teacher_id=teacher_id)
        assert [str(item["id"]) for item in listed] == [family_id]
        assert [int(item["course_count"]) for item in listed] == [1]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_delete_course_family_removes_empty_family() -> None:
    teacher_id = str(uuid4())

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(
            teacher_id=teacher_id,
            name="Disposable Family",
        )

        deleted = await courses_service.delete_course_family(
            str(family["id"]),
            teacher_id=teacher_id,
        )

        assert deleted is True
        assert await courses_service.list_course_families(teacher_id=teacher_id) == []
    finally:
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_reorder_course_within_family_is_transactional() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(teacher_id=teacher_id)
        family_id = str(family["id"])
        course_a = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"a-{uuid4().hex[:8]}",
        )
        course_b = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"b-{uuid4().hex[:8]}",
        )
        course_c = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"c-{uuid4().hex[:8]}",
        )
        created_ids.extend(
            [str(course_a["id"]), str(course_b["id"]), str(course_c["id"])]
        )

        with pytest.raises(ValueError, match="current course family"):
            await courses_service.reorder_course_within_family(
                str(course_a["id"]),
                group_position=3,
                teacher_id=teacher_id,
            )

        updated = await courses_service.reorder_course_within_family(
            str(course_a["id"]),
            group_position=2,
            teacher_id=teacher_id,
        )

        assert updated is not None
        assert int(updated["group_position"]) == 2
        assert await _family_rows(family_id) == [
            (str(course_b["id"]), 0),
            (str(course_c["id"]), 1),
            (str(course_a["id"]), 2),
        ]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_move_between_families_appends_and_collapses_source() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        source_family = await _create_course_family(
            teacher_id=teacher_id,
            name="Source Family",
        )
        target_family = await _create_course_family(
            teacher_id=teacher_id,
            name="Target Family",
        )
        source_family_id = str(source_family["id"])
        target_family_id = str(target_family["id"])
        source_a = await _create_course(
            teacher_id=teacher_id,
            course_group_id=source_family_id,
        )
        source_b = await _create_course(
            teacher_id=teacher_id,
            course_group_id=source_family_id,
        )
        target_a = await _create_course(
            teacher_id=teacher_id,
            course_group_id=target_family_id,
        )
        target_b = await _create_course(
            teacher_id=teacher_id,
            course_group_id=target_family_id,
        )
        created_ids.extend(
            [
                str(source_a["id"]),
                str(source_b["id"]),
                str(target_a["id"]),
                str(target_b["id"]),
            ]
        )

        with pytest.raises(ValueError, match="different course_group_id"):
            await courses_service.move_course_to_family(
                str(source_a["id"]),
                course_group_id=source_family_id,
                teacher_id=teacher_id,
            )

        moved = await courses_service.move_course_to_family(
            str(source_a["id"]),
            course_group_id=target_family_id,
            teacher_id=teacher_id,
        )

        assert moved is not None
        assert str(moved["course_group_id"]) == target_family_id
        assert int(moved["group_position"]) == 2
        assert await _family_rows(source_family_id) == [
            (str(source_b["id"]), 0),
        ]
        assert await _family_rows(target_family_id) == [
            (str(target_a["id"]), 0),
            (str(target_b["id"]), 1),
            (str(source_a["id"]), 2),
        ]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_delete_course_collapses_remaining_family_positions() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(teacher_id=teacher_id)
        family_id = str(family["id"])
        course_a = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
        )
        course_b = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
        )
        course_c = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
        )
        created_ids.extend(
            [str(course_a["id"]), str(course_b["id"]), str(course_c["id"])]
        )

        deleted = await courses_service.delete_course(
            str(course_b["id"]),
            teacher_id=teacher_id,
        )

        assert deleted is True
        created_ids.remove(str(course_b["id"]))
        assert await _family_rows(family_id) == [
            (str(course_a["id"]), 0),
            (str(course_c["id"]), 1),
        ]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)


async def test_concurrent_family_operations_remain_contiguous() -> None:
    teacher_id = str(uuid4())
    created_ids: list[str] = []

    await _ensure_teacher(teacher_id)
    try:
        family = await _create_course_family(teacher_id=teacher_id)
        family_id = str(family["id"])
        course_a = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"concurrent-a-{uuid4().hex[:8]}",
        )
        course_b = await _create_course(
            teacher_id=teacher_id,
            course_group_id=family_id,
            slug=f"concurrent-b-{uuid4().hex[:8]}",
        )
        created_ids.extend([str(course_a["id"]), str(course_b["id"])])

        created_course, reordered_course = await asyncio.gather(
            _create_course(
                teacher_id=teacher_id,
                course_group_id=family_id,
                slug=f"concurrent-c-{uuid4().hex[:8]}",
            ),
            courses_service.reorder_course_within_family(
                str(course_a["id"]),
                group_position=1,
                teacher_id=teacher_id,
            ),
        )

        created_ids.append(str(created_course["id"]))
        assert reordered_course is not None
        assert await _family_rows(family_id) == [
            (str(course_b["id"]), 0),
            (str(course_a["id"]), 1),
            (str(created_course["id"]), 2),
        ]
    finally:
        await _cleanup_courses(created_ids)
        await _cleanup_course_families(teacher_id)
        await _cleanup_teacher(teacher_id)
