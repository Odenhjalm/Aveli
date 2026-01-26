from __future__ import annotations

from typing import Any, Mapping, Sequence

import stripe
from starlette.concurrency import run_in_threadpool

from psycopg.types.json import Jsonb

from ..repositories import (
    courses as courses_repo,
    get_latest_order_for_course,
    get_latest_subscription,
    get_profile,
)
from ..utils.lesson_content import serialize_audio_embeds
from ..utils import media_signer


CoursePayload = Mapping[str, Any]
ModulePayload = Mapping[str, Any]
LessonPayload = Mapping[str, Any]

_INACTIVE_SUBSCRIPTION_STATUSES: set[str | None] = {
    None,
    "canceled",
    "unpaid",
    "incomplete_expired",
}


def _is_admin_profile(profile: Mapping[str, Any] | None) -> bool:
    if not profile:
        return False
    if profile.get("is_admin"):
        return True
    role = (profile.get("role_v2") or "").lower()
    return role == "admin"


def _has_active_subscription(
    profile: Mapping[str, Any] | None,
    subscription: Mapping[str, Any] | None,
) -> bool:
    if _is_admin_profile(profile):
        return True
    status_value = (subscription or {}).get("status")
    return status_value not in _INACTIVE_SUBSCRIPTION_STATUSES


def _normalize_value(value: Any) -> Any:
    if isinstance(value, Jsonb):
        return value.obj
    return value


def _materialize_mapping(row: Mapping[str, Any]) -> dict[str, Any]:
    return {key: _normalize_value(val) for key, val in row.items()}


def _materialize_optional_row(row: Mapping[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return _materialize_mapping(row)


def _materialize_rows(rows: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return [_materialize_mapping(row) for row in rows]


async def fetch_course(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> dict[str, Any] | None:
    """Wrapper around the repository with room for validation/permissions."""
    if slug and not course_id:
        row = await courses_repo.get_course_by_slug(slug)
    else:
        row = await courses_repo.get_course(course_id=course_id, slug=slug)
    return _materialize_optional_row(row)


async def list_courses(
    *,
    teacher_id: str | None = None,
    status: str | None = None,
    limit: int | None = None,
) -> Sequence[dict[str, Any]]:
    """Return courses after future policy checks."""
    rows = await courses_repo.list_courses(
        teacher_id=teacher_id,
        status=status,
        limit=limit,
    )
    return _materialize_rows(rows)


async def list_public_courses(
    *,
    published_only: bool = True,
    free_intro: bool | None = None,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[dict[str, Any]]:
    """List courses for the public catalog."""
    rows = await courses_repo.list_public_courses(
        published_only=published_only,
        free_intro=free_intro,
        search=search,
        limit=limit,
    )
    return _materialize_rows(rows)


async def create_course(payload: CoursePayload) -> dict[str, Any]:
    """Create a course after upcoming validation hooks."""
    return await courses_repo.create_course(payload)


async def update_course(
    course_id: str,
    payload: CoursePayload,
) -> dict[str, Any] | None:
    """Update an existing course and return the new state."""
    return await courses_repo.update_course(course_id, payload)


async def delete_course(course_id: str) -> bool:
    """Delete a course; additional side-effects land here later."""
    return await courses_repo.delete_course(course_id)


async def list_modules(course_id: str) -> Sequence[dict[str, Any]]:
    """Return ordered modules for a course."""
    rows = await courses_repo.list_modules(course_id)
    return _materialize_rows(rows)


async def create_module(
    course_id: str,
    *,
    title: str,
    position: int = 0,
    module_id: str | None = None,
) -> dict[str, Any]:
    row = await courses_repo.create_module(
        course_id,
        title=title,
        position=position,
        module_id=module_id,
    )
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def upsert_module(
    course_id: str,
    payload: ModulePayload,
) -> dict[str, Any]:
    """Create or update a module."""
    row = await courses_repo.upsert_module(course_id, payload)
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def delete_module(module_id: str) -> bool:
    """Remove a module using the repository."""
    return await courses_repo.delete_module(module_id)


async def list_lessons(module_id: str) -> Sequence[dict[str, Any]]:
    """Return lessons for the supplied module."""
    rows = await courses_repo.list_lessons(module_id)
    return _materialize_rows(rows)


async def create_lesson(
    module_id: str,
    *,
    title: str,
    content_markdown: str | None = None,
    position: int = 0,
    is_intro: bool = False,
    lesson_id: str | None = None,
) -> dict[str, Any]:
    content_value = content_markdown
    if isinstance(content_value, str) and content_value:
        content_value = serialize_audio_embeds(content_value)

    row = await courses_repo.create_lesson(
        module_id,
        title=title,
        content_markdown=content_value,
        position=position,
        is_intro=is_intro,
        lesson_id=lesson_id,
    )
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def list_lesson_media(lesson_id: str) -> Sequence[dict[str, Any]]:
    """Return media entries for a lesson with download URLs."""
    rows = await courses_repo.list_lesson_media(lesson_id)
    items: list[dict[str, Any]] = []
    for row in rows:
        item = _materialize_mapping(row)
        if not item.get("storage_bucket") and not item.get("media_asset_id"):
            item["storage_bucket"] = "lesson-media"
        if not item.get("media_asset_id"):
            media_signer.attach_media_links(item)
        items.append(item)
    return items


async def user_has_global_course_access(user_id: str) -> bool:
    """Return True when the user can access all courses (subscription/admin)."""
    profile = await get_profile(user_id)
    subscription = await get_latest_subscription(user_id)
    return _has_active_subscription(profile, subscription)


async def list_home_audio_media(
    user_id: str,
    *,
    limit: int = 20,
) -> list[dict[str, Any]]:
    rows = await courses_repo.list_home_audio_media(
        user_id,
        include_all_courses=False,
        limit=limit,
    )
    items: list[dict[str, Any]] = []
    for row in rows:
        item = _materialize_mapping(row)
        if not item.get("media_asset_id") and not item.get("storage_bucket"):
            item["storage_bucket"] = "lesson-media"
        if not item.get("media_asset_id"):
            media_signer.attach_media_links(item)
        items.append(item)
    return items


async def upsert_lesson(
    module_id: str,
    payload: LessonPayload,
) -> dict[str, Any]:
    """Create or update lesson data."""
    lesson_payload: dict[str, Any] = dict(payload)
    content_value = lesson_payload.get("content_markdown")
    if isinstance(content_value, str) and content_value:
        serialized = serialize_audio_embeds(content_value)
        lesson_payload["content_markdown"] = serialized

    row = await courses_repo.upsert_lesson(module_id, lesson_payload)
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def delete_lesson(lesson_id: str) -> bool:
    """Delete a lesson via the repository layer."""
    return await courses_repo.delete_lesson(lesson_id)


async def reorder_lessons(
    module_id: str,
    lesson_ids_in_order: Sequence[str],
) -> None:
    """Adjust lesson ordering for a module."""
    await courses_repo.reorder_lessons(module_id, lesson_ids_in_order)


async def fetch_module(module_id: str) -> dict[str, Any] | None:
    """Fetch single module by id."""
    row = await courses_repo.get_module(module_id)
    return _materialize_optional_row(row)


async def get_module_course_id(module_id: str) -> str | None:
    """Return parent course id for module."""
    return await courses_repo.get_module_course_id(module_id)


async def list_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    """List lessons across all modules for a course."""
    rows = await courses_repo.list_course_lessons(course_id)
    return _materialize_rows(rows)


async def list_my_courses(user_id: str) -> Sequence[dict[str, Any]]:
    """List courses the user is enrolled in."""
    rows = await courses_repo.list_my_courses(user_id)
    return _materialize_rows(rows)


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    """Return a lesson by its id."""
    row = await courses_repo.get_lesson(lesson_id)
    return _materialize_optional_row(row)


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    """Return (module_id, course_id) for a lesson."""
    return await courses_repo.get_lesson_course_ids(lesson_id)


async def is_course_owner(user_id: str, course_id: str) -> bool:
    """Check if the user is the course owner."""
    return await courses_repo.is_course_owner(course_id, user_id)


async def get_free_course_limit() -> int:
    """Return the configured free intro course limit."""
    return await courses_repo.get_free_course_limit()


async def free_consumed_count(user_id: str) -> int:
    """Return how many free intro courses the user has consumed."""
    return await courses_repo.count_free_intro_enrollments(user_id)


async def is_user_enrolled(user_id: str, course_id: str) -> bool:
    """Check whether the user is enrolled in the course."""
    return await courses_repo.is_enrolled(user_id, course_id)


async def enroll_free_intro(user_id: str, course_id: str) -> dict[str, Any]:
    """Enroll a user in a free intro course respecting subscription limits."""
    profile = await get_profile(user_id)
    subscription = await get_latest_subscription(user_id)
    has_subscription = _has_active_subscription(profile, subscription)
    free_limit = await get_free_course_limit()

    result = await courses_repo.enroll_free_intro(
        user_id,
        course_id,
        free_limit=free_limit,
        has_active_subscription=has_subscription,
    )
    if "limit" not in result:
        result["limit"] = free_limit
    if result.get("status") == "enrolled":
        return result
    if "consumed" not in result:
        result["consumed"] = await free_consumed_count(user_id)
    return result


async def latest_order_for_course(user_id: str, course_id: str) -> dict[str, Any] | None:
    """Return the latest order for the given course/user pair."""
    return await get_latest_order_for_course(user_id, course_id)


async def course_access_snapshot(user_id: str, course_id: str) -> dict[str, Any]:
    """Return an access snapshot for course gating logic."""
    enrolled = await is_user_enrolled(user_id, course_id)
    latest_order = await latest_order_for_course(user_id, course_id)
    free_consumed = await free_consumed_count(user_id)
    free_limit = await get_free_course_limit()
    profile = await get_profile(user_id)
    subscription = await get_latest_subscription(user_id)
    is_admin = _is_admin_profile(profile)
    has_active_subscription = _has_active_subscription(profile, subscription)
    has_access = enrolled or has_active_subscription or is_admin
    return {
        "enrolled": enrolled,
        "has_active_subscription": has_active_subscription,
        "has_access": has_access,
        "free_consumed": free_consumed,
        "free_limit": free_limit,
        "latest_order": latest_order,
    }


async def course_quiz_info(
    course_id: str,
    user_id: str | None,
) -> dict[str, Any]:
    """Return quiz metadata and certification state for the user."""
    quiz = await courses_repo.get_course_quiz(course_id)
    certified = False
    if user_id:
        certified = await courses_repo.is_user_certified_for_course(user_id, course_id)
    return {
        "quiz_id": quiz.get("id") if quiz else None,
        "certified": certified,
    }


async def quiz_questions(quiz_id: str) -> Sequence[dict[str, Any]]:
    """List questions for a quiz."""
    rows = await courses_repo.list_quiz_questions(quiz_id)
    return _materialize_rows(rows)


async def submit_quiz(quiz_id: str, user_id: str, answers: Mapping[str, Any]) -> dict[str, Any]:
    """Submit quiz answers and return grading outcome."""
    return await courses_repo.submit_quiz_answers(quiz_id, user_id, answers)


async def ensure_course_stripe_assets(course: Mapping[str, Any]) -> dict[str, Any]:
    """Ensure a course has corresponding Stripe product and price ids."""
    if not course:
        raise ValueError("course payload is required")
    materialized = dict(course)
    course_id = materialized.get("id")
    if not course_id:
        raise ValueError("course id is required")
    course_id_str = str(course_id)
    slug = str(materialized.get("slug") or "")
    amount_cents = int(materialized.get("price_amount_cents") or 0)
    currency = (materialized.get("currency") or "sek").lower()

    product_id = materialized.get("stripe_product_id")
    price_id = materialized.get("stripe_price_id")

    if price_id and not product_id:
        try:
            price = await run_in_threadpool(lambda: stripe.Price.retrieve(price_id))
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise RuntimeError("Failed to retrieve Stripe price for course") from exc
        product_ref = price.get("product")
        if isinstance(product_ref, str):
            product_id = product_ref
            await courses_repo.update_course_stripe_ids(course_id_str, product_id, price_id)
            materialized["stripe_product_id"] = product_id

    if not product_id:
        try:
            product = await run_in_threadpool(
                lambda: stripe.Product.create(
                    name=materialized.get("title") or slug or "Course",
                    metadata={"course_id": course_id_str, "slug": slug},
                )
            )
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise RuntimeError("Failed to create Stripe product for course") from exc
        product_id = product.get("id")
        if not isinstance(product_id, str):
            raise RuntimeError("Stripe did not return a product id")
        await courses_repo.update_course_stripe_ids(course_id_str, product_id, price_id)
        materialized["stripe_product_id"] = product_id

    if not price_id:
        if amount_cents <= 0:
            raise RuntimeError("price_amount_cents must be set before creating a Stripe price")
        product_ref = materialized.get("stripe_product_id")
        if not isinstance(product_ref, str):
            raise RuntimeError("Stripe product id missing for course price creation")
        try:
            price = await run_in_threadpool(
                lambda: stripe.Price.create(
                    product=product_ref,
                    unit_amount=amount_cents,
                    currency=currency,
                )
            )
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise RuntimeError("Failed to create Stripe price for course") from exc
        price_id = price.get("id")
        if not isinstance(price_id, str):
            raise RuntimeError("Stripe did not return a price id")
        await courses_repo.update_course_stripe_ids(course_id_str, product_ref, price_id)
        materialized["stripe_price_id"] = price_id

    return materialized


__all__ = [
    "CoursePayload",
    "ModulePayload",
    "LessonPayload",
    "fetch_course",
    "list_courses",
    "list_public_courses",
    "create_course",
    "update_course",
    "delete_course",
    "list_modules",
    "create_module",
    "upsert_module",
    "delete_module",
    "list_lessons",
    "create_lesson",
    "list_lesson_media",
    "list_home_audio_media",
    "upsert_lesson",
    "delete_lesson",
    "reorder_lessons",
    "fetch_module",
    "get_module_course_id",
    "list_course_lessons",
    "list_my_courses",
    "fetch_lesson",
    "lesson_course_ids",
    "is_course_owner",
    "get_free_course_limit",
    "free_consumed_count",
    "is_user_enrolled",
    "enroll_free_intro",
    "latest_order_for_course",
    "course_access_snapshot",
    "course_quiz_info",
    "ensure_course_stripe_assets",
    "quiz_questions",
    "submit_quiz",
    "user_has_global_course_access",
]
