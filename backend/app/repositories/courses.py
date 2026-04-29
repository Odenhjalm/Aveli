from __future__ import annotations

import logging
from typing import Any, Sequence
from uuid import UUID, uuid4

from psycopg import Error as PsycopgError
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool


CourseRow = dict[str, Any]
LessonRow = dict[str, Any]
logger = logging.getLogger(__name__)
_EMPTY_LESSON_DOCUMENT_SQL = (
    """'{"schema_version":"lesson_document_v1","blocks":[]}'::jsonb"""
)
_MISSING_COURSE_PUBLIC_CONTENT_ERROR = (
    "Invariant violation: missing course_public_content"
)

_COURSE_COLUMNS = """
    c.id,
    c.slug,
    c.title,
    c.teacher_id,
    c.course_group_id,
    c.group_position,
    c.visibility,
    c.content_ready,
    c.price_amount_cents,
    c.stripe_product_id,
    c.active_stripe_price_id,
    c.sellable,
    c.required_enrollment_source::text as required_enrollment_source,
    c.drip_enabled,
    c.drip_interval_days,
    c.cover_media_id
"""

_STUDIO_COURSE_COLUMNS = f"""
    {_COURSE_COLUMNS},
    case
        when exists (
            select 1
            from app.course_custom_drip_configs as config
            where config.course_id = c.id
        ) then 'custom_lesson_offsets'
        when c.drip_enabled is true
             and c.drip_interval_days is not null
             and c.drip_interval_days > 0
          then 'legacy_uniform_drip'
        else 'no_drip_immediate_access'
    end as drip_mode,
    exists (
        select 1
        from app.course_enrollments as ce
        where ce.course_id = c.id
    ) as schedule_locked
"""

_PUBLIC_DISCOVERY_COLUMNS = """
    cds.id,
    cds.slug,
    cds.title,
    c.teacher_id,
    nullif(btrim(p.display_name), '') as teacher_display_name,
    cds.course_group_id,
    cds.group_position,
    cds.price_amount_cents,
    cds.drip_enabled,
    cds.drip_interval_days,
    cds.cover_media_id,
    cds.required_enrollment_source::text as required_enrollment_source,
    cpc.description,
    c.sellable
"""

_MEDIA_ORIGINAL_NAME_SQL = """
    coalesce(
        nullif(btrim(ma.original_filename), ''),
        nullif(regexp_replace(ma.original_object_path, '^.*/', ''), '')
    ) as original_name
"""


async def _assert_course_public_content_invariant(conn: Any) -> None:
    query = """
        select 1
        from app.courses as c
        where not exists (
            select 1
            from app.course_public_content as cpc
            where cpc.course_id = c.id
        )
        limit 1
    """
    async with conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(query)
        row = await cur.fetchone()
    if row is not None:
        raise RuntimeError(_MISSING_COURSE_PUBLIC_CONTENT_ERROR)


class CourseCreateDatabaseError(RuntimeError):
    def __init__(
        self,
        *,
        title: str | None,
        slug: str | None,
        cause: PsycopgError,
    ) -> None:
        super().__init__("course create database error")
        self.title = title
        self.slug = slug
        self.cause = cause


class CourseScheduleLockedError(RuntimeError):
    def __init__(self, course_id: str) -> None:
        super().__init__(
            "custom drip schedule-affecting edits are locked after first enrollment"
        )
        self.course_id = course_id


def _safe_course_create_log_value(value: Any, *, limit: int = 160) -> str | None:
    if value is None:
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    if len(text) <= limit:
        return text
    return f"{text[: limit - 3]}..."


def _course_create_db_log_context(
    payload: dict[str, Any],
    exc: PsycopgError,
) -> dict[str, Any]:
    diag = getattr(exc, "diag", None)
    return {
        "course_create_title": _safe_course_create_log_value(payload.get("title")),
        "course_create_slug": _safe_course_create_log_value(payload.get("slug")),
        "db_error_type": exc.__class__.__name__,
        "db_sqlstate": getattr(exc, "sqlstate", None),
        "db_constraint_name": getattr(diag, "constraint_name", None),
        "db_message": _safe_course_create_log_value(exc, limit=500),
    }


async def _acquire_course_transition_lock(
    active_conn: Any,
    *,
    scope: str,
    key: str,
) -> None:
    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(
            "select pg_advisory_xact_lock(hashtextextended(%s, 0))",
            (f"app.courses.{scope}:{key}",),
        )


async def _acquire_course_family_locks(
    active_conn: Any,
    course_group_ids: Sequence[str],
) -> None:
    normalized_ids = sorted(
        {
            str(course_group_id).strip()
            for course_group_id in course_group_ids
            if str(course_group_id).strip()
        }
    )
    for course_group_id in normalized_ids:
        await _acquire_course_transition_lock(
            active_conn,
            scope="family",
            key=course_group_id,
        )


async def _get_course_transition_row(
    active_conn: Any,
    course_id: str,
    *,
    for_update: bool = False,
) -> dict[str, Any] | None:
    query = """
        select
            c.id::text as id,
            c.teacher_id::text as teacher_id,
            c.course_group_id::text as course_group_id,
            c.group_position
        from app.courses as c
        where c.id = %s::uuid
        limit 1
    """
    if for_update:
        query = """
            select
                c.id::text as id,
                c.teacher_id::text as teacher_id,
                c.course_group_id::text as course_group_id,
                c.group_position
            from app.courses as c
            where c.id = %s::uuid
            for update
        """

    async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
        await cur.execute(query, (course_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def _get_course_family_size(
    active_conn: Any,
    course_group_id: str,
) -> int:
    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            select count(*)::integer
            from app.courses
            where course_group_id = %s::uuid
            """,
            (course_group_id,),
        )
        row = await cur.fetchone()
    return int(row[0] if row else 0)


async def _get_course_family_append_position(
    active_conn: Any,
    course_group_id: str,
) -> int:
    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            select coalesce(max(group_position), -1)::integer + 1
            from app.courses
            where course_group_id = %s::uuid
            """,
            (course_group_id,),
        )
        row = await cur.fetchone()
    return int(row[0] if row else 0)


async def list_course_families(teacher_id: str) -> list[dict[str, Any]]:
    query = """
        select f.id::text as id,
               f.name,
               f.teacher_id::text as teacher_id,
               f.created_at,
               count(c.id)::integer as course_count
          from app.course_families as f
          left join app.courses as c
            on c.course_group_id = f.id
         where f.teacher_id = %s::uuid
         group by f.id, f.name, f.teacher_id, f.created_at
         order by lower(f.name) asc, f.created_at asc, f.id asc
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (teacher_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def get_course_family(course_group_id: str) -> dict[str, Any] | None:
    query = """
        select f.id::text as id,
               f.name,
               f.teacher_id::text as teacher_id,
               f.created_at,
               (
                 select count(*)::integer
                   from app.courses as c
                  where c.course_group_id = f.id
               ) as course_count
          from app.course_families as f
         where f.id = %s::uuid
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_group_id,))
            row = await cur.fetchone()
    return dict(row) if row else None


async def create_course_family(
    *,
    teacher_id: str,
    name: str,
    family_id: str | None = None,
) -> dict[str, Any]:
    query = """
        insert into app.course_families (
            id,
            teacher_id,
            name
        )
        values (
            coalesce(%s::uuid, gen_random_uuid()),
            %s::uuid,
            %s
        )
        returning id::text as id,
                  name,
                  teacher_id::text as teacher_id,
                  created_at,
                  0::integer as course_count
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (family_id, teacher_id, name))
            row = await cur.fetchone()
        await conn.commit()
    if row is None:
        raise RuntimeError("created course family was not returned")
    return dict(row)


async def update_course_family_name(
    course_family_id: str,
    *,
    teacher_id: str,
    name: str,
) -> dict[str, Any] | None:
    query = """
        update app.course_families as f
           set name = %s
         where f.id = %s::uuid
           and f.teacher_id = %s::uuid
        returning f.id::text as id,
                  f.name,
                  f.teacher_id::text as teacher_id,
                  f.created_at,
                  (
                    select count(*)::integer
                    from app.courses as c
                    where c.course_group_id = f.id
                  ) as course_count
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (name, course_family_id, teacher_id))
            row = await cur.fetchone()
        await conn.commit()
    return dict(row) if row else None


async def count_courses_in_family(course_family_id: str) -> int:
    async with pool.connection() as conn:  # type: ignore
        return await _get_course_family_size(conn, course_family_id)


async def delete_course_family(course_family_id: str, *, teacher_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        await _acquire_course_family_locks(conn, (course_family_id,))
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                with deleted as (
                    delete from app.course_families as f
                    where f.id = %s::uuid
                      and f.teacher_id = %s::uuid
                      and not exists (
                          select 1
                          from app.courses as c
                          where c.course_group_id = f.id
                      )
                    returning f.id
                )
                select exists(select 1 from deleted)
                """,
                (course_family_id, teacher_id),
            )
            row = await cur.fetchone()
        await conn.commit()
    return bool(row[0]) if row else False


async def _reorder_course_within_family(
    active_conn: Any,
    *,
    course_id: str,
    course_group_id: str,
    current_position: int,
    new_position: int,
) -> None:
    family_size = await _get_course_family_size(active_conn, course_group_id)
    if new_position < 0 or new_position >= family_size:
        raise ValueError("group_position must stay within the current course family")
    if new_position == current_position:
        return

    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            update app.courses
               set group_position = case
                 when id = %(course_id)s::uuid then %(new_position)s
                 when %(new_position)s < %(current_position)s
                      and group_position between %(new_position)s and %(current_position)s - 1
                   then group_position + 1
                 when %(new_position)s > %(current_position)s
                      and group_position between %(current_position)s + 1 and %(new_position)s
                   then group_position - 1
                 else group_position
               end
             where course_group_id = %(course_group_id)s::uuid
               and (
                 id = %(course_id)s::uuid
                 or (
                   %(new_position)s < %(current_position)s
                   and group_position between %(new_position)s and %(current_position)s - 1
                 )
                 or (
                   %(new_position)s > %(current_position)s
                   and group_position between %(current_position)s + 1 and %(new_position)s
                 )
               )
            """,
            {
                "course_id": course_id,
                "course_group_id": course_group_id,
                "current_position": current_position,
                "new_position": new_position,
            },
        )


async def _move_course_to_family_end(
    active_conn: Any,
    *,
    course_id: str,
    source_course_group_id: str,
    source_group_position: int,
    target_course_group_id: str,
) -> int:
    target_group_position = await _get_course_family_append_position(
        active_conn,
        target_course_group_id,
    )

    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(
            """
            with moved as (
                update app.courses
                   set course_group_id = %s::uuid,
                       group_position = %s
                 where id = %s::uuid
                 returning %s::uuid as source_course_group_id,
                           %s::integer as source_group_position
            )
            update app.courses as c
               set group_position = c.group_position - 1
              from moved
             where c.course_group_id = moved.source_course_group_id
               and c.group_position > moved.source_group_position
            """,
            (
                target_course_group_id,
                target_group_position,
                course_id,
                source_course_group_id,
                source_group_position,
            ),
        )

    return target_group_position


async def _apply_course_metadata_patch(
    active_conn: Any,
    *,
    course_id: str,
    patch: dict[str, Any],
) -> None:
    assignments: list[str] = []
    params: list[Any] = []
    field_specs = (
        ("title", "title = %s", lambda value: value),
        ("slug", "slug = %s", lambda value: value),
        (
            "required_enrollment_source",
            "required_enrollment_source = %s::app.course_enrollment_source",
            lambda value: str(value) if value is not None else None,
        ),
        ("price_amount_cents", "price_amount_cents = %s", lambda value: value),
        (
            "cover_media_id",
            "cover_media_id = %s::uuid",
            lambda value: str(value) if value else None,
        ),
    )
    for key, sql, serializer in field_specs:
        if key not in patch:
            continue
        assignments.append(sql)
        params.append(serializer(patch[key]))

    if not assignments:
        return

    params.append(course_id)
    query = f"""
        update app.courses
        set {", ".join(assignments)}
        where id = %s::uuid
    """
    async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
        await cur.execute(query, params)


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
    conn: Any | None = None,
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

    async def _execute(active_conn: Any) -> CourseRow | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def get_studio_course(
    course_id: str,
    *,
    conn: Any | None = None,
) -> CourseRow | None:
    query = f"""
        select {_STUDIO_COURSE_COLUMNS}
        from app.courses as c
        where c.id = %s::uuid
        limit 1
    """

    async def _execute(active_conn: Any) -> CourseRow | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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


async def get_lesson_view_course_pricing(
    course_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            c.id::text as course_id,
            c.price_amount_cents,
            c.price_currency,
            c.sellable,
            c.required_enrollment_source::text as required_enrollment_source,
            c.active_stripe_price_id
        from app.courses as c
        where c.id = %s::uuid
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


def _course_entry_lookup_clause(course_id_or_slug: str) -> tuple[str, tuple[Any, ...]]:
    normalized = str(course_id_or_slug or "").strip()
    if not normalized:
        raise ValueError("course_id_or_slug is required")
    try:
        UUID(normalized)
    except ValueError:
        return "c.slug = %s", (normalized,)
    return "c.id = %s::uuid", (normalized,)


async def get_course_entry_view_base(
    course_id_or_slug: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    where_clause, params = _course_entry_lookup_clause(course_id_or_slug)
    query = f"""
        select
            c.id::text as id,
            c.slug,
            c.title,
            c.required_enrollment_source::text as required_enrollment_source,
            c.sellable,
            c.price_amount_cents,
            c.price_currency,
            c.active_stripe_price_id,
            c.content_ready,
            c.visibility::text as visibility,
            c.cover_media_id::text as cover_media_id,
            cover.id::text as cover_asset_id,
            cover.state::text as cover_state,
            cover.media_type::text as cover_media_type,
            cover.purpose::text as cover_purpose,
            cpc.description
        from app.courses as c
        join app.course_public_content as cpc
          on cpc.course_id = c.id
        left join app.media_assets as cover
          on cover.id = c.cover_media_id
        where {where_clause}
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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
            c.required_enrollment_source::text as required_enrollment_source,
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
        select
            {_COURSE_COLUMNS},
            cpc.description
        from app.courses as c
        join app.course_public_content as cpc
          on cpc.course_id = c.id
        {where_sql}
        order by c.slug asc
        {limit_sql}
    """

    async with pool.connection() as conn:  # type: ignore
        await _assert_course_public_content_invariant(conn)
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_studio_courses(
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
        select {_STUDIO_COURSE_COLUMNS}
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


_PUBLIC_DISCOVERABLE_COURSE_SQL = """
    c.content_ready is true
    and (
      c.sellable is true
      or (
        c.sellable is false
        and coalesce(c.price_amount_cents, 0) <= 0
      )
    )
"""


async def list_public_courses(
    *,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[CourseRow]:
    clauses = [
        "c.visibility = 'public'::app.course_visibility",
        _PUBLIC_DISCOVERABLE_COURSE_SQL,
    ]
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
    group_position: int | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []
    if search:
        pattern = f"%{search}%"
        clauses.append("(cds.title ilike %s or cds.slug ilike %s)")
        params.extend([pattern, pattern])
    if group_position is not None:
        clauses.append("cds.group_position = %s")
        params.append(int(group_position))

    limit_sql = "limit %s" if limit is not None else ""
    if limit is not None:
        params.append(int(limit))

    query = f"""
        select {_PUBLIC_DISCOVERY_COLUMNS}
        from app.course_discovery_surface as cds
        join app.courses as c
          on c.id = cds.id
        left join app.profiles as p
          on p.user_id = c.teacher_id
        join app.course_public_content as cpc
          on cpc.course_id = cds.id
        where {_PUBLIC_DISCOVERABLE_COURSE_SQL}
        {"and " + " and ".join(clauses) if clauses else ""}
        order by cds.slug asc
        {limit_sql}
    """

    async with pool.connection() as conn:  # type: ignore
        await _assert_course_public_content_invariant(conn)
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


async def list_course_entry_lessons(
    course_id: str,
    *,
    conn: Any | None = None,
) -> Sequence[LessonRow]:
    query = """
        select
            lss.id::text as id,
            lss.lesson_title,
            lss.position
        from app.lesson_structure_surface as lss
        where lss.course_id = %s::uuid
        order by lss.position asc, lss.id asc
    """

    async def _execute(active_conn: Any) -> list[LessonRow]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
        return [dict(row) for row in rows]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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

    query = f"""
        select
            cd.id,
            cd.slug,
            cd.title,
            c.teacher_id,
            nullif(btrim(p.display_name), '') as teacher_display_name,
            cd.course_group_id,
            cd.group_position,
            cd.cover_media_id,
            cd.price_amount_cents,
            cd.drip_enabled,
            cd.drip_interval_days,
            cd.required_enrollment_source::text as required_enrollment_source,
            c.sellable,
            cpc.description,
            cd.lesson_id,
            cd.lesson_title,
            cd.lesson_position
        from app.course_detail_surface as cd
        join app.courses as c
          on c.id = cd.id
        left join app.profiles as p
          on p.user_id = c.teacher_id
        join app.course_public_content as cpc
          on cpc.course_id = cd.id
        where {_PUBLIC_DISCOVERABLE_COURSE_SQL}
          and {" and ".join(clauses)}
        order by cd.lesson_position asc nulls last, cd.lesson_id asc nulls last
    """

    async with pool.connection() as conn:  # type: ignore
        await _assert_course_public_content_invariant(conn)
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def create_course(payload: dict[str, Any]) -> CourseRow:
    course_id = str(payload.get("id") or uuid4())
    course_group_id = str(payload["course_group_id"])
    query = """
        insert into app.courses (
            id,
            teacher_id,
            title,
            slug,
            course_group_id,
            group_position,
            required_enrollment_source,
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
            %s::app.course_enrollment_source,
            %s,
            %s,
            %s,
            %s::uuid
        )
            returning id
    """
    try:
        async with pool.connection() as conn:  # type: ignore
            await _acquire_course_family_locks(conn, (course_group_id,))
            append_group_position = await _get_course_family_append_position(
                conn,
                course_group_id,
            )
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    query,
                    (
                        course_id,
                        str(payload["teacher_id"]),
                        payload["title"],
                        payload["slug"],
                        course_group_id,
                        append_group_position,
                        payload.get("required_enrollment_source"),
                        payload.get("price_amount_cents"),
                        payload["drip_enabled"],
                        payload["drip_interval_days"],
                        str(payload["cover_media_id"])
                        if payload.get("cover_media_id")
                        else None,
                    ),
                )
                await cur.fetchone()
                await conn.commit()
        row = await get_course(course_id=course_id)
    except PsycopgError as exc:
        context = _course_create_db_log_context(payload, exc)
        logger.exception("Course create database error", extra=context)
        raise CourseCreateDatabaseError(
            title=context["course_create_title"],
            slug=context["course_create_slug"],
            cause=exc,
        ) from exc
    if row is None:
        raise RuntimeError("created course was not returned")
    return row


async def update_course(course_id: str, patch: dict[str, Any]) -> CourseRow | None:
    async with pool.connection() as conn:  # type: ignore
        await _acquire_course_transition_lock(
            conn,
            scope="course",
            key=course_id,
        )
        current_row = await _get_course_transition_row(conn, course_id)
        if current_row is None:
            return None

        requested_course_group_id = (
            str(patch["course_group_id"])
            if "course_group_id" in patch and patch["course_group_id"] is not None
            else None
        )
        requested_group_position = (
            int(patch["group_position"])
            if "group_position" in patch and patch["group_position"] is not None
            else None
        )
        target_course_group_id = requested_course_group_id or str(
            current_row["course_group_id"]
        )

        if "course_group_id" in patch or "group_position" in patch:
            await _acquire_course_family_locks(
                conn,
                (
                    str(current_row["course_group_id"]),
                    target_course_group_id,
                ),
            )

        locked_row = await _get_course_transition_row(
            conn,
            course_id,
            for_update=True,
        )
        if locked_row is None:
            return None

        current_course_group_id = str(locked_row["course_group_id"])
        current_group_position = int(locked_row["group_position"])
        transition_applied = False

        if target_course_group_id != current_course_group_id:
            append_group_position = await _get_course_family_append_position(
                conn,
                target_course_group_id,
            )
            if (
                requested_group_position is not None
                and requested_group_position != append_group_position
            ):
                raise ValueError(
                    "group_position must append to the target course family"
                )
            await _move_course_to_family_end(
                conn,
                course_id=course_id,
                source_course_group_id=current_course_group_id,
                source_group_position=current_group_position,
                target_course_group_id=target_course_group_id,
            )
            transition_applied = True
        elif (
            requested_group_position is not None
            and requested_group_position != current_group_position
        ):
            await _reorder_course_within_family(
                conn,
                course_id=course_id,
                course_group_id=current_course_group_id,
                current_position=current_group_position,
                new_position=requested_group_position,
            )
            transition_applied = True

        metadata_patch = {
            key: value
            for key, value in patch.items()
            if key not in {"course_group_id", "group_position"}
        }
        await _apply_course_metadata_patch(
            conn,
            course_id=course_id,
            patch=metadata_patch,
        )

        if transition_applied or metadata_patch:
            await conn.commit()
        else:
            await conn.rollback()

    row = await get_course(course_id=course_id)
    if row is None:
        return None
    return row


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
    stripe_product_id: str | None,
    active_stripe_price_id: str | None,
    requires_monetization: bool,
) -> CourseRow | None:
    query = """
        update app.courses
        set content_ready = true,
            visibility = 'public'::app.course_visibility,
            stripe_product_id = %s,
            active_stripe_price_id = %s,
            required_enrollment_source = case
                when %s then 'purchase'::app.course_enrollment_source
                else 'intro'::app.course_enrollment_source
            end,
            sellable = %s
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
                    requires_monetization,
                    requires_monetization,
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
            c.sellable,
            c.required_enrollment_source::text as required_enrollment_source
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
    async with pool.connection() as conn:  # type: ignore
        await _acquire_course_transition_lock(
            conn,
            scope="course",
            key=course_id,
        )
        current_row = await _get_course_transition_row(conn, course_id)
        if current_row is None:
            return False

        await _acquire_course_family_locks(
            conn,
            (str(current_row["course_group_id"]),),
        )
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                with deleted as (
                    delete from app.courses
                    where id = %s::uuid
                    returning course_group_id, group_position
                ),
                shifted as (
                    update app.courses as c
                       set group_position = c.group_position - 1
                      from deleted
                     where c.course_group_id = deleted.course_group_id
                       and c.group_position > deleted.group_position
                    returning c.id
                )
                select exists(select 1 from deleted)
                """,
                (course_id,),
            )
            row = await cur.fetchone()
        await conn.commit()
    return bool(row[0]) if row else False


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


async def list_course_ownership_rows(
    course_ids: Sequence[str],
) -> Sequence[dict[str, Any]]:
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


async def get_course_public_content(course_id: str) -> dict[str, Any]:
    query = """
        select
            cpc.course_id,
            cpc.description
        from app.course_public_content as cpc
        where cpc.course_id = %s::uuid
        limit 1
    """
    async with pool.connection() as conn:  # type: ignore
        await _assert_course_public_content_invariant(conn)
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
    if row is None:
        raise RuntimeError(_MISSING_COURSE_PUBLIC_CONTENT_ERROR)
    return dict(row)


async def upsert_course_public_content(
    course_id: str,
    *,
    description: str,
) -> dict[str, Any]:
    normalized_description = str(description)
    query = """
        update app.course_public_content
        set description = %s
        where course_id = %s::uuid
        returning
            course_id,
            description
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (normalized_description, course_id),
            )
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        raise RuntimeError(_MISSING_COURSE_PUBLIC_CONTENT_ERROR)
    return dict(row)


async def list_my_courses(user_id: str) -> Sequence[CourseRow]:
    query = f"""
        select distinct on (c.id)
            {_COURSE_COLUMNS},
            cpc.description
        from app.course_enrollments as ce
        join app.courses as c
          on c.id = ce.course_id
        join app.course_public_content as cpc
          on cpc.course_id = c.id
        where ce.user_id = %s
        order by c.id, ce.granted_at desc
    """
    async with pool.connection() as conn:  # type: ignore
        await _assert_course_public_content_invariant(conn)
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id,))
            rows = await cur.fetchall()
    return [dict(row) for row in rows]


async def list_intro_selection_progress_rows(
    *,
    user_id: str,
    conn: Any | None = None,
) -> list[dict[str, Any]]:
    query = """
        select
            ce.id as enrollment_id,
            ce.course_id,
            ce.current_unlock_position,
            coalesce(max(l.position), 0)::integer as max_lesson_position,
            count(l.id)::integer as lesson_count,
            count(lc.id)::integer as completed_lesson_count
        from app.course_enrollments as ce
        join app.courses as c
          on c.id = ce.course_id
        left join app.lessons as l
          on l.course_id = ce.course_id
        left join app.lesson_completions as lc
          on lc.user_id = ce.user_id
         and lc.course_id = ce.course_id
         and lc.lesson_id = l.id
        where ce.user_id = %s::uuid
          and c.required_enrollment_source = 'intro'::app.course_enrollment_source
          and ce.source = c.required_enrollment_source
        group by
            ce.id,
            ce.course_id,
            ce.current_unlock_position,
            ce.granted_at
        order by ce.granted_at asc, ce.id asc
    """

    async def _execute(active_conn: Any) -> list[dict[str, Any]]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id,))
            rows = await cur.fetchall()
        return [dict(row) for row in rows]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        rows = await _execute(active_conn)
        await active_conn.commit()
        return rows


async def get_active_intro_drip_state(
    user_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any]:
    query = """
        with intro_enrollments as (
            select
                ce.id,
                ce.course_id::text as active_course_id,
                ce.current_unlock_position,
                ce.drip_started_at,
                ce.granted_at,
                coalesce(max(l.position), 0)::integer as max_lesson_position
            from app.course_enrollments as ce
            join app.courses as c
              on c.id = ce.course_id
            left join app.lessons as l
              on l.course_id = ce.course_id
            where ce.user_id = %s::uuid
              and c.required_enrollment_source = 'intro'::app.course_enrollment_source
              and ce.source = c.required_enrollment_source
            group by
                ce.id,
                ce.course_id,
                ce.current_unlock_position,
                ce.drip_started_at,
                ce.granted_at
        ),
        active_intro_drip as (
            select
                active_course_id,
                current_unlock_position,
                max_lesson_position,
                drip_started_at
            from intro_enrollments
            where current_unlock_position < max_lesson_position
            order by granted_at asc, id asc
            limit 1
        )
        select
            exists(select 1 from active_intro_drip) as is_in_any_intro_drip,
            (
                select active_course_id
                from active_intro_drip
            ) as active_course_id,
            (
                select current_unlock_position
                from active_intro_drip
            ) as current_unlock_position,
            (
                select max_lesson_position
                from active_intro_drip
            ) as max_lesson_position,
            (
                select drip_started_at
                from active_intro_drip
            ) as drip_started_at
    """

    async def _execute(active_conn: Any) -> dict[str, Any]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id,))
            row = await cur.fetchone()
        return dict(row) if row else {"is_in_any_intro_drip": False}

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def get_course_enrollment(
    user_id: str,
    course_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            ce.id,
            ce.user_id,
            ce.course_id,
            ce.source::text as source,
            ce.granted_at,
            ce.drip_started_at,
            ce.current_unlock_position,
            app.compute_course_next_unlock_at(
                ce.course_id,
                ce.drip_started_at,
                ce.current_unlock_position
            ) as next_unlock_at
        from app.course_enrollments as ce
        where ce.user_id = %s
          and ce.course_id = %s
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, course_id))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def get_course_entry_enrollment(
    user_id: str,
    course_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            true as enrollment_exists,
            ce.id::text as enrollment_id,
            ce.drip_started_at,
            ce.current_unlock_position
        from app.course_enrollments as ce
        where ce.user_id = %s::uuid
          and ce.course_id = %s::uuid
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, course_id))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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


async def get_lesson_view_lesson_shell(
    lesson_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            l.id::text as id,
            l.course_id::text as course_id,
            l.lesson_title,
            l.position
        from app.lessons as l
        where l.id = %s::uuid
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def get_lesson_view_navigation(
    lesson_id: str,
    *,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        with target as (
            select
                l.id,
                l.course_id
            from app.lessons as l
            where l.id = %s::uuid
            limit 1
        ),
        ordered_lessons as (
            select
                l.id,
                l.course_id,
                lag(l.id) over (
                    partition by l.course_id
                    order by l.position asc, l.id asc
                ) as previous_lesson_id,
                lead(l.id) over (
                    partition by l.course_id
                    order by l.position asc, l.id asc
                ) as next_lesson_id
            from app.lessons as l
            join target as t
              on t.course_id = l.course_id
        )
        select
            t.id::text as lesson_id,
            t.course_id::text as course_id,
            ol.previous_lesson_id::text as previous_lesson_id,
            ol.next_lesson_id::text as next_lesson_id
        from target as t
        join ordered_lessons as ol
          on ol.id = t.id
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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
                lcs.content_document,
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


async def list_studio_course_lessons(
    course_id: str,
    *,
    conn: Any | None = None,
) -> Sequence[LessonRow]:
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

    async def _execute(active_conn: Any) -> Sequence[LessonRow]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
        return [dict(row) for row in rows]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def list_course_custom_drip_lesson_offsets(
    course_id: str,
    *,
    conn: Any | None = None,
) -> Sequence[dict[str, Any]]:
    query = """
        select
            offsets.lesson_id,
            offsets.unlock_offset_days
        from app.course_custom_drip_lesson_offsets as offsets
        join app.lessons as l
          on l.id = offsets.lesson_id
        where offsets.course_id = %s::uuid
        order by l.position asc, l.id asc
    """

    async def _execute(active_conn: Any) -> Sequence[dict[str, Any]]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            rows = await cur.fetchall()
        return [dict(row) for row in rows]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def course_schedule_is_locked(
    course_id: str,
    *,
    conn: Any | None = None,
) -> bool:
    query = """
        select exists (
            select 1
            from app.course_enrollments
            where course_id = %s::uuid
        )
    """

    async def _execute(active_conn: Any) -> bool:
        async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id,))
            row = await cur.fetchone()
        return bool(row[0]) if row else False

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


async def replace_course_drip_authoring(
    course_id: str,
    *,
    mode: str,
    legacy_drip_interval_days: int | None,
    custom_schedule_rows: Sequence[dict[str, Any]],
) -> CourseRow | None:
    async with pool.connection() as conn:  # type: ignore
        await _acquire_course_transition_lock(
            conn,
            scope="course",
            key=course_id,
        )
        locked_row = await _get_course_transition_row(
            conn,
            course_id,
            for_update=True,
        )
        if locked_row is None:
            return None
        if await course_schedule_is_locked(course_id, conn=conn):
            await conn.rollback()
            raise CourseScheduleLockedError(course_id)

        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            if mode == "custom_lesson_offsets":
                await cur.execute(
                    """
                    update app.courses
                    set drip_enabled = false,
                        drip_interval_days = null
                    where id = %s::uuid
                    """,
                    (course_id,),
                )
                await cur.execute(
                    """
                    insert into app.course_custom_drip_configs (course_id)
                    values (%s::uuid)
                    on conflict (course_id) do nothing
                    """,
                    (course_id,),
                )
                await cur.execute(
                    """
                    delete from app.course_custom_drip_lesson_offsets
                    where course_id = %s::uuid
                    """,
                    (course_id,),
                )
                for row in custom_schedule_rows:
                    await cur.execute(
                        """
                        insert into app.course_custom_drip_lesson_offsets (
                            course_id,
                            lesson_id,
                            unlock_offset_days
                        )
                        values (
                            %s::uuid,
                            %s::uuid,
                            %s
                        )
                        """,
                        (
                            course_id,
                            str(row["lesson_id"]),
                            int(row["unlock_offset_days"]),
                        ),
                    )
            elif mode == "legacy_uniform_drip":
                await cur.execute(
                    """
                    delete from app.course_custom_drip_configs
                    where course_id = %s::uuid
                    """,
                    (course_id,),
                )
                await cur.execute(
                    """
                    update app.courses
                    set drip_enabled = true,
                        drip_interval_days = %s
                    where id = %s::uuid
                    """,
                    (legacy_drip_interval_days, course_id),
                )
            elif mode == "no_drip_immediate_access":
                await cur.execute(
                    """
                    delete from app.course_custom_drip_configs
                    where course_id = %s::uuid
                    """,
                    (course_id,),
                )
                await cur.execute(
                    """
                    update app.courses
                    set drip_enabled = false,
                        drip_interval_days = null
                    where id = %s::uuid
                    """,
                    (course_id,),
                )
            else:
                await conn.rollback()
                raise ValueError("Unsupported studio course drip authoring mode")
        await conn.commit()

    return await get_studio_course(course_id)


async def list_course_publish_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    query = f"""
        select
            l.id,
            l.course_id,
            l.lesson_title,
            l.position,
            lc.content_document is not null as has_content,
            coalesce(
                lc.content_document,
                {_EMPTY_LESSON_DOCUMENT_SQL}
            ) as content_document
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


async def get_lesson(
    lesson_id: str,
    *,
    conn: Any | None = None,
) -> LessonRow | None:
    query = f"""
        select {_lesson_columns(include_content=True)}
        from app.lessons as l
        left join app.lesson_contents as lc
          on lc.lesson_id = l.id
        where l.id = %s
        limit 1
    """

    async def _execute(active_conn: Any) -> LessonRow | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (lesson_id,))
            row = await cur.fetchone()
        return dict(row) if row else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)


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
    query = f"""
        select
            l.id as lesson_id,
            l.course_id,
            coalesce(
                lc.content_document,
                {_EMPTY_LESSON_DOCUMENT_SQL}
            ) as content_document
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


async def update_lesson_document_if_current(
    lesson_id: str,
    content_document: dict[str, Any],
    *,
    expected_content_document: dict[str, Any],
) -> dict[str, Any] | None:
    query = f"""
        with target_lesson as (
            select id
            from app.lessons
            where id = %s::uuid
        ),
        current_content as (
            select content_document, content_markdown
            from app.lesson_contents
            where lesson_id = %s::uuid
        ),
        updated_content as (
            insert into app.lesson_contents (
                lesson_id,
                content_document,
                content_markdown
            )
            select
                target_lesson.id,
                %s,
                coalesce(
                    (select current_content.content_markdown from current_content),
                    ''
                )
            from target_lesson
            where coalesce(
                (select current_content.content_document from current_content),
                {_EMPTY_LESSON_DOCUMENT_SQL}
            ) = %s
            on conflict (lesson_id)
            do update set content_document = excluded.content_document
            where coalesce(
                app.lesson_contents.content_document,
                {_EMPTY_LESSON_DOCUMENT_SQL}
            ) = %s
            returning lesson_id, content_document
        )
        select lesson_id, content_document
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
                    Jsonb(content_document),
                    Jsonb(expected_content_document),
                    Jsonb(expected_content_document),
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
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
            existing_ids = [str(row["id"]) for row in rows if row.get("id") is not None]
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
    conn: Any | None = None,
) -> LessonRow:
    new_lesson_id = str(uuid4())

    async def _execute(active_conn: Any) -> LessonRow:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                insert into app.lessons (id, course_id, lesson_title, position)
                values (%s::uuid, %s::uuid, %s, %s)
                returning id, course_id, lesson_title, position
                """,
                (new_lesson_id, course_id, lesson_title, position),
            )
            row = await cur.fetchone()
        if row is None:
            raise RuntimeError("created lesson structure was not returned")
        return dict(row)

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        row = await _execute(active_conn)
        await active_conn.commit()
        return row


async def create_custom_drip_row(
    *,
    course_id: str,
    lesson_id: str,
    unlock_offset_days: int,
    conn: Any | None = None,
) -> None:
    query = """
        insert into app.course_custom_drip_lesson_offsets (
            course_id,
            lesson_id,
            unlock_offset_days
        )
        values (
            %s::uuid,
            %s::uuid,
            %s
        )
    """

    async def _execute(active_conn: Any) -> None:
        async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (course_id, lesson_id, unlock_offset_days),
            )

    if conn is not None:
        await _execute(conn)
        return

    async with pool.connection() as active_conn:  # type: ignore
        await _execute(active_conn)
        await active_conn.commit()


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
    conn: Any | None = None,
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
            ce.current_unlock_position,
            app.compute_course_next_unlock_at(
                ce.course_id,
                ce.drip_started_at,
                ce.current_unlock_position
            ) as next_unlock_at
        from app.canonical_create_course_enrollment(
            %s::uuid,
            %s::uuid,
            %s::uuid,
            %s::app.course_enrollment_source,
            clock_timestamp()
        ) as ce
    """

    async def _execute(active_conn: Any) -> dict[str, Any]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (enrollment_id, user_id, course_id, source))
            row = await cur.fetchone()
        if row is None:
            raise RuntimeError("canonical course enrollment was not returned")
        return dict(row)

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        row = await _execute(active_conn)
        await active_conn.commit()
        return row


async def revoke_course_enrollment(
    user_id: str,
    course_id: str,
    *,
    excluding_order_id: str | None = None,
    conn: Any | None = None,
) -> bool:
    async def _execute(active_conn: Any) -> bool:
        if await _has_remaining_paid_course_purchase(
            user_id,
            course_id,
            excluding_order_id=excluding_order_id,
            conn=active_conn,
        ):
            return False

        async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                delete from app.course_enrollments
                where user_id = %s::uuid
                  and course_id = %s::uuid
                  and source = 'purchase'::app.course_enrollment_source
                """,
                (user_id, course_id),
            )
            deleted = cur.rowcount > 0
        return deleted

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        deleted = await _execute(active_conn)
        await active_conn.commit()
        return deleted


async def _has_remaining_paid_course_purchase(
    user_id: str,
    course_id: str,
    *,
    excluding_order_id: str | None = None,
    conn: Any | None = None,
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

    async def _execute(active_conn: Any) -> bool:
        async with active_conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                direct_query,
                (user_id, course_id, excluding_order_id, excluding_order_id),
            )
            if await cur.fetchone() is not None:
                return True

            await cur.execute("select to_regclass('app.course_bundle_courses')")
            bundle_table = await cur.fetchone()
            if not bundle_table or bundle_table[0] is None:
                return False

            await cur.execute(
                bundle_query,
                (user_id, course_id, excluding_order_id, excluding_order_id),
            )
            return await cur.fetchone() is not None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        return await _execute(active_conn)
