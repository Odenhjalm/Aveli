from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional

from psycopg.types.json import Jsonb

from ..db import get_conn


async def insert_activity(
    *,
    activity_type: str,
    actor_id: Optional[str],
    subject_table: str,
    subject_id: Optional[str],
    summary: Optional[str],
    metadata: Optional[dict[str, Any]] = None,
    occurred_at: Optional[datetime] = None,
) -> None:
    """
    Persist an audit activity row.
    """
    payload = metadata or {}
    timestamp = occurred_at or datetime.now(timezone.utc)
    query = """
        insert into app.activities (
            activity_type,
            actor_id,
            subject_table,
            subject_id,
            summary,
            metadata,
            occurred_at
        )
        values (%s, %s, %s, %s, %s, %s, %s)
    """
    async with get_conn() as cur:
        await cur.execute(
            query,
            (
                activity_type,
                actor_id,
                subject_table,
                subject_id,
                summary,
                Jsonb(payload),
                timestamp,
            ),
        )
