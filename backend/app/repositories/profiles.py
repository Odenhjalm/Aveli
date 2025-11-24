from __future__ import annotations

from typing import Any
from uuid import UUID

from psycopg.rows import dict_row

from ..db import get_conn, pool


async def get_profile(user_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT user_id,
                   email,
                   display_name,
                   bio,
                   photo_url,
                   avatar_media_id,
                   role_v2,
                   is_admin,
                   created_at,
                   updated_at
            FROM app.profiles
            WHERE user_id = %s
            LIMIT 1
            """,
            (user_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None


async def update_profile(
    user_id: str | UUID,
    *,
    display_name: str | None = None,
    bio: str | None = None,
    photo_url: str | None = None,
    avatar_media_id: str | None = None,
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
    if photo_url is not None:
        _append("photo_url", photo_url.strip() or None)
    if avatar_media_id is not None:
        _append("avatar_media_id", avatar_media_id)

    if not assignments:
        return await get_profile(user_id)

    assignments.append("updated_at = now()")
    params.append(str(user_id))

    query = """
        UPDATE app.profiles
           SET {set_clause}
         WHERE user_id = %s
         RETURNING user_id, email, display_name, bio, photo_url,
                   avatar_media_id, role_v2, is_admin, created_at, updated_at
    """.format(set_clause=", ".join(assignments))

    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor(row_factory=dict_row) as cur:  # type: ignore[attr-defined]
            await cur.execute(query, params)
            row = await cur.fetchone()
            await conn.commit()
            return dict(row) if row else None
