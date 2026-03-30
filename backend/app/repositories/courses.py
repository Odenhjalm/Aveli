from __future__ import annotations

from uuid import uuid4
from typing import Any, Sequence

from psycopg.rows import dict_row

from ..db import pool


CourseRow = dict[str, Any]
LessonRow = dict[str, Any]

_COURSE_COLUMNS = """
    c.id,
    c.slug,
    c.title,
    c.course_group_id,
    c.step::text as step,
    c.price_amount_cents,
    c.drip_enabled,
    c.drip_interval_days,
    c.cover_media_id
"""


def _lesson_columns(include_content: bool) -> str:
    columns = [
        "l.id",
        "l.course_id",
        "l.lesson_title as title",
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
    normalized = str(slug or "").strip().lower()
    if not normalized:
        return None
    return await get_course(slug=normalized)


async def list_courses(
    *,
    limit: int | None = None,
    search: str | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if search:
        pattern = f"%{str(search).strip().lower()}%"
        clauses.append("(lower(c.title) like %s or lower(c.slug) like %s)")
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
    return await list_courses(search=search, limit=limit)


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
            l.lesson_title as title,
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


async def get_lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    lesson = await get_lesson(lesson_id)
    if lesson is None:
        return None, None
    return lesson_id, str(lesson.get("course_id") or "") or None


async def list_lesson_media(lesson_id: str) -> Sequence[dict[str, Any]]:
    query = """
        select
            lm.id,
            lm.lesson_id,
            lm.media_asset_id,
            lm.position,
            ma.media_type::text as kind,
            rm.lesson_media_id is not null as playback_ready
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
