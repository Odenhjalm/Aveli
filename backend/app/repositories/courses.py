from __future__ import annotations

from typing import Any, Mapping, Sequence

from psycopg import errors
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from ..db import get_conn, pool


CourseRow = dict[str, Any]
ModuleRow = dict[str, Any]
LessonRow = dict[str, Any]

_FULL_COURSE_COLUMNS = """
        id,
        slug,
        title,
        description,
        cover_url,
        cover_media_id,
        video_url,
        branch,
        is_free_intro,
        price_amount_cents,
        currency,
        stripe_product_id,
        stripe_price_id,
        is_published,
        created_by,
        created_at,
        updated_at
    """

_FULL_COURSE_COLUMNS_WITH_ALIAS = _FULL_COURSE_COLUMNS.replace(
    "\n        ",
    "\n        c.",
)

_BASE_COURSE_UPDATE_COLUMNS = {
    "title",
    "slug",
    "description",
    "is_free_intro",
    "price_amount_cents",
    "is_published",
}


def _legacy_course_columns(alias: str | None = None) -> str:
    prefix = f"{alias}." if alias else ""
    base_columns = [
        "id",
        "slug",
        "title",
        "description",
        "cover_url",
        "video_url",
        "branch",
        "is_free_intro",
        "is_published",
        "created_by",
        "created_at",
        "updated_at",
    ]
    column_lines = [f"{prefix}{column}" for column in base_columns]
    cover_index = base_columns.index("cover_url") + 1
    column_lines.insert(cover_index, "NULL::uuid AS cover_media_id")
    price_source = f"{prefix}price_cents"
    column_lines.extend(
        [
            f"COALESCE({price_source}, 0)::int AS price_amount_cents",
            "'sek'::text AS currency",
            "NULL::text AS stripe_product_id",
            "NULL::text AS stripe_price_id",
        ]
    )
    return ",\n        ".join(column_lines)


def _coerce_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "1", "yes", "y", "on"}:
            return True
        if lowered in {"false", "0", "no", "n", "off"}:
            return False
    return bool(value)


def _coerce_int(value: Any) -> int | None:
    if value in (None, ""):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


async def get_course(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> CourseRow | None:
    if not course_id and not slug:
        raise ValueError("course_id or slug is required.")

    clauses: list[str] = []
    params: list[Any] = []
    if course_id:
        clauses.append("id = %s")
        params.append(course_id)
    if slug:
        clauses.append("slug = %s")
        params.append(slug)

    where_clause = " AND ".join(clauses)
    query = f"""
        SELECT {_FULL_COURSE_COLUMNS}
        FROM app.courses
        WHERE {where_clause}
        LIMIT 1
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, params)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_query = f"""
                    SELECT {_legacy_course_columns()}
                    FROM app.courses
                    WHERE {where_clause}
                    LIMIT 1
                """
                await cur.execute(fallback_query, params)
            return await cur.fetchone()


async def get_course_by_slug(slug: str) -> CourseRow | None:
    if not slug:
        return None
    normalized = slug.strip().lower()
    if not normalized:
        return None
    candidates: list[str] = [normalized]
    base_slug = normalized.split("-", 1)[0]
    if base_slug and base_slug != normalized:
        candidates.append(base_slug)
    seen: set[str] = set()
    for candidate in candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        row = await get_course(slug=candidate)
        if row:
            return row
    if base_slug:
        row = await _get_course_by_slug_prefix(base_slug)
        if row:
            return row
    return None


async def _get_course_by_slug_prefix(slug_base: str) -> CourseRow | None:
    pattern = f"{slug_base}%"
    query = f"""
        SELECT {_FULL_COURSE_COLUMNS}
        FROM app.courses
        WHERE lower(slug) LIKE %s
        ORDER BY updated_at DESC
        LIMIT 1
    """
    params = [pattern]
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, params)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_query = f"""
                    SELECT {_legacy_course_columns()}
                    FROM app.courses
                    WHERE lower(slug) LIKE %s
                    ORDER BY updated_at DESC
                    LIMIT 1
                """
                await cur.execute(fallback_query, params)
            return await cur.fetchone()


async def update_course_stripe_ids(
    course_id: str,
    product_id: str | None,
    price_id: str | None,
) -> None:
    query = """
        UPDATE app.courses
           SET stripe_product_id = %s,
               stripe_price_id = %s,
               updated_at = now()
         WHERE id = %s
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, (product_id, price_id, course_id))
            except errors.UndefinedColumn:
                await conn.rollback()
                return
            await conn.commit()


async def update_course_price_cents(
    course_id: str,
    amount_cents: int,
    currency: str = "sek",
) -> None:
    resolved_amount = _coerce_int(amount_cents)
    if resolved_amount is None:
        raise ValueError("amount_cents is required")
    query = """
        UPDATE app.courses
           SET price_amount_cents = %s,
               currency = %s,
               updated_at = now()
         WHERE id = %s
    """
    normalized_currency = (currency or "sek").lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (resolved_amount, normalized_currency, course_id),
            )
            await conn.commit()


async def list_courses(
    *,
    teacher_id: str | None = None,
    status: str | None = None,
    limit: int | None = None,
    published_only: bool | None = None,
    free_intro: bool | None = None,
    search: str | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []

    if teacher_id:
        clauses.append("created_by = %s")
        params.append(teacher_id)

    if status:
        status_map = {
            "published": True,
            "draft": False,
            "unpublished": False,
        }
        normalized = status.lower()
        if normalized in status_map:
            clauses.append("is_published = %s")
            params.append(status_map[normalized])

    if published_only is True:
        clauses.append("is_published = true")
    elif published_only is False:
        clauses.append("is_published = false")

    if free_intro is not None:
        clauses.append("is_free_intro = %s")
        params.append(free_intro)

    if search:
        clauses.append("(lower(title) LIKE %s OR lower(description) LIKE %s)")
        pattern = f"%{search.lower()}%"
        params.extend([pattern, pattern])

    where_sql = f" WHERE {' AND '.join(clauses)}" if clauses else ""
    query = f"""
        SELECT {_FULL_COURSE_COLUMNS}
        FROM app.courses
        {where_sql}
        ORDER BY updated_at DESC
    """

    if limit is not None:
        limit_value = _coerce_int(limit)
        if limit_value is None:
            raise ValueError("limit must be an integer.")
        query += " LIMIT %s"
        params.append(limit_value)

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, params)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_query = query.replace(_FULL_COURSE_COLUMNS, _legacy_course_columns())
                await cur.execute(fallback_query, params)
            return await cur.fetchall()


async def list_public_courses(
    *,
    published_only: bool = True,
    free_intro: bool | None = None,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[CourseRow]:
    clauses: list[str] = []
    params: list[Any] = []

    if published_only:
        clauses.append("is_published = true")
    if free_intro is not None:
        clauses.append("is_free_intro = %s")
        params.append(free_intro)
    if search:
        clauses.append("(lower(title) LIKE %s OR lower(description) LIKE %s)")
        pattern = f"%{search.lower()}%"
        params.extend([pattern, pattern])

    query = f"""
        SELECT {_FULL_COURSE_COLUMNS}
        FROM app.courses
    """
    if clauses:
        query += " WHERE " + " AND ".join(clauses)
    query += " ORDER BY created_at DESC"
    if limit is not None:
        limit_value = _coerce_int(limit)
        if limit_value is None:
            raise ValueError("limit must be an integer.")
        query += " LIMIT %s"
        params.append(limit_value)

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, params)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_query = query.replace(_FULL_COURSE_COLUMNS, _legacy_course_columns())
                await cur.execute(fallback_query, params)
            return await cur.fetchall()


async def create_course(data: Mapping[str, Any]) -> CourseRow:
    required_fields = ("title", "created_by")
    missing = [field for field in required_fields if not data.get(field)]
    if missing:
        raise ValueError(f"Missing required course fields: {', '.join(missing)}")

    columns = ["title", "created_by"]
    placeholders = ["%s", "%s"]
    values: list[Any] = [data["title"], data["created_by"]]

    optional_fields: list[tuple[str, Any]] = [
        ("slug", data.get("slug")),
        ("description", data.get("description")),
        ("video_url", data.get("video_url")),
        ("branch", data.get("branch")),
        ("currency", data.get("currency")),
    ]

    bool_fields = {
        "is_free_intro": _coerce_bool(data.get("is_free_intro")),
        "is_published": _coerce_bool(data.get("is_published")),
    }
    price_amount_value = _coerce_int(data.get("price_amount_cents"))
    if price_amount_value is None:
        price_amount_value = _coerce_int(data.get("price_cents"))
    int_fields = {
        "price_amount_cents": price_amount_value,
    }

    for column, value in optional_fields:
        if value is not None:
            columns.append(column)
            placeholders.append("%s")
            values.append(value)

    for column, value in {**bool_fields, **int_fields}.items():
        if value is not None:
            columns.append(column)
            placeholders.append("%s")
            values.append(value)

    columns_sql = ", ".join(columns)
    placeholders_sql = ", ".join(placeholders)
    query = f"""
        INSERT INTO app.courses ({columns_sql})
        VALUES ({placeholders_sql})
        RETURNING {_FULL_COURSE_COLUMNS}
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, values)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_pairs = [
                    (column, values[idx])
                    for idx, column in enumerate(columns)
                    if column
                    not in {
                        "video_url",
                        "branch",
                        "currency",
                        "price_amount_cents",
                    }
                ]
                if "price_amount_cents" in columns:
                    idx = columns.index("price_amount_cents")
                    fallback_pairs.append(("price_cents", values[idx]))
                fallback_columns = [column for column, _ in fallback_pairs]
                fallback_values = [value for _, value in fallback_pairs]
                fallback_query = f"""
                    INSERT INTO app.courses ({", ".join(fallback_columns)})
                    VALUES ({", ".join(["%s"] * len(fallback_columns))})
                    RETURNING {_legacy_course_columns()}
                """
                await cur.execute(fallback_query, fallback_values)
            row = await cur.fetchone()
            await conn.commit()
            return row or {}


async def update_course(
    course_id: str,
    data: Mapping[str, Any],
) -> CourseRow | None:
    if not data:
        return await get_course(course_id=course_id)

    updates: list[tuple[str, Any]] = []

    text_columns = (
        "title",
        "slug",
        "description",
        "video_url",
        "branch",
        "currency",
    )
    for column in text_columns:
        if column in data:
            updates.append((column, data[column]))

    if "is_free_intro" in data:
        updates.append(("is_free_intro", _coerce_bool(data.get("is_free_intro"))))
    if "price_amount_cents" in data or "price_cents" in data:
        price_value = None
        if "price_amount_cents" in data:
            price_value = _coerce_int(data.get("price_amount_cents"))
        if price_value is None and "price_cents" in data:
            price_value = _coerce_int(data.get("price_cents"))
        if price_value is not None:
            updates.append(("price_amount_cents", price_value))
    if "is_published" in data:
        updates.append(("is_published", _coerce_bool(data.get("is_published"))))

    if not updates:
        return await get_course(course_id=course_id)

    set_clause = ", ".join(f"{column} = %s" for column, _ in updates)
    params = [value for _, value in updates]
    params.append(course_id)

    query = f"""
        UPDATE app.courses
        SET {set_clause}, updated_at = now()
        WHERE id = %s
        RETURNING {_FULL_COURSE_COLUMNS}
    """

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(query, params)
            except errors.UndefinedColumn:
                await conn.rollback()
                fallback_updates: list[tuple[str, Any]] = []
                for column, value in updates:
                    if column == "price_amount_cents":
                        fallback_updates.append(("price_cents", value))
                    elif column in _BASE_COURSE_UPDATE_COLUMNS - {"price_amount_cents"}:
                        fallback_updates.append((column, value))
                if not fallback_updates:
                    raise
                fallback_clause = ", ".join(f"{column} = %s" for column, _ in fallback_updates)
                fallback_params = [value for _, value in fallback_updates]
                fallback_params.append(course_id)
                fallback_query = f"""
                    UPDATE app.courses
                    SET {fallback_clause}, updated_at = now()
                    WHERE id = %s
                    RETURNING {_legacy_course_columns()}
                """
                await cur.execute(fallback_query, fallback_params)
            row = await cur.fetchone()
            await conn.commit()
            return row


async def clear_course_cover(course_id: str) -> str | None:
    query = """
        WITH previous AS (
          SELECT cover_media_id
          FROM app.courses
          WHERE id = %s
        ),
        updated AS (
          UPDATE app.courses
          SET cover_media_id = null,
              cover_url = null,
              updated_at = now()
          WHERE id = %s
          RETURNING id
        )
        SELECT previous.cover_media_id
        FROM previous
        JOIN updated ON true
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id, course_id))
            row = await cur.fetchone()
            await conn.commit()
            return str(row["cover_media_id"]) if row and row.get("cover_media_id") else None


async def delete_course(course_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.courses WHERE id = %s",
                (course_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
            return deleted


async def list_modules(course_id: str) -> Sequence[ModuleRow]:
    query = """
        SELECT
            id,
            course_id,
            title,
            position,
            created_at,
            updated_at
        FROM app.modules
        WHERE course_id = %s
        ORDER BY position
    """
    async with get_conn() as cur:
        await cur.execute(query, (course_id,))
        return await cur.fetchall()


async def get_module(module_id: str) -> ModuleRow | None:
    query = """
        SELECT
            id,
            course_id,
            title,
            position,
            created_at,
            updated_at
        FROM app.modules
        WHERE id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (module_id,))
        return await cur.fetchone()


async def get_module_course_id(module_id: str) -> str | None:
    query = "SELECT course_id FROM app.modules WHERE id = %s"
    async with get_conn() as cur:
        await cur.execute(query, (module_id,))
        row = await cur.fetchone()
    if not row:
        return None
    return row.get("course_id")


async def create_module(
    course_id: str,
    *,
    title: str,
    position: int = 0,
    module_id: str | None = None,
) -> ModuleRow | None:
    if title is None:
        raise ValueError("title is required when creating a module.")

    position_value = _coerce_int(position)
    if position is not None and position_value is None:
        raise ValueError("position must be an integer.")

    resolved_position = position_value if position_value is not None else 0

    if module_id:
        query = """
        INSERT INTO app.modules (id, course_id, title, position)
        VALUES (%s, %s, %s, %s)
        RETURNING id, course_id, title, position, created_at, updated_at
    """
        params = (module_id, course_id, title, resolved_position)
    else:
        query = """
        INSERT INTO app.modules (course_id, title, position)
        VALUES (%s, %s, %s)
        RETURNING id, course_id, title, position, created_at, updated_at
    """
        params = (course_id, title, resolved_position)

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return row


async def upsert_module(
    course_id: str,
    data: Mapping[str, Any],
) -> ModuleRow | None:
    module_id = data.get("id")
    title = data.get("title")
    position = data.get("position")
    position_value = _coerce_int(position)

    if position is not None and position_value is None:
        raise ValueError("position must be an integer.")

    if module_id:
        updates: list[tuple[str, Any]] = []
        if "title" in data:
            updates.append(("title", title))
        if position is not None:
            updates.append(("position", position_value))

        if not updates:
            return await get_module(module_id)

        set_clause = ", ".join(f"{column} = %s" for column, _ in updates)
        params = [value for _, value in updates]
        params.extend([module_id, course_id])

        query = f"""
            UPDATE app.modules
            SET {set_clause}, updated_at = now()
            WHERE id = %s AND course_id = %s
            RETURNING id, course_id, title, position, created_at, updated_at
        """

        async with pool.connection() as conn:  # type: ignore
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(query, params)
                row = await cur.fetchone()
                await conn.commit()
                return row

    if title is None:
        raise ValueError("title is required when creating a module.")

    resolved_position = position_value if position_value is not None else 0
    query = """
        INSERT INTO app.modules (course_id, title, position)
        VALUES (%s, %s, %s)
        RETURNING id, course_id, title, position, created_at, updated_at
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (course_id, title, resolved_position))
            row = await cur.fetchone()
            await conn.commit()
            return row


async def delete_module(module_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.modules WHERE id = %s",
                (module_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
            return deleted


async def list_lessons(module_id: str) -> Sequence[LessonRow]:
    query = """
        SELECT
            id,
            module_id,
            title,
            position,
            is_intro,
            content_markdown,
            created_at,
            updated_at
        FROM app.lessons
        WHERE module_id = %s
        ORDER BY position
    """
    async with get_conn() as cur:
        await cur.execute(query, (module_id,))
        return await cur.fetchall()


async def list_course_lessons(course_id: str) -> Sequence[LessonRow]:
    query = """
        SELECT
            id,
            course_id,
            title,
            position,
            is_intro,
            content_markdown,
            created_at,
            updated_at
        FROM app.lessons
        WHERE course_id = %s
        ORDER BY position
    """
    async with get_conn() as cur:
        await cur.execute(query, (course_id,))
        return await cur.fetchall()


async def get_lesson(lesson_id: str) -> LessonRow | None:
    query = """
        SELECT
            id,
            course_id,
            title,
            position,
            is_intro,
            content_markdown,
            created_at,
            updated_at
        FROM app.lessons
        WHERE id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (lesson_id,))
        return await cur.fetchone()


async def get_lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    query = "SELECT course_id FROM app.lessons WHERE id = %s LIMIT 1"
    async with get_conn() as cur:
        await cur.execute(query, (lesson_id,))
        row = await cur.fetchone()
    if not row:
        return None, None
    return None, row.get("course_id")


async def create_lesson(
    course_id: str,
    *,
    title: str,
    content_markdown: str | None = None,
    position: int = 0,
    is_intro: bool = False,
    lesson_id: str | None = None,
) -> LessonRow | None:
    if title is None:
        raise ValueError("title is required when creating a lesson.")

    position_value = _coerce_int(position)
    if position is not None and position_value is None:
        raise ValueError("position must be an integer.")
    intro_value = _coerce_bool(is_intro) if is_intro is not None else None

    resolved_position = position_value if position_value is not None else 0
    resolved_intro = intro_value if intro_value is not None else False

    if lesson_id:
        query = """
        INSERT INTO app.lessons (id, course_id, title, content_markdown, position, is_intro)
        VALUES (%s, %s, %s, %s, %s, %s)
        RETURNING id, course_id, title, position, is_intro, content_markdown, created_at, updated_at
    """
        params = (
            lesson_id,
            course_id,
            title,
            content_markdown,
            resolved_position,
            resolved_intro,
        )
    else:
        query = """
        INSERT INTO app.lessons (course_id, title, content_markdown, position, is_intro)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id, course_id, title, position, is_intro, content_markdown, created_at, updated_at
    """
        params = (
            course_id,
            title,
            content_markdown,
            resolved_position,
            resolved_intro,
        )

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return row


async def upsert_lesson(
    course_id: str,
    data: Mapping[str, Any],
) -> LessonRow | None:
    lesson_id = data.get("id")
    title = data.get("title")
    content_markdown = data.get("content_markdown")
    position = data.get("position")
    position_value = _coerce_int(position)
    if position is not None and position_value is None:
        raise ValueError("position must be an integer.")
    is_intro = data.get("is_intro")
    intro_value = _coerce_bool(is_intro) if is_intro is not None else None

    if lesson_id:
        updates: list[tuple[str, Any]] = []
        if "title" in data:
            updates.append(("title", title))
        if "content_markdown" in data:
            updates.append(("content_markdown", content_markdown))
        if position is not None:
            updates.append(("position", position_value))
        if is_intro is not None:
            updates.append(("is_intro", intro_value))

        if not updates:
            return await get_lesson(lesson_id)

        set_clause = ", ".join(f"{column} = %s" for column, _ in updates)
        params = [value for _, value in updates]
        params.extend([lesson_id, course_id])

        query = f"""
            UPDATE app.lessons
            SET {set_clause}, updated_at = now()
            WHERE id = %s AND course_id = %s
            RETURNING id, course_id, title, position, is_intro, content_markdown, created_at, updated_at
        """

        async with pool.connection() as conn:  # type: ignore
            async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(query, params)
                row = await cur.fetchone()
                await conn.commit()
                return row

    if title is None:
        raise ValueError("title is required when creating a lesson.")

    resolved_position = position_value if position_value is not None else 0
    resolved_intro = intro_value if intro_value is not None else False

    query = """
        INSERT INTO app.lessons (course_id, title, content_markdown, position, is_intro)
        VALUES (%s, %s, %s, %s, %s)
        RETURNING id, course_id, title, position, is_intro, content_markdown, created_at, updated_at
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                query,
                (
                    course_id,
                    title,
                    content_markdown,
                    resolved_position,
                    resolved_intro,
                ),
            )
            row = await cur.fetchone()
            await conn.commit()
            return row


async def delete_lesson(lesson_id: str) -> bool:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.lessons WHERE id = %s",
                (lesson_id,),
            )
            deleted = cur.rowcount > 0
            await conn.commit()
            return deleted


async def is_course_owner(course_id: str, user_id: str) -> bool:
    query = "SELECT 1 FROM app.courses WHERE id = %s AND created_by = %s LIMIT 1"
    async with get_conn() as cur:
        await cur.execute(query, (course_id, user_id))
        return bool(await cur.fetchone())


async def reorder_lessons(
    course_id: str,
    lesson_ids_in_order: Sequence[str],
) -> None:
    if not lesson_ids_in_order:
        return

    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            for index, lesson_id in enumerate(lesson_ids_in_order):
                await cur.execute(
                    """
                    UPDATE app.lessons
                    SET position = %s, updated_at = now()
                    WHERE id = %s AND course_id = %s
                    """,
                    (index, lesson_id, course_id),
                )
            await conn.commit()


async def list_lesson_media(lesson_id: str) -> Sequence[dict[str, Any]]:
    query = """
        SELECT
          lm.id,
          lm.lesson_id,
          lm.kind,
          CASE
            WHEN ma.id IS NOT NULL THEN
              CASE WHEN ma.state = 'ready' THEN ma.streaming_object_path ELSE NULL END
            ELSE coalesce(mo.storage_path, lm.storage_path)
          END AS storage_path,
          CASE
            WHEN ma.id IS NOT NULL THEN
              CASE WHEN ma.state = 'ready' THEN ma.storage_bucket ELSE NULL END
            ELSE coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media')
          END AS storage_bucket,
          lm.media_id,
          lm.media_asset_id,
          coalesce(ma.duration_seconds, lm.duration_seconds) AS duration_seconds,
          coalesce(
            mo.content_type,
            CASE WHEN ma.state = 'ready' THEN 'audio/mpeg' ELSE NULL END
          ) AS content_type,
          mo.byte_size,
          coalesce(mo.original_name, ma.original_filename) AS original_name,
          ma.state AS media_state,
          ma.ingest_format,
          ma.streaming_format,
          ma.codec,
          ma.error_message,
          lm.created_at
        FROM app.lesson_media lm
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        WHERE lm.lesson_id = %s
        ORDER BY lm.position
    """
    async with get_conn() as cur:
        await cur.execute(query, (lesson_id,))
        return await cur.fetchall()


async def get_lesson_media_access_by_path(
    *,
    storage_path: str,
    storage_bucket: str,
) -> dict[str, Any] | None:
    query = """
        SELECT
          lm.id,
          lm.lesson_id,
          lm.kind,
          coalesce(mo.storage_path, lm.storage_path) AS storage_path,
          coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media') AS storage_bucket,
          l.is_intro,
          c.id AS course_id,
          c.created_by,
          c.is_free_intro,
          c.is_published
        FROM app.lesson_media lm
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.modules m ON m.id = l.module_id
        JOIN app.courses c ON c.id = m.course_id
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        WHERE coalesce(mo.storage_path, lm.storage_path) = %s
          AND coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media') = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (storage_path, storage_bucket))
        return await cur.fetchone()


async def list_home_audio_media(
    user_id: str,
    *,
    include_all_courses: bool,
    limit: int = 20,
) -> Sequence[dict[str, Any]]:
    params: list[Any] = []
    # Home audio access is granted only for course owners, enrolled users, and free/intro lessons.
    # (include_all_courses is intentionally ignored to avoid exposing media without enrollment.)
    opt_in_cte = """
        WITH opted_in AS (
          SELECT
            tpm.media_id AS lesson_media_id,
            tpm.teacher_id
          FROM app.teacher_profile_media tpm
          WHERE tpm.enabled_for_home_player = true
            AND tpm.media_kind = 'lesson_media'
            AND tpm.media_id IS NOT NULL
        )
    """
    enrollment_join = """
        LEFT JOIN app.enrollments e
          ON e.course_id = c.id
         AND e.user_id = %s
         AND e.status = 'active'
    """
    access_clause = """
          AND (
            c.created_by = %s
            OR (
              c.is_published = true
              AND (
                l.is_intro = true
                OR c.is_free_intro = true
                OR e.user_id IS NOT NULL
              )
            )
          )
          AND (lm.media_asset_id IS NULL OR ma.state = 'ready')
    """
    params.append(user_id)  # enrollment join
    params.append(user_id)  # owner check

    query = f"""
        {opt_in_cte}
        SELECT
          lm.id,
          lm.lesson_id,
          lm.kind,
          CASE
            WHEN ma.id IS NOT NULL THEN
              CASE WHEN ma.state = 'ready' THEN ma.streaming_object_path ELSE NULL END
            ELSE coalesce(mo.storage_path, lm.storage_path)
          END AS storage_path,
          CASE
            WHEN ma.id IS NOT NULL THEN
              CASE WHEN ma.state = 'ready' THEN ma.storage_bucket ELSE NULL END
            ELSE coalesce(mo.storage_bucket, lm.storage_bucket, 'lesson-media')
          END AS storage_bucket,
          lm.media_id,
          lm.media_asset_id,
          lm.position,
          coalesce(ma.duration_seconds, lm.duration_seconds) AS duration_seconds,
          lm.created_at,
          coalesce(
            mo.content_type,
            CASE WHEN ma.state = 'ready' THEN 'audio/mpeg' ELSE NULL END
          ) AS content_type,
          mo.byte_size,
          coalesce(mo.original_name, ma.original_filename) AS original_name,
          ma.state AS media_state,
          ma.streaming_format,
          ma.codec,
          l.title AS lesson_title,
          l.is_intro,
          c.id AS course_id,
          c.slug AS course_slug,
          c.title AS course_title,
          c.is_free_intro
        FROM opted_in oi
        JOIN app.lesson_media lm ON lm.id = oi.lesson_media_id
        JOIN app.lessons l ON l.id = lm.lesson_id
        JOIN app.courses c ON c.id = l.course_id
        JOIN app.profiles prof ON prof.user_id = c.created_by
        LEFT JOIN app.media_objects mo ON mo.id = lm.media_id
        LEFT JOIN app.media_assets ma ON ma.id = lm.media_asset_id
        {enrollment_join}
        WHERE oi.teacher_id = c.created_by
          AND lm.kind = 'audio'
          AND (prof.role_v2 = 'teacher' OR prof.is_admin = true)
          AND COALESCE(prof.email, '') NOT ILIKE '%%@example.com'
          {access_clause}
        ORDER BY lm.created_at DESC
        LIMIT %s
    """
    params.append(limit)
    async with get_conn() as cur:
        await cur.execute(query, params)
        return await cur.fetchall()


async def list_my_courses(user_id: str) -> Sequence[CourseRow]:
    query = f"""
        SELECT {_FULL_COURSE_COLUMNS_WITH_ALIAS}
        FROM app.enrollments e
        JOIN app.courses c ON c.id = e.course_id
        WHERE e.user_id = %s
        ORDER BY c.created_at DESC
    """
    async with get_conn() as cur:
        try:
            await cur.execute(query, (user_id,))
        except errors.UndefinedColumn:
            fallback_query = f"""
                SELECT {_legacy_course_columns('c')}
                FROM app.enrollments e
                JOIN app.courses c ON c.id = e.course_id
                WHERE e.user_id = %s
                ORDER BY c.created_at DESC
            """
            await cur.execute(fallback_query, (user_id,))
        return await cur.fetchall()


async def is_enrolled(user_id: str, course_id: str) -> bool:
    query = """
        SELECT 1
        FROM app.enrollments
        WHERE user_id = %s AND course_id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (user_id, course_id))
        return (await cur.fetchone()) is not None


async def enforce_free_intro_enrollment(user_id: str, course_id: str) -> None:
    await ensure_course_enrollment(user_id, course_id, source="free_intro")


async def ensure_course_enrollment(user_id: str, course_id: str, *, source: str = "purchase") -> None:
    source_value = source or "purchase"
    query = """
        INSERT INTO app.enrollments (user_id, course_id, source)
        VALUES (%s, %s, %s)
        ON CONFLICT (user_id, course_id) DO NOTHING
    """
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, course_id, source_value))
            await conn.commit()


async def count_free_intro_enrollments(user_id: str) -> int:
    query = """
        SELECT COUNT(*)::int AS count
        FROM app.enrollments e
        JOIN app.courses c ON c.id = e.course_id
        WHERE e.user_id = %s
          AND e.source = 'free_intro'
          AND c.is_free_intro = true
    """
    async with get_conn() as cur:
        await cur.execute(query, (user_id,))
        row = await cur.fetchone()
    return int((row or {}).get("count") or 0)


async def enroll_free_intro(
    user_id: str,
    course_id: str,
    *,
    free_limit: int,
    has_active_subscription: bool,
) -> dict[str, Any]:
    async with pool.connection() as conn:  # type: ignore
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id, is_free_intro, is_published
                FROM app.courses
                WHERE id = %s
                LIMIT 1
                """,
                (course_id,),
            )
            course_row = await cur.fetchone()
            if not course_row:
                await conn.rollback()
                return {
                    "ok": False,
                    "status": "not_found",
                }
            if not bool(course_row.get("is_free_intro")):
                await conn.rollback()
                return {
                    "ok": False,
                    "status": "not_free_intro",
                }

            await cur.execute(
                """
                SELECT COUNT(*)::int AS count
                  FROM app.enrollments e
                  JOIN app.courses c ON c.id = e.course_id
                 WHERE e.user_id = %s
                   AND e.source = 'free_intro'
                   AND c.is_free_intro = true
                """,
                (user_id,),
            )
            consumed_row = await cur.fetchone()
            consumed = int((consumed_row or {}).get("count") or 0)

            await cur.execute(
                """
                SELECT EXISTS(
                  SELECT 1
                  FROM app.enrollments
                  WHERE user_id = %s AND course_id = %s
                ) AS already
                """,
                (user_id, course_id),
            )
            already_row = await cur.fetchone()
            already = bool((already_row or {}).get("already"))
            if already:
                await conn.rollback()
                return {
                    "ok": True,
                    "status": "already_enrolled",
                    "consumed": consumed,
                    "limit": free_limit,
                }

            if not has_active_subscription and consumed >= free_limit:
                await conn.rollback()
                return {
                    "ok": False,
                    "status": "limit_reached",
                    "consumed": consumed,
                    "limit": free_limit,
                }

            await cur.execute(
                """
                INSERT INTO app.enrollments (user_id, course_id, source)
                VALUES (%s, %s, 'free_intro')
                ON CONFLICT (user_id, course_id) DO NOTHING
                """,
                (user_id, course_id),
            )
            await conn.commit()

    return {
        "ok": True,
        "status": "enrolled",
        "consumed": consumed + 1,
        "limit": free_limit,
    }


async def get_course_intro_state(course_id: str) -> dict[str, Any] | None:
    query = """
        SELECT id, is_free_intro, is_published
        FROM app.courses
        WHERE id = %s
        LIMIT 1
    """
    async with get_conn() as cur:
        await cur.execute(query, (course_id,))
        row = await cur.fetchone()
    return dict(row) if row else None


async def get_free_course_limit() -> int:
    async with get_conn() as cur:
        await cur.execute("SELECT free_course_limit FROM app.app_config WHERE id = 1")
        row = await cur.fetchone()
    if not row or row.get("free_course_limit") is None:
        return 5
    value = row["free_course_limit"]
    if isinstance(value, int):
        return value
    if isinstance(value, (float, complex)):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return 5
    return 5


async def get_course_quiz(course_id: str) -> dict[str, Any] | None:
    async with get_conn() as cur:
        try:
            await cur.execute(
                "SELECT id, course_id FROM app.course_quizzes WHERE course_id = %s LIMIT 1",
                (course_id,),
            )
        except errors.UndefinedTable:
            return None
        row = await cur.fetchone()
    return dict(row) if row else None


async def is_user_certified_for_course(user_id: str, course_id: str) -> bool:
    async with get_conn() as cur:
        await cur.execute(
            "SELECT 1 FROM app.certificates WHERE user_id = %s AND course_id = %s LIMIT 1",
            (user_id, course_id),
        )
        return (await cur.fetchone()) is not None


async def list_quiz_questions(quiz_id: str) -> Sequence[dict[str, Any]]:
    query = """
        SELECT id, position, kind, prompt, options
        FROM app.quiz_questions
        WHERE quiz_id = %s
        ORDER BY position
    """
    async with get_conn() as cur:
        await cur.execute(query, (quiz_id,))
        return await cur.fetchall()


async def submit_quiz_answers(
    quiz_id: str,
    user_id: str,
    answers: Mapping[str, Any],
) -> dict[str, Any]:
    async with get_conn() as cur:
        await cur.execute(
            "SELECT * FROM app.grade_quiz_and_issue_certificate(%s, %s::jsonb)",
            (quiz_id, Jsonb(dict(answers))),
        )
        row = await cur.fetchone()
    return dict(row) if row else {}


__all__ = [
    "CourseRow",
    "ModuleRow",
    "LessonRow",
    "get_course",
    "get_course_by_slug",
    "list_courses",
    "list_public_courses",
    "create_course",
    "update_course",
    "delete_course",
    "list_modules",
    "get_module",
    "get_module_course_id",
    "create_module",
    "upsert_module",
    "delete_module",
    "list_lessons",
    "list_lesson_media",
    "get_lesson_media_access_by_path",
    "list_home_audio_media",
    "list_course_lessons",
    "get_lesson",
    "get_lesson_course_ids",
    "create_lesson",
    "upsert_lesson",
    "delete_lesson",
    "reorder_lessons",
    "is_course_owner",
    "list_my_courses",
    "is_enrolled",
    "enforce_free_intro_enrollment",
    "ensure_course_enrollment",
    "count_free_intro_enrollments",
    "enroll_free_intro",
    "get_course_intro_state",
    "get_free_course_limit",
    "get_course_quiz",
    "is_user_certified_for_course",
    "list_quiz_questions",
    "submit_quiz_answers",
    "update_course_stripe_ids",
    "update_course_price_cents",
]
