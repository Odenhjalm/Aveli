from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row

from ..db import get_conn, pool


def _hydrate_profile_projection(row: dict[str, Any]) -> dict[str, Any]:
    return dict(row)


async def get_profile(user_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT p.user_id,
                   u.email,
                   p.display_name,
                   p.bio,
                   p.avatar_media_id,
                   p.created_at,
                   p.updated_at
            FROM app.profiles p
            JOIN auth.users u ON u.id = p.user_id
            WHERE p.user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
        return _hydrate_profile_projection(dict(row)) if row else None


async def update_profile(
    user_id: str | UUID,
    *,
    display_name: str | None = None,
    bio: str | None = None,
) -> dict[str, Any] | None:
    assignments: list[str] = []
    params: list[object] = []

    def _append(column: str, value: object) -> None:
        assignments.append(f"{column} = %s")
        params.append(value)

    if display_name is not None:
        _append("display_name", display_name.strip() or None)
    if bio is not None:
        _append("bio", bio.strip() or None)

    if not assignments:
        return await get_profile(user_id)

    assignments.append("updated_at = now()")
    params.append(str(user_id))

    query = """
        UPDATE app.profiles
           SET {set_clause}
         WHERE user_id = %s
         RETURNING user_id
    """.format(set_clause=", ".join(assignments))

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            await cur.fetchone()
            await conn.commit()
            return await get_profile(user_id)


async def update_avatar_media_projection(
    user_id: str | UUID,
    *,
    avatar_media_id: str | UUID,
) -> dict[str, Any] | None:
    query = """
        UPDATE app.profiles
           SET avatar_media_id = %s::uuid,
               updated_at = now()
         WHERE user_id = %s::uuid
         RETURNING user_id
    """
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, (str(avatar_media_id), str(user_id)))
            row = await cur.fetchone()
            await conn.commit()
    if row is None:
        return None
    return await get_profile(user_id)
