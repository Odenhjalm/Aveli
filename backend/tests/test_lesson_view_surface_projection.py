from __future__ import annotations

import inspect

import pytest

from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
TEACHER_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
LESSON_ID = "33333333-3333-3333-3333-333333333333"
PREVIOUS_LESSON_ID = "33333333-3333-3333-3333-333333333331"
NEXT_LESSON_ID = "33333333-3333-3333-3333-333333333334"
LESSON_MEDIA_ID = "44444444-4444-4444-4444-444444444444"
MEDIA_ID = "55555555-5555-5555-5555-555555555555"


def _lesson_shell(*, position: int = 2) -> dict[str, object]:
    return {
        "id": LESSON_ID,
        "course_id": COURSE_ID,
        "lesson_title": "Lesson View",
        "position": position,
    }


def _navigation() -> dict[str, object]:
    return {
        "lesson_id": LESSON_ID,
        "course_id": COURSE_ID,
        "previous_lesson_id": PREVIOUS_LESSON_ID,
        "next_lesson_id": NEXT_LESSON_ID,
    }


def _premium_pricing() -> dict[str, object]:
    return {
        "course_id": COURSE_ID,
        "price_amount_cents": 12345,
        "price_currency": "sek",
        "sellable": True,
        "required_enrollment_source": "purchase",
        "active_stripe_price_id": "price_123",
    }


def _intro_pricing() -> dict[str, object]:
    return {
        "course_id": COURSE_ID,
        "price_amount_cents": None,
        "price_currency": "sek",
        "sellable": False,
        "required_enrollment_source": "intro",
        "active_stripe_price_id": None,
    }


async def _install_base_repo_fakes(monkeypatch, *, shell: dict[str, object] | None = None):
    async def fake_shell(lesson_id: str):
        assert lesson_id == LESSON_ID
        return shell or _lesson_shell()

    async def fake_navigation(lesson_id: str):
        assert lesson_id == LESSON_ID
        return _navigation()

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_lesson_shell",
        fake_shell,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_navigation",
        fake_navigation,
        raising=True,
    )


async def test_lesson_view_locked_no_access_omits_content_and_media(monkeypatch):
    await _install_base_repo_fakes(monkeypatch)

    async def fake_pricing(course_id: str):
        assert course_id == COURSE_ID
        return _premium_pricing()

    async def fake_access(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return {
            "course": {"id": COURSE_ID},
            "enrollment": None,
            "required_enrollment_source": "purchase",
            "selection_locked": False,
            "can_access": False,
        }

    async def fail_protected_content(*args, **kwargs):
        raise AssertionError("locked Lesson View must not read protected content/media")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_course_pricing",
        fake_pricing,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fake_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_protected_lesson_content_surface",
        fail_protected_content,
        raising=True,
    )

    response = await courses_service.read_lesson_view_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    assert "content_document" not in payload["lesson"]
    assert payload["media"] == []
    assert "lesson_media_id" not in str(payload)
    assert "resolved_url" not in str(payload)
    assert payload["access"] == {
        "has_access": False,
        "is_enrolled": False,
        "is_in_drip": False,
        "is_premium": True,
        "can_enroll": False,
        "can_purchase": True,
    }
    assert payload["cta"]["type"] == "buy"
    assert payload["pricing"]["price_currency"] == "sek"
    assert payload["pricing"]["formatted"] == "123.45 SEK"
    assert payload["navigation"]["previous_lesson_id"] == PREVIOUS_LESSON_ID
    assert payload["navigation"]["next_lesson_id"] == NEXT_LESSON_ID
    assert payload["progression"] == {"unlocked": False, "reason": "no_access"}


async def test_lesson_view_unlocked_includes_canonical_content_and_media(monkeypatch):
    await _install_base_repo_fakes(monkeypatch, shell=_lesson_shell(position=1))

    content_document = {"schema_version": "lesson_document_v1", "blocks": []}

    async def fake_pricing(course_id: str):
        assert course_id == COURSE_ID
        return _premium_pricing()

    async def fake_access(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return {
            "course": {"id": COURSE_ID},
            "enrollment": {
                "id": "enrollment-1",
                "user_id": USER_ID,
                "course_id": COURSE_ID,
                "source": "purchase",
                "current_unlock_position": 1,
            },
            "required_enrollment_source": "purchase",
            "selection_locked": False,
            "can_access": True,
        }

    async def fake_protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == USER_ID
        return {
            "lesson": {
                **_lesson_shell(position=1),
                "content_document": content_document,
            },
            "media": [
                {
                    "id": LESSON_MEDIA_ID,
                    "lesson_id": LESSON_ID,
                    "media_asset_id": MEDIA_ID,
                    "position": 3,
                    "media_type": "video",
                    "state": "ready",
                    "media": {
                        "media_id": MEDIA_ID,
                        "state": "ready",
                        "resolved_url": "https://media.local/video.mp4",
                    },
                }
            ],
        }

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_course_pricing",
        fake_pricing,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fake_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_protected_lesson_content_surface",
        fake_protected_content,
        raising=True,
    )

    response = await courses_service.read_lesson_view_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    assert payload["lesson"]["content_document"] == content_document
    assert payload["access"]["has_access"] is True
    assert payload["access"]["can_purchase"] is False
    assert payload["progression"] == {"unlocked": True, "reason": "available"}
    assert payload["media"] == [
        {
            "lesson_media_id": LESSON_MEDIA_ID,
            "position": 3,
            "media_type": "video",
            "media": {
                "media_id": MEDIA_ID,
                "state": "ready",
                "resolved_url": "https://media.local/video.mp4",
            },
        }
    ]
    assert "media_asset_id" not in str(payload)


async def test_lesson_view_drip_lock_does_not_read_protected_content(monkeypatch):
    await _install_base_repo_fakes(monkeypatch, shell=_lesson_shell(position=2))

    async def fake_pricing(course_id: str):
        assert course_id == COURSE_ID
        return _intro_pricing()

    async def fake_access(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return {
            "course": {"id": COURSE_ID},
            "enrollment": {
                "id": "enrollment-1",
                "user_id": USER_ID,
                "course_id": COURSE_ID,
                "source": "intro",
                "current_unlock_position": 1,
            },
            "required_enrollment_source": "intro",
            "selection_locked": False,
            "can_access": True,
        }

    async def fail_protected_content(*args, **kwargs):
        raise AssertionError("drip-locked Lesson View must not read protected content/media")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_course_pricing",
        fake_pricing,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fake_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_protected_lesson_content_surface",
        fail_protected_content,
        raising=True,
    )

    response = await courses_service.read_lesson_view_surface(
        LESSON_ID,
        user_id=USER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    assert "content_document" not in payload["lesson"]
    assert payload["media"] == []
    assert payload["access"]["is_in_drip"] is True
    assert payload["access"]["can_enroll"] is False
    assert payload["progression"] == {"unlocked": False, "reason": "drip"}
    assert payload["cta"]["type"] == "blocked"


async def test_lesson_view_preview_uses_teacher_authorization_without_enrollment_claim(
    monkeypatch,
):
    await _install_base_repo_fakes(monkeypatch, shell=_lesson_shell(position=1))

    content_document = {"schema_version": "lesson_document_v1", "blocks": []}

    async def fake_pricing(course_id: str):
        assert course_id == COURSE_ID
        return _premium_pricing()

    async def fake_is_course_owner(user_id: str, course_id: str):
        assert user_id == TEACHER_ID
        assert course_id == COURSE_ID
        return True

    async def fail_course_access(*args, **kwargs):
        raise AssertionError("preview must not claim learner enrollment access")

    async def fake_protected_content(lesson_id: str, *, user_id: str):
        assert lesson_id == LESSON_ID
        assert user_id == TEACHER_ID
        return {
            "lesson": {
                **_lesson_shell(position=1),
                "content_document": content_document,
            },
            "media": [],
        }

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_lesson_view_course_pricing",
        fake_pricing,
        raising=True,
    )
    monkeypatch.setattr(courses_service, "is_course_owner", fake_is_course_owner, raising=True)
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_access",
        fail_course_access,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_protected_lesson_content_surface",
        fake_protected_content,
        raising=True,
    )

    response = await courses_service.read_lesson_view_surface(
        LESSON_ID,
        preview=True,
        teacher_id=TEACHER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    assert payload["lesson"]["content_document"] == content_document
    assert payload["access"]["has_access"] is True
    assert payload["access"]["is_enrolled"] is False
    assert payload["access"]["can_purchase"] is False
    assert payload["progression"] == {"unlocked": True, "reason": "available"}


def test_lesson_view_projection_does_not_use_group_position_for_runtime_authority():
    source = inspect.getsource(courses_service.read_lesson_view_surface)
    source += inspect.getsource(courses_service._lesson_view_access_projection)

    assert "group_position" not in source
