import inspect

import pytest

from app.routes import studio
from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "course_publish_1"
TEACHER_ID = "teacher_publish_1"


def _course(**overrides):
    row = {
        "id": COURSE_ID,
        "teacher_id": TEACHER_ID,
        "slug": "publish-course",
        "title": "Publish Course",
        "course_group_id": "group_publish_1",
        "group_position": 1,
        "visibility": "draft",
        "content_ready": False,
        "price_amount_cents": 1900,
        "stripe_product_id": None,
        "active_stripe_price_id": None,
        "sellable": False,
        "drip_enabled": False,
        "drip_interval_days": None,
        "cover_media_id": None,
    }
    row.update(overrides)
    return row


def _lesson(**overrides):
    row = {
        "id": "lesson_publish_1",
        "course_id": COURSE_ID,
        "lesson_title": "Lesson 1",
        "position": 1,
        "has_content": True,
        "content_markdown": "Publiceringsklar lektion",
    }
    row.update(overrides)
    return row


async def _install_publish_fakes(
    monkeypatch,
    *,
    course: dict | None = None,
    lessons: list[dict] | None = None,
    media_by_lesson: dict[str, list[dict]] | None = None,
    owner: bool = True,
):
    state = {
        "course": dict(course or _course()),
        "lessons": list(lessons if lessons is not None else [_lesson()]),
        "media_by_lesson": dict(media_by_lesson or {}),
        "published": None,
    }

    async def fake_get_course_publish_subject(course_id: str):
        assert course_id == COURSE_ID
        return dict(state["course"]) if state["course"] is not None else None

    async def fake_is_course_owner(course_id: str, teacher_id: str):
        assert course_id == COURSE_ID
        assert teacher_id == TEACHER_ID
        return owner

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id is None
        assert slug == state["course"]["slug"]
        return dict(state["course"])

    async def fake_list_course_publish_lessons(course_id: str):
        assert course_id == COURSE_ID
        return list(state["lessons"])

    async def fake_list_lesson_media(lesson_id: str, **kwargs):
        return list(state["media_by_lesson"].get(lesson_id, []))

    async def fake_publish_course_state(
        course_id: str,
        *,
        stripe_product_id: str,
        active_stripe_price_id: str,
    ):
        assert course_id == COURSE_ID
        published = {
            **state["course"],
            "content_ready": True,
            "visibility": "public",
            "stripe_product_id": stripe_product_id,
            "active_stripe_price_id": active_stripe_price_id,
            "sellable": True,
        }
        state["course"] = published
        state["published"] = published
        return dict(published)

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course_publish_subject",
        fake_get_course_publish_subject,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_course_publish_lessons",
        fake_list_course_publish_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "publish_course_state",
        fake_publish_course_state,
        raising=True,
    )
    monkeypatch.setattr(courses_service, "_require_stripe_for_course_mapping", lambda: None)
    return state


def _install_stripe_create_fakes(monkeypatch):
    calls = {"product_create": 0, "price_create": 0}

    def fake_product_create(**kwargs):
        calls["product_create"] += 1
        assert kwargs["metadata"] == {
            "course_id": COURSE_ID,
            "teacher_id": TEACHER_ID,
            "type": "course",
        }
        assert kwargs["idempotency_key"] == f"course:{COURSE_ID}:product"
        return {"id": "prod_publish_1", "metadata": kwargs["metadata"], "active": True}

    def fake_price_create(**kwargs):
        calls["price_create"] += 1
        assert kwargs["product"] == "prod_publish_1"
        assert kwargs["unit_amount"] == 1900
        assert kwargs["currency"] == "sek"
        assert kwargs["idempotency_key"] == (
            f"course:{COURSE_ID}:price:prod_publish_1:1900:sek"
        )
        return {"id": "price_publish_1"}

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    return calls


def _install_stripe_fail_fakes(monkeypatch):
    def fail(*args, **kwargs):
        raise AssertionError("validation must stop before Stripe")

    monkeypatch.setattr("stripe.Product.create", fail)
    monkeypatch.setattr("stripe.Price.create", fail)
    monkeypatch.setattr("stripe.Product.retrieve", fail)
    monkeypatch.setattr("stripe.Price.retrieve", fail)


def test_publish_endpoint_is_registered():
    assert any(
        route.path == "/studio/courses/{course_id}/publish"
        and "POST" in getattr(route, "methods", set())
        for route in studio.course_lesson_router.routes
    )


async def test_publish_success_creates_mapping_and_public_sellable_state(monkeypatch):
    await _install_publish_fakes(monkeypatch)
    calls = _install_stripe_create_fakes(monkeypatch)

    course = await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)

    assert course is not None
    assert course["content_ready"] is True
    assert course["visibility"] == "public"
    assert course["stripe_product_id"] == "prod_publish_1"
    assert course["active_stripe_price_id"] == "price_publish_1"
    assert course["sellable"] is True
    assert calls == {"product_create": 1, "price_create": 1}


async def test_publish_fails_without_lessons_before_stripe(monkeypatch):
    await _install_publish_fakes(monkeypatch, lessons=[])
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="Kursen saknar lektioner"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_with_invalid_lesson_order_before_stripe(monkeypatch):
    await _install_publish_fakes(
        monkeypatch,
        lessons=[
            _lesson(id="lesson_publish_1", position=1),
            _lesson(id="lesson_publish_2", position=3),
        ],
    )
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="Lektionernas ordning"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_with_missing_content_before_stripe(monkeypatch):
    await _install_publish_fakes(
        monkeypatch,
        lessons=[_lesson(has_content=False, content_markdown=None)],
    )
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="Lektion saknar inneh"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_with_invalid_media_token_before_stripe(monkeypatch):
    await _install_publish_fakes(
        monkeypatch,
        lessons=[_lesson(content_markdown="Bild !image(missing_media)")],
    )
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="mediareferenser"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_with_non_ready_referenced_media_before_stripe(monkeypatch):
    await _install_publish_fakes(
        monkeypatch,
        lessons=[_lesson(content_markdown="Bild !image(media_1)")],
        media_by_lesson={
            "lesson_publish_1": [
                {
                    "id": "media_1",
                    "lesson_id": "lesson_publish_1",
                    "media_type": "image",
                    "kind": "image",
                    "state": "uploaded",
                }
            ]
        },
    )
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="media"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_with_invalid_price_before_stripe(monkeypatch):
    await _install_publish_fakes(monkeypatch, course=_course(price_amount_cents=0))
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(ValueError, match="pris"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_fails_for_non_owner_before_stripe(monkeypatch):
    await _install_publish_fakes(
        monkeypatch,
        course=_course(teacher_id="other_teacher"),
        owner=False,
    )
    _install_stripe_fail_fakes(monkeypatch)

    with pytest.raises(PermissionError, match="beh"):
        await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)


async def test_publish_retry_reuses_existing_stripe_mapping(monkeypatch):
    await _install_publish_fakes(monkeypatch)
    calls = _install_stripe_create_fakes(monkeypatch)

    def fake_product_retrieve(product_id: str):
        assert product_id == "prod_publish_1"
        return {
            "id": "prod_publish_1",
            "active": True,
            "metadata": {
                "course_id": COURSE_ID,
                "teacher_id": TEACHER_ID,
                "type": "course",
            },
        }

    def fake_price_retrieve(price_id: str):
        assert price_id == "price_publish_1"
        return {
            "id": "price_publish_1",
            "product": "prod_publish_1",
            "unit_amount": 1900,
            "currency": "sek",
            "active": True,
        }

    monkeypatch.setattr("stripe.Product.retrieve", fake_product_retrieve)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)

    first = await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)
    second = await courses_service.publish_course(COURSE_ID, teacher_id=TEACHER_ID)

    assert first is not None
    assert second is not None
    assert second["stripe_product_id"] == "prod_publish_1"
    assert second["active_stripe_price_id"] == "price_publish_1"
    assert calls == {"product_create": 1, "price_create": 1}


def test_publish_flow_does_not_create_commerce_or_entitlement_rows():
    publish_source = "\n".join(
        inspect.getsource(fn)
        for fn in (
            courses_service.publish_course,
            courses_service._validate_course_publish_readiness,
            courses_service._resolve_publish_stripe_mapping,
        )
    )

    assert "create_order" not in publish_source
    assert "payment" not in publish_source
    assert "create_course_enrollment" not in publish_source
