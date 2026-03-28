from __future__ import annotations

import asyncio
from typing import Any

from psycopg import errors

from ...repositories import (
    auth as auth_repo,
    course_entitlements as course_entitlements_repo,
    courses as courses_repo,
    memberships as memberships_repo,
    profiles as profiles_repo,
)
from ...utils.membership_status import is_membership_row_active
from .. import onboarding_state
from .common import (
    iso,
    now,
    normalize_text,
    sort_inconsistencies,
    sort_violations,
    status_from_violations,
    unique_sorted_strings,
    violation,
)

_COURSE_LIMIT = 25
_SCHEMA_GUARDED_SOURCES = {
    "auth.get_user_by_id": "error",
    "profiles.get_profile": "error",
    "memberships.get_membership": "warning",
    "courses.list_courses": "warning",
    "courses.list_my_courses": "warning",
    "course_entitlements.list_entitlements_for_user": "warning",
}


def _email_verification_state(user_row: dict[str, Any] | None) -> str:
    if user_row is None:
        return "missing"
    if user_row.get("email_confirmed_at") or user_row.get("confirmed_at"):
        return "verified"
    return "unverified"


def _role_state(profile_row: dict[str, Any] | None) -> str:
    if profile_row is None:
        return "missing"
    if bool(profile_row.get("is_admin")):
        return "admin"
    return normalize_text(profile_row.get("role_v2")) or "missing"


async def _guard_schema(source: str, awaitable) -> tuple[Any, dict[str, Any] | None]:
    try:
        return await awaitable, None
    except (errors.UndefinedColumn, errors.UndefinedTable) as exc:
        return None, {
            "code": f"{source.replace('.', '_')}_schema_unavailable",
            "message": f"{source} is unavailable in the local candidate schema",
            "source": source,
            "severity": _SCHEMA_GUARDED_SOURCES.get(source, "warning"),
            "details": {
                "database_error": (exc.diag.message_primary if exc.diag else None) or str(exc),
            },
        }


async def inspect_user(user_id: str) -> dict[str, Any]:
    normalized_user_id = str(user_id or "").strip()
    (
        (user_row, user_issue),
        (profile_row, profile_issue),
        (membership_row, membership_issue),
        (authored_courses_raw, authored_courses_issue),
        (enrolled_courses_raw, enrolled_courses_issue),
        (entitlement_slugs_raw, entitlements_issue),
    ) = await asyncio.gather(
        _guard_schema("auth.get_user_by_id", auth_repo.get_user_by_id(normalized_user_id)),
        _guard_schema("profiles.get_profile", profiles_repo.get_profile(normalized_user_id)),
        _guard_schema("memberships.get_membership", memberships_repo.get_membership(normalized_user_id)),
        _guard_schema(
            "courses.list_courses",
            courses_repo.list_courses(teacher_id=normalized_user_id, limit=_COURSE_LIMIT),
        ),
        _guard_schema("courses.list_my_courses", courses_repo.list_my_courses(normalized_user_id)),
        _guard_schema(
            "course_entitlements.list_entitlements_for_user",
            course_entitlements_repo.list_entitlements_for_user(normalized_user_id),
        ),
    )
    authored_courses_raw = authored_courses_raw or []
    enrolled_courses_raw = enrolled_courses_raw or []
    entitlement_slugs_raw = entitlement_slugs_raw or []

    derived_onboarding_state: str | None = None
    if profile_row is not None:
        try:
            derived_onboarding_state = await onboarding_state.derive_onboarding_state(
                normalized_user_id
            )
        except ValueError:
            derived_onboarding_state = None

    authored_course_ids = unique_sorted_strings(
        row.get("id") for row in list(authored_courses_raw)[:_COURSE_LIMIT]
    )
    enrolled_course_ids = unique_sorted_strings(
        row.get("id") for row in list(enrolled_courses_raw)[:_COURSE_LIMIT]
    )
    entitlement_slugs = unique_sorted_strings(list(entitlement_slugs_raw)[:_COURSE_LIMIT])

    violations: list[dict[str, Any]] = []
    inconsistencies: list[dict[str, Any]] = []
    subject = {"user_id": normalized_user_id}
    for source_issue in (
        user_issue,
        profile_issue,
        membership_issue,
        authored_courses_issue,
        enrolled_courses_issue,
        entitlements_issue,
    ):
        if source_issue is None:
            continue
        violations.append(
            violation(
                source_issue["code"],
                source_issue["message"],
                source=source_issue["source"],
                severity_value=source_issue["severity"],
                subject=subject,
                details=source_issue["details"],
            )
        )
        inconsistencies.append(
            {
                "code": source_issue["code"],
                "message": source_issue["message"],
                "source": source_issue["source"],
                "details": source_issue["details"],
            }
        )

    if user_row is None:
        violations.append(
            violation(
                "user_missing",
                "User was not found",
                source="auth.get_user_by_id",
                subject=subject,
            )
        )
    if profile_row is None:
        violations.append(
            violation(
                "profile_missing",
                "Profile was not found",
                source="profiles.get_profile",
                subject=subject,
            )
        )

    user_email = normalize_text((user_row or {}).get("email"))
    profile_email = normalize_text((profile_row or {}).get("email"))
    if user_email is not None and profile_email is not None:
        if user_email.lower() != profile_email.lower():
            details = {
                "auth_email_present": True,
                "profile_email_present": True,
            }
            violations.append(
                violation(
                    "profile_auth_email_mismatch",
                    "Auth user and profile email do not align",
                    source="auth.get_user_by_id",
                    severity_value="warning",
                    subject=subject,
                    details=details,
                )
            )
            inconsistencies.append(
                {
                    "code": "profile_auth_email_mismatch",
                    "message": "Auth user and profile email do not align",
                    "source": "auth.get_user_by_id",
                    "details": details,
                }
            )

    stored_onboarding_state = normalize_text((profile_row or {}).get("onboarding_state"))
    if (
        stored_onboarding_state is not None
        and derived_onboarding_state is not None
        and stored_onboarding_state != derived_onboarding_state
    ):
        details = {
            "stored": stored_onboarding_state,
            "derived": derived_onboarding_state,
        }
        violations.append(
            violation(
                "onboarding_state_drift",
                "Stored onboarding state does not match the derived onboarding state",
                source="onboarding_state.derive_onboarding_state",
                severity_value="warning",
                subject=subject,
                details=details,
            )
        )
        inconsistencies.append(
            {
                "code": "onboarding_state_drift",
                "message": "Stored onboarding state differs from derived state",
                "source": "onboarding_state.derive_onboarding_state",
                "details": details,
            }
        )

    sorted_violations = sort_violations(violations)
    sorted_inconsistencies = sort_inconsistencies(inconsistencies)
    generated_at = iso(now())
    return {
        "generated_at": generated_at,
        "inspection": {
            "tool": "inspect_user",
            "version": "1",
        },
        "subject": subject,
        "status": status_from_violations(
            sorted_violations,
            missing_subject=user_row is None and profile_row is None,
        ),
        "violations": sorted_violations,
        "inconsistencies": sorted_inconsistencies,
        "state_summary": {
            "auth_user_state": "present" if user_row is not None else "missing",
            "email_verification_state": _email_verification_state(user_row),
            "profile_state": "present" if profile_row is not None else "missing",
            "role_state": _role_state(profile_row),
            "membership_state": (
                "active"
                if is_membership_row_active(membership_row)
                else ("inactive" if membership_row is not None else "missing")
            ),
            "stored_onboarding_state": stored_onboarding_state,
            "derived_onboarding_state": derived_onboarding_state,
            "onboarding_alignment": (
                "unavailable"
                if stored_onboarding_state is None or derived_onboarding_state is None
                else (
                    "aligned"
                    if stored_onboarding_state == derived_onboarding_state
                    else "drift"
                )
            ),
            "authored_course_count": len(authored_course_ids),
            "enrolled_course_count": len(enrolled_course_ids),
            "entitlement_count": len(entitlement_slugs),
        },
        "truth_sources": {
            "auth": {
                "user_present": user_row is not None,
            },
            "profile": {
                "profile_present": profile_row is not None,
            },
            "membership": {
                "membership_present": membership_row is not None,
                "membership_active": is_membership_row_active(membership_row),
            },
            "onboarding": {
                "stored": stored_onboarding_state,
                "derived": derived_onboarding_state,
            },
            "courses": {
                "authored_course_ids": authored_course_ids,
                "enrolled_course_ids": enrolled_course_ids,
            },
            "entitlements": {
                "course_slugs": entitlement_slugs,
            },
        },
        "sources_consulted": [
            "auth.get_user_by_id",
            "profiles.get_profile",
            "memberships.get_membership",
            "onboarding_state.derive_onboarding_state",
            "courses.list_courses",
            "courses.list_my_courses",
            "course_entitlements.list_entitlements_for_user",
        ],
    }
