from __future__ import annotations

from typing import Any, AsyncIterator
from uuid import UUID

from ..db import get_conn


async def list_services(*, status: str | None = None) -> AsyncIterator[dict[str, Any]]:
    base_query = """
        SELECT id,
               provider_id,
               title,
               description,
               status,
               price_cents,
               currency,
               duration_min,
               requires_certification,
               certified_area,
               thumbnail_url,
               created_at,
               updated_at
        FROM app.services
    """
    params: dict[str, Any] = {}
    if status:
        base_query += " WHERE status = %(status)s::app.service_status"
        params["status"] = status
    base_query += " ORDER BY created_at DESC"

    async with get_conn() as cur:
        await cur.execute(base_query, params)
        rows = await cur.fetchall()

    for row in rows or []:
        yield dict(row)


async def get_service(service_id: str | UUID) -> dict[str, Any] | None:
    async with get_conn() as cur:
        await cur.execute(
            """
            SELECT id, provider_id, title, description, status,
                   price_cents, currency, duration_min,
                   requires_certification, certified_area,
                   thumbnail_url,
                   created_at, updated_at
            FROM app.services
            WHERE id = %s
            LIMIT 1
            """,
            (service_id,),
        )
        row = await cur.fetchone()
        return dict(row) if row else None
