from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from fastapi import HTTPException

from app.routes import playback
from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


async def test_course_access_snapshot_denies_non_intro_membership_without_enrollment(
    monkeypatch,
):
    async def false_async(*args, **kwargs):
        return False

    async def none_async(*args, **kwargs):
        return None

    async def empty_profile(*args, **kwargs):
        return {}

    async def active_membership(*args, **kwargs):
        return {"status": "active", "expires_at": None}

    async def paid_course(*args, **kwargs):
        return {"id": "course-paid", "is_free_intro": False, "is_published": True}

    monkeypatch.setattr(
        courses_service,
        "is_course_teacher_or_instructor",
        false_async,
        raising=True,
    )
    monkeypatch.setattr(courses_service, "is_user_enrolled", false_async, raising=True)
    monkeypatch.setattr(courses_service, "latest_order_for_course", none_async, raising=True)
    monkeypatch.setattr(courses_service, "get_profile", empty_profile, raising=True)
    monkeypatch.setattr(courses_service, "get_membership", active_membership, raising=True)
    monkeypatch.setattr(
        courses_service,
        "fetch_course_access_subject",
        paid_course,
        raising=True,
    )

    snapshot = await courses_service.course_access_snapshot("user-1", "course-paid")

    assert snapshot["has_active_subscription"] is True
    assert snapshot["has_access"] is False
    assert snapshot["can_access"] is False
    assert snapshot["access_reason"] == "none"
    assert snapshot["enrolled"] is False
    assert snapshot["latest_order"] is None


async def test_course_access_snapshot_grants_intro_membership_access_explicitly(
    monkeypatch,
):
    async def false_async(*args, **kwargs):
        return False

    async def none_async(*args, **kwargs):
        return None

    async def empty_profile(*args, **kwargs):
        return {}

    async def active_membership(*args, **kwargs):
        return {"status": "active", "expires_at": None}

    async def intro_course(*args, **kwargs):
        return {"id": "course-intro", "is_free_intro": True, "is_published": True}

    monkeypatch.setattr(
        courses_service,
        "is_course_teacher_or_instructor",
        false_async,
        raising=True,
    )
    monkeypatch.setattr(courses_service, "is_user_enrolled", false_async, raising=True)
    monkeypatch.setattr(courses_service, "latest_order_for_course", none_async, raising=True)
    monkeypatch.setattr(courses_service, "get_profile", empty_profile, raising=True)
    monkeypatch.setattr(courses_service, "get_membership", active_membership, raising=True)
    monkeypatch.setattr(
        courses_service,
        "fetch_course_access_subject",
        intro_course,
        raising=True,
    )

    snapshot = await courses_service.course_access_snapshot("user-1", "course-intro")

    assert snapshot["has_active_subscription"] is True
    assert snapshot["has_access"] is True
    assert snapshot["can_access"] is True
    assert snapshot["access_reason"] == "membership_intro"
    assert snapshot["enrolled"] is False


async def test_enroll_free_intro_requires_membership_without_step1_bypass(
    monkeypatch,
):
    async def intro_course(*args, **kwargs):
        return {"id": "course-intro", "is_free_intro": True, "is_published": True}

    async def no_membership(*args, **kwargs):
        return None

    ensure_course_enrollment = AsyncMock()
    claim_intro_monthly_access = AsyncMock()
    user_owns_any_course_step = AsyncMock(return_value=True)

    monkeypatch.setattr(courses_service, "fetch_course", intro_course, raising=True)
    monkeypatch.setattr(courses_service, "get_membership", no_membership, raising=True)
    monkeypatch.setattr(
        courses_service.courses_repo,
        "ensure_course_enrollment",
        ensure_course_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "claim_intro_monthly_access",
        claim_intro_monthly_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "user_owns_any_course_step",
        user_owns_any_course_step,
        raising=True,
    )

    result = await courses_service.enroll_free_intro("user-1", "course-intro")

    assert result == {"ok": False, "status": "subscription_required"}
    ensure_course_enrollment.assert_not_awaited()
    claim_intro_monthly_access.assert_not_awaited()
    user_owns_any_course_step.assert_not_awaited()


async def test_playback_access_does_not_fall_back_to_entitlements(monkeypatch):
    async def paid_course(*args, **kwargs):
        return {"id": "course-paid", "is_free_intro": False, "is_published": True}

    async def read_denied(*args, **kwargs):
        return False

    monkeypatch.setattr(
        playback.courses_service,
        "fetch_course_access_subject",
        paid_course,
        raising=True,
    )
    monkeypatch.setattr(
        playback.courses_service,
        "can_user_read_course",
        read_denied,
        raising=True,
    )
    assert not hasattr(playback, "entitlement_service")

    with pytest.raises(HTTPException) as excinfo:
        await playback._enforce_course_access(
            object(),
            user_id="user-1",
            course_id="course-paid",
        )

    assert excinfo.value.status_code == 403


async def test_playback_access_allows_explicit_intro_membership(monkeypatch):
    async def intro_course(*args, **kwargs):
        return {"id": "course-intro", "is_free_intro": True, "is_published": True}

    async def read_allowed(*args, **kwargs):
        return True

    monkeypatch.setattr(
        playback.courses_service,
        "fetch_course_access_subject",
        intro_course,
        raising=True,
    )
    monkeypatch.setattr(
        playback.courses_service,
        "can_user_read_course",
        read_allowed,
        raising=True,
    )
    assert not hasattr(playback, "entitlement_service")

    await playback._enforce_course_access(
        object(),
        user_id="user-1",
        course_id="course-intro",
    )
