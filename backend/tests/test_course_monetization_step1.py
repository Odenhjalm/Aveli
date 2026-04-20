import pytest

from app.services import checkout_service, courses_service


pytestmark = pytest.mark.anyio("asyncio")


def _course_row(**overrides):
    row = {
        "id": "course_step1",
        "teacher_id": "teacher_step1",
        "slug": "course-step1",
        "title": "Course Step 1",
        "course_group_id": "group_step1",
        "group_position": 1,
        "visibility": "draft",
        "content_ready": False,
        "price_amount_cents": None,
        "stripe_product_id": None,
        "active_stripe_price_id": None,
        "sellable": False,
        "required_enrollment_source": None,
        "drip_enabled": False,
        "drip_interval_days": None,
        "cover_media_id": None,
    }
    row.update(overrides)
    return row


async def test_create_course_with_positive_price_does_not_create_stripe_mapping(
    monkeypatch,
):
    teacher_id = "teacher_step1"

    async def fake_create_course(payload):
        assert payload["teacher_id"] == teacher_id
        assert payload["price_amount_cents"] == 1900
        return _course_row(
            teacher_id=teacher_id,
            price_amount_cents=1900,
        )

    async def fail_ensure_course_stripe_mapping(*args, **kwargs):
        raise AssertionError("create_course must not ensure Stripe mapping")

    async def fail_delete_course(*args, **kwargs):
        raise AssertionError("create_course must not roll back through Stripe mapping")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "create_course",
        fake_create_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "delete_course",
        fail_delete_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "ensure_course_stripe_mapping",
        fail_ensure_course_stripe_mapping,
        raising=True,
    )

    course = await courses_service.create_course(
        {
            "title": "Course Step 1",
            "slug": "course-step1",
            "course_group_id": "group_step1",
            "group_position": 1,
            "price_amount_cents": 1900,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
        teacher_id=teacher_id,
    )

    assert course["price_amount_cents"] == 1900
    assert course["stripe_product_id"] is None
    assert course["active_stripe_price_id"] is None
    assert course["sellable"] is False


async def test_update_course_price_change_does_not_create_stripe_mapping(
    monkeypatch,
):
    course_id = "course_step1"
    teacher_id = "teacher_step1"
    existing = _course_row(id=course_id, teacher_id=teacher_id)
    updated = _course_row(
        id=course_id,
        teacher_id=teacher_id,
        price_amount_cents=2500,
    )

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == "course_step1"
        assert slug is None
        return existing

    async def fake_is_course_owner(candidate_course_id: str, candidate_teacher_id: str):
        assert candidate_course_id == course_id
        assert candidate_teacher_id == teacher_id
        return True

    async def fake_update_course(candidate_course_id: str, patch: dict):
        assert candidate_course_id == course_id
        assert patch == {"price_amount_cents": 2500}
        return updated

    async def fail_ensure_course_stripe_mapping(*args, **kwargs):
        raise AssertionError("update_course must not ensure Stripe mapping")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
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
        "update_course",
        fake_update_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "ensure_course_stripe_mapping",
        fail_ensure_course_stripe_mapping,
        raising=True,
    )

    course = await courses_service.update_course(
        course_id,
        {"price_amount_cents": 2500},
        teacher_id=teacher_id,
    )

    assert course == updated
    assert course["stripe_product_id"] is None
    assert course["active_stripe_price_id"] is None
    assert course["sellable"] is False


async def test_draft_course_with_price_intent_remains_non_sellable(monkeypatch):
    subject = _course_row(
        id="course_step1",
        teacher_id="teacher_step1",
        price_amount_cents=1900,
    )

    async def fake_get_course_sellability_subject(course_id: str):
        assert course_id == "course_step1"
        return subject

    async def fail_update_course_sellability(*args, **kwargs):
        raise AssertionError("draft price intent must not become sellable")

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == "course_step1"
        assert slug is None
        return subject

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course_sellability_subject",
        fake_get_course_sellability_subject,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "update_course_sellability",
        fail_update_course_sellability,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )

    course = await courses_service.refresh_course_sellability("course_step1")

    assert course is not None
    assert course["sellable"] is False


def test_course_sellability_predicate_fails_closed_without_public_ready_authority():
    mapped_subject = _course_row(
        teacher_id="teacher_step1",
        price_amount_cents=1900,
        stripe_product_id="prod_course_step1",
        active_stripe_price_id="price_course_step1",
    )

    assert courses_service._is_course_sellable_subject(mapped_subject) is False
    assert (
        courses_service._is_course_sellable_subject(
            {**mapped_subject, "visibility": "draft", "content_ready": True}
        )
        is False
    )
    assert (
        courses_service._is_course_sellable_subject(
            {**mapped_subject, "visibility": "public", "content_ready": False}
        )
        is False
    )
    assert (
        courses_service._is_course_sellable_subject(
            {**mapped_subject, "visibility": "public", "content_ready": True}
        )
        is False
    )
    assert (
        courses_service._is_course_sellable_subject(
            {
                **mapped_subject,
                "visibility": "public",
                "content_ready": True,
                "required_enrollment_source": "purchase",
            }
        )
        is True
    )


async def test_checkout_uses_existing_active_price_without_creating_stripe_entities(
    monkeypatch,
):
    captured_checkout: dict[str, object] = {}

    def fail_stripe_entity_create(*args, **kwargs):
        raise AssertionError("checkout must not create Stripe Product or Price")

    def fake_session_create(**kwargs):
        captured_checkout.update(kwargs)
        return {
            "id": "cs_course_step1",
            "url": "https://stripe.test/cs_course_step1",
            "payment_intent": "pi_course_step1",
        }

    async def fake_run_in_threadpool(callback):
        return callback()

    async def fake_get_course_by_slug(slug: str):
        assert slug == "course-step1"
        return _course_row(
            id="course_step1",
            slug="course-step1",
            visibility="public",
            content_ready=True,
            price_amount_cents=1900,
            stripe_product_id="prod_course_step1",
            active_stripe_price_id="price_course_step1",
            sellable=True,
        )

    async def fake_ensure_customer_id(user):
        assert user["id"] == "user_step1"
        return "cus_course_step1"

    async def fake_create_order(**kwargs):
        assert kwargs["course_id"] == "course_step1"
        assert kwargs["amount_cents"] == 1900
        assert kwargs["metadata"]["price_id"] == "price_course_step1"
        return {"id": "order_course_step1"}

    async def fake_set_order_checkout_reference(**kwargs):
        assert kwargs == {
            "order_id": "order_course_step1",
            "checkout_id": "cs_course_step1",
            "payment_intent": "pi_course_step1",
        }

    monkeypatch.setattr(checkout_service, "_require_stripe", lambda: None)
    monkeypatch.setattr(
        checkout_service,
        "run_in_threadpool",
        fake_run_in_threadpool,
        raising=True,
    )
    monkeypatch.setattr(
        checkout_service.courses_repo,
        "get_course_by_slug",
        fake_get_course_by_slug,
        raising=True,
    )
    monkeypatch.setattr(
        checkout_service.stripe_customers_service,
        "ensure_customer_id",
        fake_ensure_customer_id,
        raising=True,
    )
    monkeypatch.setattr(
        checkout_service.repositories,
        "create_order",
        fake_create_order,
        raising=True,
    )
    monkeypatch.setattr(
        checkout_service.repositories,
        "set_order_checkout_reference",
        fake_set_order_checkout_reference,
        raising=True,
    )
    monkeypatch.setattr(
        checkout_service,
        "_default_checkout_urls",
        lambda: ("https://checkout.test/success", "https://checkout.test/cancel"),
        raising=True,
    )
    monkeypatch.setattr("stripe.Product.create", fail_stripe_entity_create)
    monkeypatch.setattr("stripe.Price.create", fail_stripe_entity_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)

    response = await checkout_service.create_course_checkout(
        {"id": "user_step1"},
        "course-step1",
    )

    assert response.url == "https://stripe.test/cs_course_step1"
    assert response.session_id == "cs_course_step1"
    assert response.order_id == "order_course_step1"
    assert captured_checkout["line_items"] == [
        {"price": "price_course_step1", "quantity": 1}
    ]
