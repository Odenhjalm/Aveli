from __future__ import annotations

from uuid import uuid4
from typing import Any, Sequence

from psycopg import errors
from psycopg.rows import dict_row

from ..db import get_conn, pool


CourseRow = dict[str, Any]
LessonRow = dict[str, Any]

_COURSE_COLUMNS = """
    c.id,
    c.slug,
    c.title,
    c.course_group_id,
    c.group_position,
    c.visibility,
    c.content_ready,
    c.price_amount_cents,
    c.stripe_product_id,
    c.active_stripe_price_id,
    c.sellable,
    c.drip_enabled,
    c.drip_interval_days,
    c.cover_media_id
"""

_PUBLIC_DISCOVERY_COLUMNS = """
    cds.id,
    cds.slug,
    cds.title,
    cds.course_group_id,
    cds.group_position,
    cds.price_amount_cents,
    cds.drip_enabled,
    cds.drip_interval_days,
    cds.cover_media_id
"""

_MEDIA_ORIGINAL_NAME_SQL = """
    nullif(regexp_replace(ma.original_object_path, '^.*/', ''), '') as original_name
"""


def _lesson_columns(include_content: bool) -> str:
    columns = [
        "l.id",
        "l.course_id",
        "l.lesson_title",
        "l.position",
    ]
    if include_content:
        columns.append("lc.content_markdown")
    return ",\n        ".join(columns)


async def get_course(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> CourseRow | None:
    if not course_id and not slug:
        raise ValueError("course_id or slug is required")

    clauses: list[str] = []
    params: list[Any] = []
    if course_id:
        clauses.append("c.id = %s")
        params.append(course_id)
    if slug:
        clauses.append("c.slug = %s")
        params.append(slug)

    query = f"""
        select {_COURSE_COLUMNS}
        from app.courses as c
        where {" and ".join(clauses)}
        limit 1
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_course_by_slug(slug: str) -> CourseRow | None:
    if slug == "":
        return None
    return await get_course(slug=slug)


async def get_course_pricing_by_slug(slug: str) -> dict[str, Any] | None:
    if slug == "":
        return None

    query = """
        select
            c.price_amount_cents as amount_cents
        from app.courses as c
        where c.slug = %s
        limit 1
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (slug,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_course_publish_subject(course_id: str) -> dict[str, Any] | None:
    query = """
        select
            c.id,
            c.teacher_id,
            c.slug,
            c.title,
            c.course_group_id,
            c.group_position,
            c.visibility,
            c.content_ready,
            c.price_amount_cents,
            c.stripe_product_id,
            c.active_stripe_price_id,
            c.sellable,
            c.drip_enabled,
            c.drip_interval_days,
            c.cover_media_id
        from app.courses as c
        where c.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def list_courses(
    *,
    teacher_id: str | None = None,
    limit: int | None = None,
    search: str | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if teacher_id:
        clauses.append("c.teacher_id = %s::uuid")
        params.append(teacher_id)
    if search:
        pattern = f"%{search}%"
        clauses.append("(c.title ilike %s or c.slug ilike %s)")
        params.extend([pattern, pattern])

    where_sql = f"where {' and '.join(clauses)}" if clauses else ""
    limit_sql = "limit %s" if limit is not None else ""
    if limit is not None:
        params.append(int(limit))

    query = f"""
        select {_COURSE_COLUMNS}
        from app.courses as c
        {where_sql}
        order by c.slug asc
        {limit_sql}
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_public_courses(
    *,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[CourseRow]:
    clauses = ["c.sellable is true"]
    params: list[Any] = []
    if search:
        pattern = f"%{search}%"
        clauses.append("(c.title ilike %s or c.slug ilike %s)")
        params.extend([pattern, pattern])

    where_sql = f"where {' and '.join(clauses)}"
    limit_sql = "limit %s" if limit is not None else ""
    if limit is not None:
        params.append(int(limit))

    query = f"""
        select {_COURSE_COLUMNS}
        from app.courses as c
        {where_sql}
        order by c.slug asc
        {limit_sql}
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_public_course_discovery(
    *,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if search:
        pattern = f"%{search}%"
        clauses.append("(cds.title ilike %s or cds.slug ilike %s)")
        params.extend([pattern, pattern])

    limit_sql = "limit %s" if limit is not None else ""
    if limit is not None:
        params.append(int(limit))

    query = f"""
        select {_PUBLIC_DISCOVERY_COLUMNS}
        from app.course_discovery_surface as cds
        join app.courses as c
          on c.id = cds.id
        where c.sellable is true
        {"and " + " and ".join(clauses) if clauses else ""}
        order by cds.slug asc
        {limit_sql}
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_lesson_structure_surface(course_id: str) -> Sequence[LessonRow]:
    query = """
        select
            lss.id,
            lss.course_id,
            lss.lesson_title,
            lss.position
        from app.lesson_structure_surface as lss
        where lss.course_id = %s::uuid
        order by lss.position asc, lss.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_public_course_detail_rows(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> Sequence[dict[str, Any]]:
    if not course_id and not slug:
        raise ValueError("course_id or slug is required")

    clauses: list[str] = []
    params: list[Any] = []
    if course_id:
        clauses.append("cd.id = %s::uuid")
        params.append(course_id)
    if slug:
        clauses.append("cd.slug = %s")
        params.append(slug)

    query = """
        select
            cd.id,
            cd.slug,
            cd.title,
            cd.course_group_id,
            cd.group_position,
            cd.cover_media_id,
            cd.price_amount_cents,
            cd.drip_enabled,
            cd.drip_interval_days,
            cd.short_description,
            cd.lesson_id,
            cd.lesson_title,
            cd.lesson_position
        from app.course_detail_surface as cd
        join app.courses as c
          on c.id = cd.id
        where c.sellable is true
          and {where_sql}
        order by cd.lesson_position asc nulls last, cd.lesson_id asc nulls last
    """.format(where_sql=" and ".join(clauses))

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_course(payload: dict[str, Any]) -> CourseRow:
    course_id = str(payload.get("id") or uuid4())
    query = """
        insert into app.courses (
            id,
            teacher_id,
            title,
            slug,
            course_group_id,
            group_position,
            price_amount_cents,
            drip_enabled,
            drip_interval_days,
            cover_media_id
        )
        values (
            %s::uuid,
            %s::uuid,
            %s,
            %s,
            %s::uuid,
            %s,
            %s,
            %s,
            %s,
            %s::uuid
        )
        returning id
    """
    params = (
        course_id,
        str(payload["teacher_id"]),
        payload["title"],
        payload["slug"],
        str(payload["course_group_id"]),
        payload["group_position"],
        payload.get("price_amount_cents"),
        payload["drip_enabled"],
        payload["drip_interval_days"],
        str(payload["cover_media_id"]) if payload.get("cover_media_id") else None,
    )
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            await cur.fetchone()
            await conn.commit()
    row = await get_course(course_id=course_id)
    if row is None:
        raise RuntimeError("created course was not returned")
    return row


async def update_course(course_id: str, patch: dict[str, Any]) -> CourseRow | None:
    assignments: list[str] = []
    params: list[Any] = []
    field_specs = (
        ("title", "title = %s", lambda value: value),
        ("slug", "slug = %s", lambda value: value),
        ("course_group_id", "course_group_id = %s::uuid", lambda value: str(value)),
        ("group_position", "group_position = %s", lambda value: int(value)),
        ("price_amount_cents", "price_amount_cents = %s", lambda value: value),
        ("drip_enabled", "drip_enabled = %s", lambda value: value),
        ("drip_interval_days", "drip_interval_days = %s", lambda value: value),
        ("cover_media_id", "cover_media_id = %s::uuid", lambda value: str(value) if value else None),
    )
    for key, sql, serializer in field_specs:
        if key not in patch:
            continue
        assignments.append(sql)
        params.append(serializer(patch[key]))

    if not assignments:
        return await get_course(course_id=course_id)

    params.append(course_id)
    query = f"""
        update app.courses
        set {", ".join(assignments)}
        where id = %s::uuid
        returning id
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_course(course_id=course_id)


async def update_course_stripe_mapping(
    course_id: str,
    *,
    stripe_product_id: str,
    active_stripe_price_id: str,
) -> CourseRow | None:
    query = """
        update app.courses
        set stripe_product_id = %s,
            active_stripe_price_id = %s
        where id = %s::uuid
        returning id
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    stripe_product_id,
                    active_stripe_price_id,
                    course_id,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_course(course_id=course_id)


async def publish_course_state(
    course_id: str,
    *,
    stripe_product_id: str,
    active_stripe_price_id: str,
) -> CourseRow | None:
    query = """
        update app.courses
        set content_ready = true,
            visibility = 'public'::app.course_visibility,
            stripe_product_id = %s,
            active_stripe_price_id = %s,
            sellable = true
        where id = %s::uuid
        returning id
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    stripe_product_id,
                    active_stripe_price_id,
                    course_id,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_course(course_id=course_id)


async def get_course_sellability_subject(course_id: str) -> dict[str, Any] | None:
    query = """
        select
            c.id,
            c.teacher_id,
            c.group_position,
            c.visibility,
            c.content_ready,
            c.price_amount_cents,
            c.stripe_product_id,
            c.active_stripe_price_id,
            c.sellable
        from app.courses as c
        where c.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def update_course_sellability(
    course_id: str,
    *,
    sellable: bool,
) -> CourseRow | None:
    query = """
        update app.courses
        set sellable = %s
        where id = %s::uuid
        returning id
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (sellable, course_id))
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_course(course_id=course_id)


async def delete_course(course_id: str) -> bool:
    query = "delete from app.courses where id = %s::uuid"
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            deleted = cur.rowcount > 0
            await conn.commit()
    return deleted


async def is_course_owner(course_id: str, teacher_id: str) -> bool:
    query = """
        select 1
        from app.courses as c
        where c.id = %s::uuid
          and c.teacher_id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id, teacher_id))
            return await cur.fetchone() is not None


async def list_course_ownership_rows(course_ids: Sequence[str]) -> Sequence[dict[str, Any]]:
    normalized_ids = [str(course_id or "").strip() for course_id in course_ids]
    exact_ids = [course_id for course_id in normalized_ids if course_id]
    if not exact_ids:
        return []

    query = """
        select
            c.id,
            c.teacher_id
        from app.courses as c
        where c.id = any(%s::uuid[])
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (exact_ids,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_course_public_content(course_id: str) -> dict[str, Any] | None:
    query = """
        select
            cpc.course_id,
            cpc.short_description
        from app.course_public_content as cpc
        where cpc.course_id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def upsert_course_public_content(
    course_id: str,
    *,
    short_description: str,
) -> dict[str, Any]:
    query = """
        insert into app.course_public_content (
            course_id,
            short_description
        )
        values (
            %s::uuid,
            %s
        )
        on conflict (course_id) do update
        set short_description = excluded.short_description
        returning
            course_id,
            short_description
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id, short_description))
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        raise RuntimeError("course public content was not returned")
    return dict(row)


async def list_my_courses(user_id: str) -> Sequence[CourseRow]:
    query = f"""
        select distinct on (c.id)
            {_COURSE_COLUMNS}
        from app.course_enrollments as ce
        join app.courses as c
          on c.id = ce.course_id
        where ce.user_id = %s
        order by c.id, ce.granted_at desc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_course_enrollment(user_id: str, course_id: str) -> dict[str, Any] | None:
    query = """
        select
            ce.id,
            ce.user_id,
            ce.course_id,
            ce.source::text as source,
            ce.granted_at,
            ce.drip_started_at,
            ce.current_unlock_position
        from app.course_enrollments as ce
        where ce.user_id = %s
          and ce.course_id = %s
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, course_id))
            row = await cur.fetchone()
    return dict(row) if row else None


async def is_enrolled(user_id: str, course_id: str) -> bool:
    return await get_course_enrollment(user_id, course_id) is not None


async def list_course_lessons(course_id: str) -> Sequence[LessonRow]:
    query = """
        select
            l.id,
            l.lesson_title,
            l.position
        from app.lessons as l
        where l.course_id = %s
        order by l.position asc, l.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_lesson_content_surface_rows(
    *,
    lesson_id: str,
    user_id: str,
) -> Sequence[dict[str, Any]]:
    async with get_conn() as cur:
        await cur.execute(
            "select set_config('request.jwt.claim.sub', %s, true)",
            (user_id,),
        )
        await cur.execute(
            """
            select
                lcs.id,
                lcs.course_id,
                lcs.lesson_title,
                lcs.position,
                lcs.content_markdown,
                lm.id as lesson_media_id,
                lm.media_asset_id,
                lm.position as lesson_media_position
            from app.lesson_content_surface as lcs
            left join app.lesson_media as lm
              on lm.lesson_id = lcs.id
            where lcs.id = %s::uuid
            order by lm.position asc nulls last,
                     lm.id asc nulls last
            """,
            (lesson_id,),
        )
        rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_studio_course_lessons(course_id: str) -> Sequence[LessonRow]:
    query = """
        select
            l.id,
            l.course_id,
            l.lesson_title,
            l.position
        from app.lessons as l
        where l.course_id = %s::uuid
        order by l.position asc, l.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_course_publish_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    query = """
        select
            l.id,
            l.course_id,
            l.lesson_title,
            l.position,
            lc.lesson_id is not null as has_content,
            lc.content_markdown
        from app.lessons as l
        left join app.lesson_contents as lc
          on lc.lesson_id = l.id
        where l.course_id = %s::uuid
        order by l.position asc, l.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_lesson(lesson_id: str) -> LessonRow | None:
    query = f"""
        select {_lesson_columns(include_content=True)}
        from app.lessons as l
        left join app.lesson_contents as lc
          on lc.lesson_id = l.id
        where l.id = %s
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_studio_lesson(lesson_id: str) -> LessonRow | None:
    query = """
        select
            l.id,
            l.course_id,
            l.lesson_title,
            l.position,
            lc.content_markdown
        from app.lessons as l
        left join app.lesson_contents as lc
          on lc.lesson_id = l.id
        where l.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_lesson_structure(lesson_id: str) -> LessonRow | None:
    query = """
        select
            l.id,
            l.course_id,
            l.lesson_title,
            l.position
        from app.lessons as l
        where l.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_studio_lesson_content(lesson_id: str) -> dict[str, Any] | None:
    query = """
        select
            l.id as lesson_id,
            l.course_id,
            coalesce(lc.content_markdown, '') as content_markdown
        from app.lessons as l
        left join app.lesson_contents as lc
          on lc.lesson_id = l.id
        where l.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    query = """
        select
            l.id,
            l.course_id
        from app.lessons as l
        where l.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
    if row is None:
        return None, None
    return str(row["id"]), str(row["course_id"])


async def list_lesson_media(lesson_id: str) -> Sequence[dict[str, Any]]:
    query = f"""
        select
            lm.id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as media_type,
            ma.state::text as state,
            {_MEDIA_ORIGINAL_NAME_SQL},
            rm.lesson_media_id is not null as preview_ready
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        left join app.runtime_media as rm
          on rm.lesson_media_id = lm.id
        where lm.lesson_id = %s
        order by lm.position asc, lm.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_lesson_media_for_asset(
    media_asset_id: str,
    *,
    limit: int = 25,
) -> Sequence[dict[str, Any]]:
    capped_limit = max(1, min(int(limit or 25), 100))
    query = """
        select
            lm.id,
            lm.lesson_id,
            null::text as kind,
            lm.position,
            lm.media_asset_id,
            ma.state::text as media_state,
            null::text as content_type,
            null::integer as duration_seconds,
            null::text as error_message,
            null::text as issue_reason,
            null::jsonb as issue_details,
            null::timestamptz as issue_updated_at,
            null::timestamptz as created_at,
            null::text as storage_bucket,
            null::text as storage_path
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        where lm.media_asset_id = %s::uuid
        order by lm.position asc, lm.id asc
        limit %s
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (media_asset_id, capped_limit))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_lesson_media_asset_ids(lesson_id: str) -> list[str]:
    query = """
        select media_asset_id
        from app.lesson_media
        where lesson_id = %s::uuid
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            rows = await cur.fetchall()
    return [
        str(row["media_asset_id"])
        for row in rows
        if row.get("media_asset_id") is not None
    ]


async def list_lesson_media_for_studio(lesson_id: str) -> Sequence[dict[str, Any]]:
    query = f"""
        select
            lm.id as lesson_media_id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as media_type,
            ma.state::text as state,
            {_MEDIA_ORIGINAL_NAME_SQL},
            (ma.state in ('uploaded', 'ready')) as preview_ready
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        where lm.lesson_id = %s
        order by lm.position asc, lm.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_lesson_media_for_studio(
    lesson_id: str,
    lesson_media_id: str,
) -> dict[str, Any] | None:
    query = f"""
        select
            lm.id as lesson_media_id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as media_type,
            ma.state::text as state,
            {_MEDIA_ORIGINAL_NAME_SQL},
            (ma.state in ('uploaded', 'ready')) as preview_ready
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        where lm.lesson_id = %s::uuid
          and lm.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id, lesson_media_id))
            row = await cur.fetchone()
    return dict(row) if row else None


async def get_lesson_media_by_id_for_studio(
    lesson_media_id: str,
) -> dict[str, Any] | None:
    query = f"""
        select
            lm.id as lesson_media_id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as media_type,
            ma.state::text as state,
            {_MEDIA_ORIGINAL_NAME_SQL},
            (ma.state in ('uploaded', 'ready')) as preview_ready
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        where lm.id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_media_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def list_lesson_media_by_ids_for_studio(
    lesson_media_ids: Sequence[str],
) -> Sequence[dict[str, Any]]:
    exact_ids = list(lesson_media_ids)
    if not exact_ids:
        return []

    query = f"""
        select
            lm.id as lesson_media_id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as media_type,
            ma.state::text as state,
            {_MEDIA_ORIGINAL_NAME_SQL},
            (ma.state in ('uploaded', 'ready')) as preview_ready
        from app.lesson_media as lm
        join app.media_assets as ma
          on ma.id = lm.media_asset_id
        where lm.id = any(%s::uuid[])
        order by lm.position asc, lm.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (exact_ids,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_lesson_media(
    *,
    lesson_id: str,
    media_asset_id: str,
    lesson_media_id: str | None = None,
) -> dict[str, Any]:
    new_lesson_media_id = str(lesson_media_id or uuid4())
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select coalesce(max(position), 0) + 1 as next_position
                from app.lesson_media
                where lesson_id = %s::uuid
                """,
                (lesson_id,),
            )
            position_row = await cur.fetchone()
            position = int(position_row["next_position"]) if position_row else 1
            await cur.execute(
                """
                insert into app.lesson_media (
                    id,
                    lesson_id,
                    media_asset_id,
                    position
                )
                values (
                    %s::uuid,
                    %s::uuid,
                    %s::uuid,
                    %s
                )
                """,
                (new_lesson_media_id, lesson_id, media_asset_id, position),
            )
            await conn.commit()
    row = await get_lesson_media_for_studio(lesson_id, new_lesson_media_id)
    if row is None:
        raise RuntimeError("created lesson_media was not returned")
    return row


async def reorder_lesson_media(
    lesson_id: str,
    ordered_lesson_media_ids: Sequence[str],
) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select id
                from app.lesson_media
                where lesson_id = %s::uuid
                order by position asc, id asc
                """,
                (lesson_id,),
            )
            rows = await cur.fetchall()
            existing_ids = [
                str(row["id"])
                for row in rows
                if row.get("id") is not None
            ]
            if set(existing_ids) != set(ordered_lesson_media_ids):
                raise ValueError(
                    "Reorder payload must include every lesson media row exactly once"
                )

            offset = len(ordered_lesson_media_ids)
            for index, current_lesson_media_id in enumerate(
                ordered_lesson_media_ids,
                start=1,
            ):
                await cur.execute(
                    """
                    update app.lesson_media
                    set position = %s
                    where lesson_id = %s::uuid
                      and id = %s::uuid
                    """,
                    (offset + index, lesson_id, current_lesson_media_id),
                )

            for index, current_lesson_media_id in enumerate(
                ordered_lesson_media_ids,
                start=1,
            ):
                await cur.execute(
                    """
                    update app.lesson_media
                    set position = %s
                    where lesson_id = %s::uuid
                      and id = %s::uuid
                    """,
                    (index, lesson_id, current_lesson_media_id),
                )
            await conn.commit()


async def delete_lesson_media(
    lesson_id: str,
    lesson_media_id: str,
) -> dict[str, Any] | None:
    query = """
        delete from app.lesson_media
        where lesson_id = %s::uuid
          and id = %s::uuid
        returning id, lesson_id, media_asset_id, position
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id, lesson_media_id))
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def lesson_media_asset_is_linked(media_asset_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select 1
                from app.lesson_media
                where media_asset_id = %s::uuid
                limit 1
                """,
                (media_asset_id,),
            )
            row = await cur.fetchone()
    return row is not None


async def create_lesson(
    *,
    lesson_id: str | None,
    course_id: str,
    lesson_title: str,
    content_markdown: str,
    position: int,
) -> LessonRow:
    new_lesson_id = str(lesson_id or uuid4())
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lessons (id, course_id, lesson_title, position)
                values (%s::uuid, %s::uuid, %s, %s)
                """,
                (new_lesson_id, course_id, lesson_title, position),
            )
            await cur.execute(
                """
                insert into app.lesson_contents (lesson_id, content_markdown)
                values (%s::uuid, %s)
                """,
                (new_lesson_id, content_markdown),
            )
            await conn.commit()
    row = await get_studio_lesson(new_lesson_id)
    if row is None:
        raise RuntimeError("created lesson was not returned")
    return row


async def create_lesson_structure(
    *,
    course_id: str,
    lesson_title: str,
    position: int,
) -> LessonRow:
    new_lesson_id = str(uuid4())
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lessons (id, course_id, lesson_title, position)
                values (%s::uuid, %s::uuid, %s, %s)
                """,
                (new_lesson_id, course_id, lesson_title, position),
            )
            await conn.commit()
    row = await get_lesson_structure(new_lesson_id)
    if row is None:
        raise RuntimeError("created lesson structure was not returned")
    return row


async def update_lesson_structure(
    lesson_id: str,
    patch: dict[str, Any],
) -> LessonRow | None:
    assignments: list[str] = []
    params: list[Any] = []
    if "lesson_title" in patch:
        assignments.append("lesson_title = %s")
        params.append(patch["lesson_title"])
    if "position" in patch:
        assignments.append("position = %s")
        params.append(patch["position"])

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            if assignments:
                await cur.execute(
                    f"""
                    update app.lessons
                    set {", ".join(assignments)}
                    where id = %s::uuid
                    returning id, course_id, lesson_title, position
                    """,
                    (*params, lesson_id),
                )
            else:
                await cur.execute(
                    """
                    select id, course_id, lesson_title, position
                    from app.lessons
                    where id = %s::uuid
                    limit 1
                    """,
                    (lesson_id,),
                )
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def update_lesson_content(
    lesson_id: str,
    content_markdown: str,
) -> dict[str, Any] | None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "select id from app.lessons where id = %s::uuid limit 1",
                (lesson_id,),
            )
            lesson_row = await cur.fetchone()
            if lesson_row is None:
                return None

            await cur.execute(
                """
                insert into app.lesson_contents (lesson_id, content_markdown)
                values (%s::uuid, %s)
                on conflict (lesson_id)
                do update set content_markdown = excluded.content_markdown
                returning lesson_id, content_markdown
                """,
                (lesson_id, content_markdown),
            )
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def update_lesson_content_if_current(
    lesson_id: str,
    content_markdown: str,
    *,
    expected_content_markdown: str,
) -> dict[str, Any] | None:
    query = """
        with target_lesson as (
            select id
            from app.lessons
            where id = %s::uuid
        ),
        current_content as (
            select content_markdown
            from app.lesson_contents
            where lesson_id = %s::uuid
        ),
        updated_content as (
            insert into app.lesson_contents (lesson_id, content_markdown)
            select target_lesson.id, %s
            from target_lesson
            where coalesce(
                (select current_content.content_markdown from current_content),
                ''
            ) = %s
            on conflict (lesson_id)
            do update set content_markdown = excluded.content_markdown
            where app.lesson_contents.content_markdown = %s
            returning lesson_id, content_markdown
        )
        select lesson_id, content_markdown
        from updated_content
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    lesson_id,
                    lesson_id,
                    content_markdown,
                    expected_content_markdown,
                    expected_content_markdown,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
    return dict(row) if row else None


async def update_lesson(lesson_id: str, patch: dict[str, Any]) -> LessonRow | None:
    del lesson_id, patch
    raise RuntimeError(
        "Legacy mixed lesson update is disabled; use separate structure and content surfaces"
    )


async def reorder_lessons(course_id: str, ordered_lesson_ids: Sequence[str]) -> None:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            for index, lesson_id in enumerate(ordered_lesson_ids, start=1):
                await cur.execute(
                    """
                    update app.lessons
                    set position = %s
                    where id = %s::uuid
                      and course_id = %s::uuid
                    """,
                    (index, lesson_id, course_id),
                )
            await conn.commit()


async def delete_lesson(lesson_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "delete from app.lesson_contents where lesson_id = %s::uuid",
                (lesson_id,),
            )
            await cur.execute(
                "delete from app.lesson_media where lesson_id = %s::uuid",
                (lesson_id,),
            )
            await cur.execute(
                "delete from app.lessons where id = %s::uuid",
                (lesson_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
    return deleted


async def create_course_enrollment(
    *,
    user_id: str,
    course_id: str,
    source: str,
) -> dict[str, Any]:
    enrollment_id = str(uuid4())
    query = """
        select
            ce.id,
            ce.user_id,
            ce.course_id,
            ce.source::text as source,
            ce.granted_at,
            ce.drip_started_at,
            ce.current_unlock_position
        from app.canonical_create_course_enrollment(
            %s::uuid,
            %s::uuid,
            %s::uuid,
            %s::app.course_enrollment_source,
            clock_timestamp()
        ) as ce
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (enrollment_id, user_id, course_id, source))
            row = await cur.fetchone()
    if row is None:
        raise RuntimeError("canonical course enrollment was not returned")
    return dict(row)


async def revoke_course_enrollment(
    user_id: str,
    course_id: str,
    *,
    excluding_order_id: str | None = None,
) -> bool:
    if await _has_remaining_paid_course_purchase(
        user_id,
        course_id,
        excluding_order_id=excluding_order_id,
    ):
        return False

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                delete from app.course_enrollments
                where user_id = %s::uuid
                  and course_id = %s::uuid
                """,
                (user_id, course_id),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
    return deleted


async def _has_remaining_paid_course_purchase(
    user_id: str,
    course_id: str,
    *,
    excluding_order_id: str | None = None,
) -> bool:
    direct_query = """
        select 1
        from app.orders as o
        where o.user_id = %s::uuid
          and o.status = 'paid'
          and o.course_id = %s::uuid
          and (%s::uuid is null or o.id <> %s::uuid)
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                direct_query,
                (user_id, course_id, excluding_order_id, excluding_order_id),
            )
            if await cur.fetchone() is not None:
                return True

    bundle_query = """
        select 1
        from app.orders as o
        join app.course_bundle_courses as cbc
          on cbc.bundle_id::text = o.metadata->>'bundle_id'
        where o.user_id = %s::uuid
          and o.status = 'paid'
          and o.order_type::text = 'bundle'
          and cbc.course_id = %s::uuid
          and (%s::uuid is null or o.id <> %s::uuid)
        limit 1
    """
    try:
        async with pool.connection() as conn:  # type: ignore
            async with conn.cursor() as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    bundle_query,
                    (user_id, course_id, excluding_order_id, excluding_order_id),
                )
                return await cur.fetchone() is not None
    except errors.UndefinedTable:
        return False
