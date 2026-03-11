from __future__ import annotations

import calendar
from datetime import datetime, timedelta, timezone


def add_referral_duration(
    start_at: datetime,
    *,
    free_days: int | None = None,
    free_months: int | None = None,
) -> datetime:
    if free_days is not None:
        return start_at + timedelta(days=free_days)
    if free_months is None:
        raise ValueError("Referral duration is required")

    month_index = start_at.month - 1 + free_months
    year = start_at.year + month_index // 12
    month = month_index % 12 + 1
    day = min(start_at.day, calendar.monthrange(year, month)[1])
    return start_at.replace(year=year, month=month, day=day)


def build_referral_duration_label(
    *,
    free_days: int | None = None,
    free_months: int | None = None,
) -> str:
    if free_days is not None:
        suffix = "dag" if free_days == 1 else "dagar"
        return f"{free_days} {suffix}"
    if free_months is not None:
        suffix = "månad" if free_months == 1 else "månader"
        return f"{free_months} {suffix}"
    raise ValueError("Referral duration is required")


def referral_membership_window(
    *,
    free_days: int | None = None,
    free_months: int | None = None,
    now: datetime | None = None,
) -> tuple[datetime, datetime]:
    start_at = now or datetime.now(timezone.utc)
    return start_at, add_referral_duration(
        start_at,
        free_days=free_days,
        free_months=free_months,
    )


__all__ = [
    "add_referral_duration",
    "build_referral_duration_label",
    "referral_membership_window",
]
