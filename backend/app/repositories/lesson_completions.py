from __future__ import annotations

from typing import Any

from psycopg import Error as PsycopgError
from psycopg.rows import dict_row

from ..db import pool


class LessonCompletionAlreadyExistsError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("lesson completion already exists")


class LessonCompletionUnknownUserError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("lesson completion user does not exist")


class LessonCompletionInvalidLessonCourseError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("lesson completion lesson/course pair is invalid")


class LessonCompletionInvalidSourceError(RuntimeError):
    def __init__(self) -> None:
        super().__init__("lesson completion source is invalid")


_LESSON_COMPLETION_COLUMNS = """
    id,
    user_id,
    course_id,
    lesson_id,
    completed_at,
    completion_source
"""


def _constraint_name(exc: PsycopgError) -> str | None:
    diag = getattr(exc, "diag", None)
    return getattr(diag, "constraint_name", None)


def _map_create_lesson_completion_error(
    exc: PsycopgError,
) -> RuntimeError | None:
    constraint_name = _constraint_name(exc)
    if constraint_name == "lesson_completions_user_id_lesson_id_key":
        return LessonCompletionAlreadyExistsError()
    if constraint_name == "lesson_completions_user_id_fkey":
        return LessonCompletionUnknownUserError()
    if constraint_name == "lesson_completions_lesson_id_course_id_fkey":
        return LessonCompletionInvalidLessonCourseError()
    if constraint_name == "lesson_completions_completion_source_check":
        return LessonCompletionInvalidSourceError()
    return None


async def create_lesson_completion(
    *,
    user_id: str,
    course_id: str,
    lesson_id: str,
    completion_source: str,
    conn: Any | None = None,
) -> dict[str, Any]:
    query = f"""
        insert into app.lesson_completions (
            user_id,
            course_id,
            lesson_id,
            completion_source
        )
        values (
            %s::uuid,
            %s::uuid,
            %s::uuid,
            %s
        )
        returning
            {_LESSON_COMPLETION_COLUMNS}
    """

    async def _execute(active_conn: Any) -> dict[str, Any]:
        try:
            async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
                await cur.execute(
                    query,
                    (user_id, course_id, lesson_id, completion_source),
                )
                row = await cur.fetchone()
        except PsycopgError as exc:
            mapped = _map_create_lesson_completion_error(exc)
            if mapped is not None:
                raise mapped from exc
            raise

        if row is None:
            raise RuntimeError("lesson completion insert did not return a row")
        return dict(row)

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        row = await _execute(active_conn)
        await active_conn.commit()
        return row


async def get_lesson_completion(
    *,
    user_id: str,
    lesson_id: str,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = f"""
        select
            {_LESSON_COMPLETION_COLUMNS}
        from app.lesson_completions
        where user_id = %s::uuid
          and lesson_id = %s::uuid
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, lesson_id))
            row = await cur.fetchone()
        return dict(row) if row is not None else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


async def list_course_lesson_completions(
    *,
    user_id: str,
    course_id: str,
    conn: Any | None = None,
) -> list[dict[str, Any]]:
    query = f"""
        select
            {_LESSON_COMPLETION_COLUMNS}
        from app.lesson_completions
        where user_id = %s::uuid
          and course_id = %s::uuid
        order by completed_at asc, lesson_id asc
    """

    async def _execute(active_conn: Any) -> list[dict[str, Any]]:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (user_id, course_id))
            rows = await cur.fetchall()
        return [dict(row) for row in rows]

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        rows = await _execute(active_conn)
        await active_conn.commit()
        return rows


async def get_intro_final_lesson_auto_completion_candidate(
    *,
    enrollment_id: str,
    conn: Any | None = None,
) -> dict[str, Any] | None:
    query = """
        select
            ce.id as enrollment_id,
            ce.user_id,
            ce.course_id,
            ce.drip_started_at,
            fl.id as final_lesson_id,
            app.compute_course_final_unlock_at(
                ce.course_id,
                ce.drip_started_at
            ) as final_unlock_at
        from app.course_enrollments as ce
        join app.courses as c
          on c.id = ce.course_id
        join app.lessons as fl
          on fl.course_id = ce.course_id
        where ce.id = %s::uuid
          and c.required_enrollment_source = 'intro'::app.course_enrollment_source
          and ce.source = c.required_enrollment_source
          and fl.position = (
            select max(l2.position)
            from app.lessons as l2
            where l2.course_id = ce.course_id
          )
        order by fl.id asc
        limit 1
    """

    async def _execute(active_conn: Any) -> dict[str, Any] | None:
        async with active_conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (enrollment_id,))
            row = await cur.fetchone()
        return dict(row) if row is not None else None

    if conn is not None:
        return await _execute(conn)

    async with pool.connection() as active_conn:  # type: ignore
        result = await _execute(active_conn)
        await active_conn.commit()
        return result


__all__ = [
    "LessonCompletionAlreadyExistsError",
    "LessonCompletionInvalidLessonCourseError",
    "LessonCompletionInvalidSourceError",
    "LessonCompletionUnknownUserError",
    "create_lesson_completion",
    "get_intro_final_lesson_auto_completion_candidate",
    "get_lesson_completion",
    "list_course_lesson_completions",
]
