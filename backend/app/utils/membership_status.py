from __future__ import annotations


def is_membership_active(status: str) -> bool:
    return status in ("active", "trialing")

