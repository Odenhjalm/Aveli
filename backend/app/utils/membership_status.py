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


def membership_expires_at(
    membership: Mapping[str, Any] | None,
) -> datetime | str | None:
    if not membership:
        return None
    return membership.get("expires_at", membership.get("end_date"))


def is_membership_active(
    status: str,
    expires_at: datetime | str | None = None,
    *,
    now: datetime | None = None,
) -> bool:
    normalized_status = str(status or "").strip().lower()
    if normalized_status == "active":
        return True

    current_time = now or datetime.now(timezone.utc)
    if normalized_status != "canceled":
        return False

    normalized_expiry = _normalize_datetime(expires_at)
    if normalized_expiry is None:
        return False
    return normalized_expiry > current_time


def is_membership_row_active(
    membership: Mapping[str, Any] | None,
    *,
    now: datetime | None = None,
) -> bool:
    if not membership:
        return False
    return is_membership_active(
        str(membership.get("status") or ""),
        membership_expires_at(membership),
        now=now,
    )
