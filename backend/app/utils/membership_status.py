from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Mapping


def _normalize_datetime(value: datetime | str | None) -> datetime | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value)
        except ValueError:
            return None
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    return None


def is_membership_active(
    status: str,
    end_date: datetime | str | None = None,
    *,
    now: datetime | None = None,
) -> bool:
    if status not in ("active", "trialing"):
        return False
    normalized_end = _normalize_datetime(end_date)
    if normalized_end is None:
        return True
    current_time = now or datetime.now(timezone.utc)
    return normalized_end > current_time


def is_membership_row_active(
    membership: Mapping[str, Any] | None,
    *,
    now: datetime | None = None,
) -> bool:
    if not membership:
        return False
    return is_membership_active(
        str(membership.get("status") or ""),
        membership.get("end_date"),
        now=now,
    )
