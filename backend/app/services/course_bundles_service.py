from __future__ import annotations

import stripe
from psycopg import Error as PsycopgError
from psycopg import errors as psycopg_errors
from starlette.concurrency import run_in_threadpool

from typing import Any, Mapping, Sequence
from uuid import UUID

from .. import repositories
from .. import stripe_mode
from ..config import settings
from ..repositories import course_bundles as bundle_repo
from ..repositories import courses as courses_repo
from ..schemas.checkout import CheckoutCreateResponse
from ..schemas.course_bundles import (
    CourseBundleCourse,
    CourseBundleCreateRequest,
    CourseBundleResponse,
)
from . import stripe_customers as stripe_customers_service

RETURN_PATH = "checkout/return?session_id={CHECKOUT_SESSION_ID}"
CANCEL_PATH = "checkout/cancel"
RETURN_DEEP_LINK = f"aveliapp://{RETURN_PATH}"
CANCEL_DEEP_LINK = "aveliapp://checkout/cancel"
_CANONICAL_BUNDLE_STRIPE_CURRENCY = "sek"


class CourseBundleError(Exception):
    status_code = 400

    def __init__(self, detail: str, *, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code is not None:
            self.status_code = status_code
        self.detail = detail


class CourseBundleConfigError(CourseBundleError):
    def __init__(self, detail: str) -> None:
        super().__init__(detail, status_code=503)


def map_bundle_database_error(exc: PsycopgError) -> CourseBundleError:
    if isinstance(exc, (psycopg_errors.UndefinedColumn, psycopg_errors.UndefinedTable)):
        return CourseBundleError(
            "Paketfunktionen är inte tillgänglig just nu",
            status_code=503,
        )
    if isinstance(
        exc,
        (
            psycopg_errors.CheckViolation,
            psycopg_errors.ForeignKeyViolation,
            psycopg_errors.NotNullViolation,
            psycopg_errors.UniqueViolation,
        ),
    ):
        return CourseBundleError(
            "Paketet kunde inte sparas med angivna uppgifter",
            status_code=400,
        )
    return CourseBundleError("Paketet kunde inte hanteras just nu", status_code=503)


def _is_bundle_sellable_subject(
    bundle: Mapping[str, Any],
    *,
    has_courses: bool,
) -> bool:
    teacher_id = str(bundle.get("teacher_id") or "").strip()
    amount_cents = int(bundle.get("price_amount_cents") or 0)
    stripe_product_id = str(bundle.get("stripe_product_id") or "").strip()
    active_price_id = str(bundle.get("active_stripe_price_id") or "").strip()
    return (
        bool(teacher_id)
        and amount_cents > 0
        and bool(stripe_product_id)
        and bool(active_price_id)
        and has_courses
    )


async def create_bundle(
    current_user: Mapping[str, Any],
    payload: CourseBundleCreateRequest,
) -> CourseBundleResponse:
    teacher_id = str(current_user["id"])
    price_amount_cents = _validate_bundle_price_amount(payload.price_amount_cents)
    validated_course_ids = await _validate_bundle_course_candidates(
        payload.course_ids,
        teacher_id=teacher_id,
        minimum_count=2,
    )
    bundle = await bundle_repo.create_bundle(
        teacher_id=teacher_id,
        title=payload.title,
        price_amount_cents=price_amount_cents,
    )
    try:
        await ensure_bundle_stripe_mapping(str(bundle["id"]), teacher_id)
        await bundle_repo.replace_bundle_courses(str(bundle["id"]), validated_course_ids)
        await refresh_bundle_sellability(str(bundle["id"]))
    except Exception:
        await bundle_repo.delete_bundle(str(bundle["id"]))
        raise
    detailed = await get_bundle(bundle["id"], include_inactive=True)
    if not detailed:
        raise CourseBundleError("Paketet kunde inte skapas", status_code=500)
    return detailed


async def attach_course(
    current_user: Mapping[str, Any],
    bundle_id: str,
    *,
    course_id: str,
    position: int | None = None,
) -> CourseBundleResponse:
    teacher_id = str(current_user["id"])
    bundle = await bundle_repo.get_bundle_composition(bundle_id)
    if not bundle:
        raise CourseBundleError("Paketet saknas", status_code=404)
    if str(bundle.get("teacher_id")) != teacher_id:
        raise CourseBundleError("Du kan bara ändra dina egna paket", status_code=403)
    validated_course_ids = await _validate_bundle_course_candidates(
        [course_id],
        teacher_id=teacher_id,
        minimum_count=1,
    )
    current_courses = await bundle_repo.list_bundle_courses_composition(bundle_id)
    next_course_ids = _bundle_course_ids_after_attach(
        current_courses,
        validated_course_ids[0],
        position=position,
    )
    await bundle_repo.replace_bundle_courses(bundle_id, next_course_ids)
    await refresh_bundle_sellability(bundle_id)
    detailed = await get_bundle(bundle_id, include_inactive=True)
    if not detailed:
        raise CourseBundleError("Paketet kunde inte uppdateras", status_code=500)
    return detailed


async def list_teacher_bundles(current_user: Mapping[str, Any]) -> list[CourseBundleResponse]:
    teacher_id = str(current_user["id"])
    bundles = await bundle_repo.list_bundle_compositions(teacher_id=teacher_id)
    results: list[CourseBundleResponse] = []
    for bundle in bundles:
        detailed = await get_bundle(str(bundle["id"]), include_inactive=True)
        if detailed:
            results.append(detailed)
    return results


async def get_bundle(bundle_id: str, *, include_inactive: bool = False) -> CourseBundleResponse | None:
    bundle = await bundle_repo.get_bundle_composition(
        bundle_id,
        include_unsellable=include_inactive,
    )
    if not bundle:
        return None
    courses = await bundle_repo.list_bundle_courses_composition(bundle_id)
    course_models = [
        CourseBundleCourse(
            course_id=row["course_id"],
            slug=row.get("slug"),
            title=row.get("title"),
            position=int(row["position"]),
            price_amount_cents=row.get("price_amount_cents"),
        )
        for row in courses
    ]
    return CourseBundleResponse(
        id=bundle["id"],
        teacher_id=bundle["teacher_id"],
        title=bundle["title"],
        price_amount_cents=bundle["price_amount_cents"],
        courses=course_models,
    )


async def create_checkout_session(user: Mapping[str, Any], bundle_id: str) -> CheckoutCreateResponse:
    _require_stripe()

    bundle = await bundle_repo.get_bundle_mapping_subject(bundle_id)
    if not bundle or not bool(bundle.get("sellable")):
        raise CourseBundleError("Paketet är inte tillgängligt just nu", status_code=404)

    courses = await bundle_repo.list_bundle_checkout_courses(bundle_id)
    if not courses:
        raise CourseBundleError("Paketet saknar kurser", status_code=400)

    product_id = str(bundle.get("stripe_product_id") or "").strip()
    price_id = str(bundle.get("active_stripe_price_id") or "").strip()
    if not product_id or not price_id:
        raise CourseBundleError("Stripe-mappning saknas för paketet", status_code=400)

    customer_id = await _ensure_customer_id(user)
    user_id = str(user["id"])

    metadata: dict[str, Any] = {
        "user_id": user_id,
        "bundle_id": str(bundle_id),
        "checkout_type": "course_bundle",
        "course_ids": ",".join(str(row["course_id"]) for row in courses),
        "course_slugs": ",".join(str(row.get("slug") or "") for row in courses),
        "price_id": price_id,
    }

    order = await repositories.create_order(
        user_id=user_id,
        course_id=None,
        bundle_id=str(bundle_id),
        amount_cents=int(bundle.get("price_amount_cents") or 0),
        currency=_CANONICAL_BUNDLE_STRIPE_CURRENCY,
        order_type="bundle",
        metadata=metadata,
        stripe_customer_id=customer_id,
        stripe_subscription_id=None,
    )
    metadata["order_id"] = str(order["id"])

    success_url, cancel_url = _default_checkout_urls()
    try:
        session = await run_in_threadpool(
            lambda: stripe.checkout.Session.create(
                mode="payment",
                customer=customer_id,
                line_items=[{"price": price_id, "quantity": 1}],
                success_url=success_url,
                cancel_url=cancel_url,
                metadata=metadata,
                ui_mode=settings.stripe_checkout_ui_mode or "custom",
                locale="sv",
            )
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CourseBundleError("Kunde inte skapa Stripe-session", status_code=502) from exc

    await repositories.set_order_checkout_reference(
        order_id=order["id"],
        checkout_id=session.get("id"),
        payment_intent=session.get("payment_intent"),
    )

    url = session.get("url")
    if not isinstance(url, str) or not url:
        raise CourseBundleError("Stripe-session saknar betalningsadress", status_code=502)

    return CheckoutCreateResponse(
        url=url,
        session_id=session.get("id"),
        order_id=str(order["id"]),
    )


async def grant_bundle_entitlements(
    bundle_id: str,
    user_id: str,
    *,
    stripe_customer_id: str | None,
    payment_intent_id: str | None,
) -> None:
    courses = await bundle_repo.list_bundle_checkout_courses(bundle_id)
    if not courses:
        return
    for course in courses:
        course_id = course.get("course_id")
        if course_id:
            await courses_repo.create_course_enrollment(
                user_id=user_id,
                course_id=str(course_id),
                source="purchase",
            )


async def _validate_bundle_course_candidates(
    course_ids: Sequence[str],
    *,
    teacher_id: str,
    minimum_count: int,
) -> list[str]:
    exact_course_ids: list[str] = []
    for course_id in course_ids:
        raw_course_id = str(course_id or "").strip()
        if not raw_course_id:
            continue
        try:
            exact_course_ids.append(str(UUID(raw_course_id)))
        except ValueError as exc:
            raise CourseBundleError("Kurs-id är ogiltigt", status_code=400) from exc

    if len(exact_course_ids) != len(set(exact_course_ids)):
        raise CourseBundleError(
            "Paketet kan inte innehålla samma kurs flera gånger",
            status_code=400,
        )
    if len(exact_course_ids) < minimum_count:
        detail = (
            "Paketet måste innehålla minst två kurser"
            if minimum_count > 1
            else "Kurs-id krävs"
        )
        raise CourseBundleError(
            detail,
            status_code=400,
        )

    ownership_rows = await courses_repo.list_course_ownership_rows(exact_course_ids)
    ownership_by_course_id = {
        str(row["id"]): dict(row)
        for row in ownership_rows
        if row.get("id") is not None
    }

    validated_course_ids: list[str] = []
    for course_id in exact_course_ids:
        row = ownership_by_course_id.get(course_id)
        if row is None:
            raise CourseBundleError("Kursen saknas", status_code=404)

        course_teacher_id = str(row.get("teacher_id") or "").strip()
        if not course_teacher_id:
            raise CourseBundleError("Kursen saknar giltig lärarägare", status_code=422)
        if course_teacher_id != teacher_id:
            raise CourseBundleError("Kursen tillhör inte dig", status_code=403)
        validated_course_ids.append(course_id)

    return validated_course_ids


def _bundle_course_ids_after_attach(
    current_courses: Sequence[Mapping[str, Any]],
    course_id: str,
    *,
    position: int | None,
) -> list[str]:
    current_course_ids = [str(row["course_id"]) for row in current_courses]
    if course_id in current_course_ids:
        raise CourseBundleError("Kursen finns redan i paketet", status_code=400)

    target_position = int(position) if position is not None else len(current_course_ids) + 1
    if target_position < 1 or target_position > len(current_course_ids) + 1:
        raise CourseBundleError("Kursens position är ogiltig", status_code=400)

    insert_at = target_position - 1
    return [
        *current_course_ids[:insert_at],
        course_id,
        *current_course_ids[insert_at:],
    ]


def _validate_bundle_price_amount(price_amount_cents: int) -> int:
    normalized_amount = int(price_amount_cents)
    if normalized_amount <= 0:
        raise CourseBundleError("Paketpriset måste vara större än noll", status_code=400)
    return normalized_amount


async def _ensure_customer_id(user: Mapping[str, Any]) -> str:
    try:
        return await stripe_customers_service.ensure_customer_id(user)
    except RuntimeError as exc:
        raise CourseBundleError(str(exc), status_code=502) from exc


async def _stripe_create_bundle_product(
    bundle: Mapping[str, Any],
    *,
    teacher_id: str,
) -> str:
    bundle_id = str(bundle.get("id") or "").strip()
    title = str(bundle.get("title") or "").strip() or "Kurspaket"

    try:
        product = await run_in_threadpool(
            lambda: stripe.Product.create(
                name=title,
                metadata={
                    "bundle_id": bundle_id,
                    "teacher_id": teacher_id,
                    "type": "course_bundle",
                },
            )
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CourseBundleError("Kunde inte skapa Stripe-produkt för paketet", status_code=502) from exc

    product_id = product.get("id")
    if not isinstance(product_id, str) or not product_id.strip():
        raise CourseBundleError("Stripe returnerade inget produkt-id för paketet", status_code=502)
    return product_id


async def _stripe_create_bundle_price(*, product_id: str, amount_cents: int) -> str:
    try:
        price = await run_in_threadpool(
            lambda: stripe.Price.create(
                product=product_id,
                unit_amount=amount_cents,
                currency=_CANONICAL_BUNDLE_STRIPE_CURRENCY,
            )
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CourseBundleError("Kunde inte skapa Stripe-pris för paketet", status_code=502) from exc

    price_id = price.get("id")
    if not isinstance(price_id, str) or not price_id.strip():
        raise CourseBundleError("Stripe returnerade inget pris-id för paketet", status_code=502)
    return price_id


async def _stripe_retrieve_bundle_price(price_id: str) -> Mapping[str, Any]:
    try:
        price = await run_in_threadpool(lambda: stripe.Price.retrieve(price_id))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise CourseBundleError("Kunde inte läsa Stripe-pris för paketet", status_code=502) from exc
    if not isinstance(price, Mapping):
        raise CourseBundleError("Stripe returnerade ogiltigt prissvar för paketet", status_code=502)
    return price


async def ensure_bundle_stripe_mapping(bundle_id: str, teacher_id: str) -> Mapping[str, Any]:
    normalized_bundle_id = str(bundle_id or "").strip()
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_bundle_id:
        raise ValueError("Paket-id krävs")
    if not normalized_teacher_id:
        raise CourseBundleError("Paketägare krävs", status_code=403)

    bundle = await bundle_repo.get_bundle_mapping_subject(normalized_bundle_id)
    if bundle is None:
        raise CourseBundleError("Paketet saknas", status_code=404)
    if str(bundle.get("teacher_id") or "").strip() != normalized_teacher_id:
        raise CourseBundleError("Du kan bara ändra dina egna paket", status_code=403)

    amount_cents = _validate_bundle_price_amount(bundle.get("price_amount_cents"))

    _require_stripe()

    product_id = str(bundle.get("stripe_product_id") or "").strip() or None
    active_price_id = str(bundle.get("active_stripe_price_id") or "").strip() or None

    if active_price_id and not product_id:
        raise CourseBundleError("Paketets Stripe-mappning är ofullständig", status_code=502)

    if product_id is None:
        product_id = await _stripe_create_bundle_product(
            bundle,
            teacher_id=normalized_teacher_id,
        )

    desired_price_id = active_price_id
    if active_price_id:
        price = await _stripe_retrieve_bundle_price(active_price_id)
        mapped_product_id = str(price.get("product") or "").strip()
        if mapped_product_id != product_id:
            raise CourseBundleError("Paketets Stripe-mappning är inkonsekvent", status_code=502)

        unit_amount = price.get("unit_amount")
        currency = str(price.get("currency") or "").strip().lower()
        is_active = bool(price.get("active", True))
        if (
            not is_active
            or unit_amount != amount_cents
            or currency != _CANONICAL_BUNDLE_STRIPE_CURRENCY
        ):
            desired_price_id = await _stripe_create_bundle_price(
                product_id=product_id,
                amount_cents=amount_cents,
            )
    else:
        desired_price_id = await _stripe_create_bundle_price(
            product_id=product_id,
            amount_cents=amount_cents,
        )

    if desired_price_id is None:
        raise CourseBundleError("Paketets Stripe-pris kunde inte fastställas", status_code=502)

    if (
        str(bundle.get("stripe_product_id") or "").strip() == product_id
        and str(bundle.get("active_stripe_price_id") or "").strip() == desired_price_id
    ):
        refreshed = await refresh_bundle_sellability(normalized_bundle_id)
        return dict(refreshed) if refreshed is not None else dict(bundle)

    updated = await bundle_repo.update_bundle_stripe_mapping(
        normalized_bundle_id,
        stripe_product_id=product_id,
        active_stripe_price_id=desired_price_id,
    )
    if updated is None:
        raise CourseBundleError("Paketets Stripe-mappning kunde inte sparas", status_code=500)
    refreshed = await refresh_bundle_sellability(normalized_bundle_id)
    return dict(refreshed) if refreshed is not None else dict(updated)


async def refresh_bundle_sellability(bundle_id: str) -> Mapping[str, Any] | None:
    normalized_bundle_id = str(bundle_id or "").strip()
    if not normalized_bundle_id:
        raise ValueError("Paket-id krävs")

    bundle = await bundle_repo.get_bundle_mapping_subject(normalized_bundle_id)
    if bundle is None:
        return None

    courses = await bundle_repo.list_bundle_courses_composition(normalized_bundle_id)
    target_sellable = _is_bundle_sellable_subject(
        bundle,
        has_courses=bool(courses),
    )
    current_sellable = bool(bundle.get("sellable"))
    if current_sellable != target_sellable:
        updated = await bundle_repo.update_bundle_sellability(
            normalized_bundle_id,
            sellable=target_sellable,
        )
        return dict(updated) if updated is not None else None

    return dict(bundle)


def _require_stripe() -> None:
    try:
        context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        raise CourseBundleConfigError(str(exc)) from exc
    stripe.api_key = context.secret_key


def _default_checkout_urls() -> tuple[str, str]:
    base = (settings.frontend_base_url or "").rstrip("/")
    success_http = f"{base}/{RETURN_PATH}" if base else None
    cancel_http = f"{base}/{CANCEL_PATH}" if base else None
    success_url = settings.checkout_success_url or success_http or RETURN_DEEP_LINK
    cancel_url = settings.checkout_cancel_url or cancel_http or CANCEL_DEEP_LINK
    return success_url, cancel_url


def _payment_link(bundle_id: str) -> str:
    base = (
        settings.stripe_checkout_base
        or settings.frontend_base_url
        or "https://aveli.app"
    )
    return f"{base.rstrip('/')}/pay/bundle/{bundle_id}"


__all__ = [
    "create_bundle",
    "attach_course",
    "get_bundle",
    "list_teacher_bundles",
    "refresh_bundle_sellability",
    "ensure_bundle_stripe_mapping",
    "create_checkout_session",
    "grant_bundle_entitlements",
    "CourseBundleError",
    "CourseBundleConfigError",
    "map_bundle_database_error",
]
