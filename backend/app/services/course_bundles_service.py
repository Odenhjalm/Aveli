from __future__ import annotations

import stripe
from starlette.concurrency import run_in_threadpool

from typing import Any, Mapping

from .. import repositories
from ..config import settings
from ..repositories import course_bundles as bundle_repo
from ..repositories import courses as courses_repo
from ..repositories import course_entitlements
from ..schemas.checkout import CheckoutCreateResponse
from ..schemas.course_bundles import (
    CourseBundleCourse,
    CourseBundleCreateRequest,
    CourseBundleResponse,
)
from . import stripe_customers as stripe_customers_service


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


async def create_bundle(
    current_user: Mapping[str, Any],
    payload: CourseBundleCreateRequest,
) -> CourseBundleResponse:
    teacher_id = str(current_user["id"])
    bundle = await bundle_repo.create_bundle(
        teacher_id=teacher_id,
        title=payload.title,
        description=payload.description,
        price_amount_cents=payload.price_amount_cents,
        currency=(payload.currency or "sek").lower(),
        is_active=payload.is_active,
    )
    if payload.course_ids:
        for idx, course_id in enumerate(payload.course_ids):
            await _ensure_course_is_owned(course_id, teacher_id)
            await bundle_repo.add_course_to_bundle(bundle["id"], course_id, position=idx)
    detailed = await get_bundle(bundle["id"], include_inactive=True)
    if not detailed:
        raise CourseBundleError("Bundle could not be created", status_code=500)
    return detailed


async def attach_course(
    current_user: Mapping[str, Any],
    bundle_id: str,
    *,
    course_id: str,
    position: int | None = None,
) -> CourseBundleResponse:
    teacher_id = str(current_user["id"])
    bundle = await bundle_repo.get_bundle(bundle_id)
    if not bundle:
        raise CourseBundleError("Paketet saknas", status_code=404)
    if str(bundle.get("teacher_id")) != teacher_id:
        raise CourseBundleError("Du kan bara ändra dina egna paket", status_code=403)
    await _ensure_course_is_owned(course_id, teacher_id)
    await bundle_repo.add_course_to_bundle(bundle_id, course_id, position=position)
    detailed = await get_bundle(bundle_id, include_inactive=True)
    if not detailed:
        raise CourseBundleError("Paketet kunde inte uppdateras", status_code=500)
    return detailed


async def list_teacher_bundles(current_user: Mapping[str, Any]) -> list[CourseBundleResponse]:
    teacher_id = str(current_user["id"])
    bundles = await bundle_repo.list_bundles(teacher_id=teacher_id, active_only=False)
    results: list[CourseBundleResponse] = []
    for bundle in bundles:
        detailed = await get_bundle(str(bundle["id"]), include_inactive=True)
        if detailed:
            results.append(detailed)
    return results


async def get_bundle(bundle_id: str, *, include_inactive: bool = False) -> CourseBundleResponse | None:
    bundle = await bundle_repo.get_bundle(bundle_id)
    if not bundle:
        return None
    if not include_inactive and not bundle.get("is_active"):
        return None
    courses = await bundle_repo.list_bundle_courses(bundle_id)
    course_models = [
        CourseBundleCourse(
            course_id=row["course_id"],
            slug=row.get("slug"),
            title=row.get("title"),
            position=row.get("position") or 0,
            price_amount_cents=row.get("price_amount_cents"),
            currency=row.get("currency"),
        )
        for row in courses
    ]
    return CourseBundleResponse(
        id=bundle["id"],
        teacher_id=bundle["teacher_id"],
        title=bundle["title"],
        description=bundle.get("description"),
        price_amount_cents=bundle["price_amount_cents"],
        currency=bundle.get("currency") or "sek",
        stripe_product_id=bundle.get("stripe_product_id"),
        stripe_price_id=bundle.get("stripe_price_id"),
        is_active=bundle.get("is_active", True),
        courses=course_models,
        payment_link=_payment_link(bundle_id),
    )


async def create_checkout_session(user: Mapping[str, Any], bundle_id: str) -> CheckoutCreateResponse:
    _require_stripe()

    bundle = await bundle_repo.get_bundle(bundle_id)
    if not bundle or not bundle.get("is_active"):
        raise CourseBundleError("Paketet är inte tillgängligt just nu", status_code=404)

    courses = await bundle_repo.list_bundle_courses(bundle_id)
    if not courses:
        raise CourseBundleError("Paketet saknar kurser", status_code=400)

    ensured_bundle = await _ensure_stripe_assets(bundle)
    price_id = ensured_bundle.get("stripe_price_id")
    if not isinstance(price_id, str):
        raise CourseBundleError("Stripe-pris saknas för paketet", status_code=502)

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
        service_id=None,
        course_id=None,
        amount_cents=int(bundle.get("price_amount_cents") or 0),
        currency=(bundle.get("currency") or "sek").lower(),
        order_type="bundle",
        metadata=metadata,
        stripe_customer_id=customer_id,
        stripe_subscription_id=None,
        connected_account_id=None,
        session_id=None,
        session_slot_id=None,
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
        raise CourseBundleError("Stripe-session saknar URL", status_code=502)

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
    courses = await bundle_repo.list_bundle_courses(bundle_id)
    if not courses:
        return
    for course in courses:
        slug = course.get("slug")
        course_id = course.get("course_id")
        if slug:
            await course_entitlements.grant_course_entitlement(
                user_id=user_id,
                course_slug=str(slug),
                stripe_customer_id=stripe_customer_id,
                payment_intent_id=payment_intent_id,
            )
        if course_id:
            await courses_repo.ensure_course_enrollment(
                user_id,
                str(course_id),
                source="purchase",
            )


async def _ensure_course_is_owned(course_id: str, teacher_id: str) -> None:
    is_owner = await courses_repo.is_course_owner(course_id, teacher_id)
    if not is_owner:
        raise CourseBundleError("Kursen tillhör inte dig", status_code=403)


async def _ensure_customer_id(user: Mapping[str, Any]) -> str:
    try:
        return await stripe_customers_service.ensure_customer_id(user)
    except RuntimeError as exc:
        raise CourseBundleError(str(exc), status_code=502) from exc


async def _ensure_stripe_assets(bundle: Mapping[str, Any]) -> Mapping[str, Any]:
    _require_stripe()
    bundle_id = str(bundle.get("id"))
    amount_cents = int(bundle.get("price_amount_cents") or 0)
    currency = (bundle.get("currency") or "sek").lower()
    if amount_cents <= 0:
        raise CourseBundleError("Paketpriset måste vara större än noll", status_code=400)

    product_id = bundle.get("stripe_product_id")
    price_id = bundle.get("stripe_price_id")

    if price_id and not product_id:
        try:
            price = await run_in_threadpool(lambda: stripe.Price.retrieve(price_id))
            product_ref = price.get("product")
            if isinstance(product_ref, str):
                product_id = product_ref
                await bundle_repo.update_bundle(
                    bundle_id,
                    {
                        "stripe_product_id": product_id,
                        "stripe_price_id": price_id,
                    },
                )
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise CourseBundleError("Kunde inte hämta Stripe-pris", status_code=502) from exc

    if not product_id:
        try:
            product = await run_in_threadpool(
                lambda: stripe.Product.create(
                    name=bundle.get("title") or "Kurs-paket",
                    metadata={"bundle_id": bundle_id, "type": "course_bundle"},
                )
            )
            product_id = product.get("id")
            if not isinstance(product_id, str):
                raise CourseBundleError("Stripe returnerade inget produkt-id", status_code=502)
            await bundle_repo.update_bundle(
                bundle_id,
                {"stripe_product_id": product_id},
            )
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise CourseBundleError("Kunde inte skapa Stripe-produkt", status_code=502) from exc

    if not price_id:
        try:
            price = await run_in_threadpool(
                lambda: stripe.Price.create(
                    product=product_id,
                    unit_amount=amount_cents,
                    currency=currency,
                )
            )
            price_id = price.get("id")
            if not isinstance(price_id, str):
                raise CourseBundleError("Stripe returnerade inget pris-id", status_code=502)
            await bundle_repo.update_bundle(
                bundle_id,
                {"stripe_price_id": price_id},
            )
        except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
            raise CourseBundleError("Kunde inte skapa Stripe-pris", status_code=502) from exc

    updated = dict(bundle)
    updated["stripe_product_id"] = product_id
    updated["stripe_price_id"] = price_id
    return updated


def _require_stripe() -> None:
    if not settings.stripe_secret_key:
        raise CourseBundleConfigError("Stripe-konfiguration saknas")
    stripe.api_key = settings.stripe_secret_key


def _default_checkout_urls() -> tuple[str, str]:
    base = (settings.frontend_base_url or "").rstrip("/")
    success_default = "aveliapp://checkout_success"
    cancel_default = "aveliapp://checkout_cancel"
    success_http = f"{base}/checkout/success" if base else None
    cancel_http = f"{base}/checkout/cancel" if base else None
    success_url = settings.checkout_success_url or success_http or success_default
    cancel_url = settings.checkout_cancel_url or cancel_http or cancel_default
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
    "create_checkout_session",
    "grant_bundle_entitlements",
    "CourseBundleError",
    "CourseBundleConfigError",
]
