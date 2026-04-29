from __future__ import annotations

import inspect

import pytest

from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


USER_ID = "11111111-1111-1111-1111-111111111111"
COURSE_ID = "22222222-2222-2222-2222-222222222222"
OTHER_COURSE_ID = "22222222-2222-2222-2222-222222222223"
LESSON_1_ID = "33333333-3333-3333-3333-333333333331"
LESSON_2_ID = "33333333-3333-3333-3333-333333333332"
LESSON_3_ID = "33333333-3333-3333-3333-333333333333"


def _course_base(
    *,
    required_enrollment_source: str = "intro",
    sellable: bool = False,
    price_amount_cents: int | None = None,
    price_currency: str = "sek",
    active_stripe_price_id: str | None = None,
) -> dict[str, object]:
    return {
        "id": COURSE_ID,
        "slug": "course-entry",
        "title": "Course Entry",
        "required_enrollment_source": required_enrollment_source,
        "sellable": sellable,
        "price_amount_cents": price_amount_cents,
        "price_currency": price_currency,
        "active_stripe_price_id": active_stripe_price_id,
        "content_ready": True,
        "visibility": "public",
        "cover_media_id": None,
        "description": "Backend-authored course description.",
    }


def _lessons() -> list[dict[str, object]]:
    return [
        {"id": LESSON_1_ID, "lesson_title": "Lesson 1", "position": 1},
        {"id": LESSON_2_ID, "lesson_title": "Lesson 2", "position": 2},
        {"id": LESSON_3_ID, "lesson_title": "Lesson 3", "position": 3},
    ]


def _enrollment(*, current_unlock_position: int = 1) -> dict[str, object]:
    return {
        "enrollment_exists": True,
        "enrollment_id": "44444444-4444-4444-4444-444444444444",
        "drip_started_at": "2026-01-01T00:00:00Z",
        "current_unlock_position": current_unlock_position,
    }


async def _install_entry_fakes(
    monkeypatch,
    *,
    course: dict[str, object] | None = None,
    lessons: list[dict[str, object]] | None = None,
    enrollment: dict[str, object] | None = None,
    intro_drip_state: dict[str, object] | None = None,
) -> None:
    async def fake_get_course_entry_view_base(course_id_or_slug: str):
        assert course_id_or_slug == "course-entry"
        return course or _course_base()

    async def fake_list_course_entry_lessons(course_id: str):
        assert course_id == COURSE_ID
        return lessons or _lessons()

    async def fake_get_course_entry_enrollment(user_id: str, course_id: str):
        assert user_id == USER_ID
        assert course_id == COURSE_ID
        return enrollment

    async def fake_get_active_intro_drip_state(user_id: str):
        assert user_id == USER_ID
        return intro_drip_state or {
            "is_in_any_intro_drip": False,
            "active_course_id": None,
        }

    async def fake_resolve_course_cover(**_: object):
        return None

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course_entry_view_base",
        fake_get_course_entry_view_base,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_course_entry_lessons",
        fake_list_course_entry_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course_entry_enrollment",
        fake_get_course_entry_enrollment,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_active_intro_drip_state",
        fake_get_active_intro_drip_state,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "resolve_course_cover",
        fake_resolve_course_cover,
        raising=True,
    )


async def test_intro_course_enroll_cta_enabled_without_active_intro_drip(monkeypatch):
    await _install_entry_fakes(monkeypatch)

    response = await courses_service.read_course_entry_view_surface(
        "course-entry",
        USER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    assert payload["access"]["can_enroll"] is True
    assert payload["access"]["can_purchase"] is False
    assert payload["cta"]["type"] == "enroll"
    assert payload["cta"]["enabled"] is True


async def test_intro_course_blocked_when_another_intro_drip_is_active(monkeypatch):
    await _install_entry_fakes(
        monkeypatch,
        intro_drip_state={
            "is_in_any_intro_drip": True,
            "active_course_id": OTHER_COURSE_ID,
        },
    )

    response = await courses_service.read_course_entry_view_surface(
        "course-entry",
        USER_ID,
    )

    assert response is not None
    assert response.access.is_in_any_intro_drip is True
    assert response.access.can_enroll is False
    assert response.cta.type == "blocked"
    assert response.cta.enabled is False
    assert response.cta.reason_code == "active_intro_drip"


async def test_premium_course_buy_cta_with_valid_pricing(monkeypatch):
    await _install_entry_fakes(
        monkeypatch,
        course=_course_base(
            required_enrollment_source="purchase",
            sellable=True,
            price_amount_cents=12345,
            price_currency="sek",
            active_stripe_price_id="price_test",
        ),
    )

    response = await courses_service.read_course_entry_view_surface(
        "course-entry",
        USER_ID,
    )

    assert response is not None
    assert response.access.can_purchase is True
    assert response.cta.type == "buy"
    assert response.cta.enabled is True
    assert response.pricing is not None
    assert response.pricing.price_amount_cents == 12345
    assert response.pricing.price_currency == "sek"
    assert response.pricing.formatted_price == "123.45 SEK"
    assert response.course.formatted_price == "123.45 SEK"


def test_course_entry_projection_does_not_use_group_position():
    sources = "\n".join(
        inspect.getsource(obj)
        for obj in (
            courses_service.read_course_entry_view_surface,
            courses_service._course_entry_access_projection,
            courses_service._course_entry_cta_projection,
            courses_service._course_entry_sellable_course,
        )
    )

    assert "group_position" not in sources


async def test_gateway_response_contains_no_lesson_content_or_media_fields(
    monkeypatch,
):
    async def fail_lesson_view(*_: object, **__: object):
        raise AssertionError("entry-view projection must not read lesson runtime")

    monkeypatch.setattr(
        courses_service,
        "read_lesson_view_surface",
        fail_lesson_view,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_protected_lesson_content_surface",
        fail_lesson_view,
        raising=True,
    )
    await _install_entry_fakes(
        monkeypatch,
        enrollment=_enrollment(current_unlock_position=2),
    )

    response = await courses_service.read_course_entry_view_surface(
        "course-entry",
        USER_ID,
    )

    assert response is not None
    payload = response.model_dump(mode="json", exclude_none=True)
    text = str(payload)
    assert "content_document" not in text
    assert "content_markdown" not in text
    assert "lesson_media_id" not in text
    assert "media_id" not in text
    assert "resolved_url" not in text


async def test_next_recommended_lesson_is_derived_backend_side(monkeypatch):
    await _install_entry_fakes(
        monkeypatch,
        enrollment=_enrollment(current_unlock_position=2),
    )

    response = await courses_service.read_course_entry_view_surface(
        "course-entry",
        {"user_id": USER_ID},
    )

    assert response is not None
    assert response.next_recommended_lesson is not None
    assert str(response.next_recommended_lesson.id) == LESSON_2_ID
    assert response.cta.type == "continue"
    assert response.cta.action == {"type": "lesson", "lesson_id": LESSON_2_ID}
    lesson_payloads = response.model_dump(mode="json")["lessons"]
    assert lesson_payloads[0]["progression"]["state"] == "completed"
    assert lesson_payloads[1]["progression"]["is_next_recommended"] is True
    assert lesson_payloads[1]["progression"]["state"] == "current"
    assert lesson_payloads[1]["availability"]["state"] == "unlocked"
    assert lesson_payloads[2]["availability"]["state"] == "locked"
    assert lesson_payloads[2]["progression"]["state"] == "upcoming"
