from collections.abc import Mapping
import re
from typing import Any


def _description_names(db: Any) -> list[str]:
    description = getattr(db, "description", None) or []
    names: list[str] = []
    for item in description:
        name = getattr(item, "name", None)
        if name is None and isinstance(item, tuple) and item:
            name = item[0]
        names.append(str(name))
    return names


def _normalize_row(db: Any, row: Any) -> Any:
    if row is None:
        return None
    if isinstance(row, tuple):
        names = _description_names(db)
        if names and len(names) == len(row):
            return dict(zip(names, row, strict=False))
    if isinstance(row, Mapping):
        return row
    return row


async def fetch_one(db: Any, query: str, *params: Any) -> Any:
    if hasattr(db, "fetchrow"):
        row = await db.fetchrow(query, *params)
    else:
        placeholder_indexes = [
            int(match.group(1)) for match in re.finditer(r"\$(\d+)\b", query)
        ]
        expanded_params = tuple(params[index - 1] for index in placeholder_indexes)
        normalized_query = re.sub(r"\$\d+\b", "%s", query)
        await db.execute(normalized_query, expanded_params)
        row = await db.fetchone()
    return _normalize_row(db, row)


async def has_course_access(db: Any, user_id: str, course_id: str) -> bool:
    del db, user_id, course_id
    raise RuntimeError(
        "legacy entitlement_service is non-authoritative; "
        "use app.course_enrollments authority"
    )
