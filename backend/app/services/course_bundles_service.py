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
    CourseBundleUpdateRequest,
)
from . import stripe_customers as stripe_customers_service

RETURN_PATH = "checkout/return?session_id={CHECKOUT_SESSION_ID}"
CANCEL_PATH = "checkout/cancel"
RETURN_DEEP_LINK = f"aveliapp://{RETURN_PATH}"
CANCEL_DEEP_LINK = "aveliapp://checkout/cancel"
_CANONICAL_BUNDLE_STRIPE_CURRENCY = "sek"
_CREATE_FIELDS = frozenset({"title", "price_amount_cents", "course_ids"})
_UPDATE_FIELDS = frozenset({"title", "price_amount_cents", "course_ids"})
_ATTACH_FIELDS = frozenset({"course_id", "position"})
_FORBIDDEN_CLIENT_FIELDS = frozenset(
    {
        "teacher_id",
        "description",
        "currency",
        "is_active",
        "sellable",
        "stripe_product_id",
        "active_stripe_price_id",
        "created_at",
        "updated_at",
    }
)


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


def parse_create_request(payload: Any) -> CourseBundleCreateRequest:
    data = _payload_mapping(payload)
    _reject_unauthorized_fields(data, allowed_fields=_CREATE_FIELDS)
    return CourseBundleCreateRequest(
        title=_required_title(data),
        price_amount_cents=_required_price_amount(data),
        course_ids=_required_course_ids(data),
    )


def parse_update_request(payload: Any) -> CourseBundleUpdateRequest:
    data = _payload_mapping(payload)
    _reject_unauthorized_fields(data, allowed_fields=_UPDATE_FIELDS)
    if not data:
        raise CourseBundleError("Inga paketändringar angavs", status_code=400)

    title = _optional_title(data)
    price_amount_cents = _optional_price_amount(data)
    course_ids = _optional_course_ids(data)
    return CourseBundleUpdateRequest(
        title=title,
        price_amount_cents=price_amount_cents,
        course_ids=course_ids,
    )


def parse_attach_request(payload: Any) -> tuple[str, int | None]:
    data = _payload_mapping(payload)
    _reject_unauthorized_fields(data, allowed_fields=_ATTACH_FIELDS)
    raw_course_id = data.get("course_id")
    if not isinstance(raw_course_id, str) or not raw_course_id.strip():
        raise CourseBundleError("Kurs-id krävs", status_code=400)

    position: int | None = None
    if "position" in data and data["position"] is not None:
        raw_position = data["position"]
        if isinstance(raw_position, bool) or not isinstance(raw_position, int):
            raise CourseBundleError("Kursens position är ogiltig", status_code=400)
        if raw_position < 1:
            raise CourseBundleError("Kursens position är ogiltig", status_code=400)
        position = raw_position

    return raw_course_id, position


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
        return CourseBundleError("Paketet kunde inte sparas med angivna uppgifter", status_code=400)
    return CourseBundleError("Paketet kunde inte hanteras just nu", status_code=503)


def map_bundle_snapshot_database_error(exc: PsycopgError) -> CourseBundleError:
    if isinstance(exc, (psycopg_errors.UndefinedColumn, psycopg_errors.UndefinedTable)):
        return CourseBundleError(
            "Paketfunktionen är inte tillgänglig just nu",
            status_code=503,
        )
    return CourseBundleError("Paketköpet kunde inte förberedas just nu", status_code=503)


def _payload_mapping(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, Mapping):
        raise CourseBundleError("Paketförfrågan är ogiltig", status_code=400)
    return dict(payload)


def _reject_unauthorized_fields(
    data: Mapping[str, Any],
    *,
    allowed_fields: frozenset[str],
) -> None:
    unauthorized_fields = set(data) - allowed_fields
    if unauthorized_fields:
        raise CourseBundleError(
            "Paketförfrågan innehåller otillåtna fält",
            status_code=400,
        )


def _required_title(data: Mapping[str, Any]) -> str:
    if "title" not in data:
        raise CourseBundleError("Paketets titel krävs", status_code=400)
    return _validated_title(data["title"])


def _optional_title(data: Mapping[str, Any]) -> str | None:
    if "title" not in data:
        return None
    return _validated_title(data["title"])


def _validated_title(value: Any) -> str:
    if not isinstance(value, str):
        raise CourseBundleError("Paketets titel är ogiltig", status_code=400)
    title = value.strip()
    if len(title) < 2:
        raise CourseBundleError("Paketets titel är ogiltig", status_code=400)
    return title


def _required_price_amount(data: Mapping[str, Any]) -> int:
    if "price_amount_cents" not in data:
        raise CourseBundleError("Paketpris krävs", status_code=400)
    return _validate_bundle_price_amount(data["price_amount_cents"])


def _optional_price_amount(data: Mapping[str, Any]) -> int | None:
    if "price_amount_cents" not in data:
        return None
    return _validate_bundle_price_amount(data["price_amount_cents"])


def _required_course_ids(data: Mapping[str, Any]) -> list[str]:
    if "course_ids" not in data:
        raise CourseBundleError("Paketet måste innehålla minst två kurser", status_code=400)
    return _validated_course_id_list(data["course_ids"])


def _optional_course_ids(data: Mapping[str, Any]) -> list[str] | None:
    if "course_ids" not in data:
        return None
    return _validated_course_id_list(data["course_ids"])


def _validated_course_id_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        raise CourseBundleError("Paketets kurslista är ogiltig", status_code=400)
    course_ids: list[str] = []
    for course_id in value:
        if not isinstance(course_id, str) or not course_id.strip():
            raise CourseBundleError("Kurs-id är ogiltigt", status_code=400)
        course_ids.append(course_id.strip())
    return course_ids


def _is_bundle_sellable_subject(
    bundle: Mapping[str, Any],
    *,
    courses: Sequence[Mapping[str, Any]],
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
        and _bundle_courses_are_sellable(courses, teacher_id=teacher_id)
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
        require_sellable=True,
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


async def update_bundle(
    current_user: Mapping[str, Any],
    bundle_id: str,
    payload: CourseBundleUpdateRequest,
) -> CourseBundleResponse:
    if (
        payload.title is None
        and payload.price_amount_cents is None
        and payload.course_ids is None
    ):
        raise CourseBundleError("Inga paketändringar angavs", status_code=400)

    teacher_id = str(current_user["id"])
    bundle = await bundle_repo.get_bundle_mapping_subject(bundle_id)
    if not bundle:
        raise CourseBundleError("Paketet saknas", status_code=404)
    if str(bundle.get("teacher_id")) != teacher_id:
        raise CourseBundleError("Du kan bara ändra dina egna paket", status_code=403)

    current_courses = await bundle_repo.list_bundle_courses_composition(bundle_id)
    requested_course_ids = (
        list(payload.course_ids)
        if payload.course_ids is not None
        else [str(row["course_id"]) for row in current_courses]
    )
    validated_course_ids = await _validate_bundle_course_candidates(
        requested_course_ids,
        teacher_id=teacher_id,
        minimum_count=2,
        require_sellable=True,
    )

    price_amount_cents = (
        _validate_bundle_price_amount(payload.price_amount_cents)
        if payload.price_amount_cents is not None
        else None
    )
    updated = await bundle_repo.update_bundle_details(
        bundle_id,
        title=payload.title,
        price_amount_cents=price_amount_cents,
    )
    if updated is None:
        raise CourseBundleError("Paketet saknas", status_code=404)

    if payload.course_ids is not None:
        await bundle_repo.replace_bundle_courses(bundle_id, validated_course_ids)
    if price_amount_cents is not None:
        await bundle_repo.update_bundle_sellability(bundle_id, sellable=False)

    await ensure_bundle_stripe_mapping(bundle_id, teacher_id)
    await refresh_bundle_sellability(bundle_id)
    detailed = await get_bundle(bundle_id, include_inactive=True)
    if not detailed:
        raise CourseBundleError("Paketet kunde inte uppdateras", status_code=500)
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
        require_sellable=True,
    )
    current_courses = await bundle_repo.list_bundle_courses_composition(bundle_id)
    next_course_ids = _bundle_course_ids_after_attach(
        current_courses,
        validated_course_ids[0],
        position=position,
    )
    validated_next_course_ids = await _validate_bundle_course_candidates(
        next_course_ids,
        teacher_id=teacher_id,
        minimum_count=2,
        require_sellable=True,
    )
    await bundle_repo.replace_bundle_courses(bundle_id, validated_next_course_ids)
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
    if not bundle:
        raise CourseBundleError("Paketet hittades inte", status_code=404)
    amount_cents = _checkout_bundle_price_amount(bundle)
    product_id = str(bundle.get("stripe_product_id") or "").strip()
    price_id = str(bundle.get("active_stripe_price_id") or "").strip()
    if not product_id or not price_id:
        raise CourseBundleError("Paketets pris är inte tillgängligt just nu", status_code=400)

    courses = await bundle_repo.list_bundle_checkout_courses(bundle_id)
    snapshot_courses = _checkout_bundle_snapshot_courses(bundle, courses)
    target_sellable = _is_bundle_sellable_subject(bundle, courses=courses)
    if bool(bundle.get("sellable")) != target_sellable:
        await bundle_repo.update_bundle_sellability(
            bundle_id,
            sellable=target_sellable,
        )
    if not target_sellable:
        raise CourseBundleError("Paketet är inte tillgängligt just nu", status_code=404)

    customer_id = await _ensure_customer_id(user)
    user_id = str(user["id"])

    try:
        order = await repositories.create_bundle_order_with_snapshot(
            user_id=user_id,
            bundle_id=str(bundle_id),
            amount_cents=amount_cents,
            currency=_CANONICAL_BUNDLE_STRIPE_CURRENCY,
            snapshot_courses=snapshot_courses,
            metadata={"checkout_type": "bundle"},
            stripe_customer_id=customer_id,
        )
    except PsycopgError as exc:
        raise map_bundle_snapshot_database_error(exc) from exc

    metadata: dict[str, Any] = {
        "order_id": str(order["id"]),
        "bundle_id": str(bundle_id),
        "checkout_type": "bundle",
    }

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


async def _validate_bundle_course_candidates(
    course_ids: Sequence[str],
    *,
    teacher_id: str,
    minimum_count: int,
    require_sellable: bool,
) -> list[str]:
    exact_course_ids: list[str] = []
    for course_id in course_ids:
        if not isinstance(course_id, str):
            raise CourseBundleError("Kurs-id är ogiltigt", status_code=400)
        raw_course_id = course_id.strip()
        if not raw_course_id:
            raise CourseBundleError("Kurs-id är ogiltigt", status_code=400)
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

    course_rows = await bundle_repo.list_bundle_candidate_courses(exact_course_ids)
    course_by_id = {
        str(row["id"]): dict(row)
        for row in course_rows
        if row.get("id") is not None
    }

    validated_course_ids: list[str] = []
    for course_id in exact_course_ids:
        row = course_by_id.get(course_id)
        if row is None:
            raise CourseBundleError("Kursen saknas", status_code=404)

        course_teacher_id = str(row.get("teacher_id") or "").strip()
        if not course_teacher_id:
            raise CourseBundleError("Kursen saknar giltig lärarägare", status_code=422)
        if course_teacher_id != teacher_id:
            raise CourseBundleError("Kursen tillhör inte dig", status_code=403)
        if require_sellable:
            _validate_bundle_course_eligibility(row)
        validated_course_ids.append(course_id)

    return validated_course_ids


def _validate_bundle_course_eligibility(course: Mapping[str, Any]) -> None:
    if course.get("content_ready") is not True:
        raise CourseBundleError("Paketet innehåller en kurs som inte är redo", status_code=400)
    visibility = str(course.get("visibility") or "").strip()
    if visibility != "public":
        raise CourseBundleError(
            "Paketet innehåller en kurs som inte är publicerad",
            status_code=400,
        )
    if _course_sellable_value(course) is not True:
        raise CourseBundleError(
            "Paketet innehåller en kurs som inte kan säljas",
            status_code=400,
        )


def _course_sellable_value(course: Mapping[str, Any]) -> bool:
    if "course_sellable" in course:
        return course.get("course_sellable") is True
    return course.get("sellable") is True


def _bundle_courses_are_sellable(
    courses: Sequence[Mapping[str, Any]],
    *,
    teacher_id: str,
) -> bool:
    if len(courses) < 2:
        return False
    seen_course_ids: set[str] = set()
    for course in courses:
        course_id = str(course.get("course_id") or course.get("id") or "").strip()
        if not course_id or course_id in seen_course_ids:
            return False
        seen_course_ids.add(course_id)
        if str(course.get("teacher_id") or "").strip() != teacher_id:
            return False
        if course.get("content_ready") is not True:
            return False
        if str(course.get("visibility") or "").strip() != "public":
            return False
        if _course_sellable_value(course) is not True:
            return False
    return True


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
    if isinstance(price_amount_cents, bool) or not isinstance(price_amount_cents, int):
        raise CourseBundleError("Paketpriset är ogiltigt", status_code=400)
    normalized_amount = price_amount_cents
    if normalized_amount <= 0:
        raise CourseBundleError("Paketpriset måste vara större än noll", status_code=400)
    return normalized_amount


def _checkout_bundle_price_amount(bundle: Mapping[str, Any]) -> int:
    try:
        return _validate_bundle_price_amount(bundle.get("price_amount_cents"))
    except CourseBundleError as exc:
        raise CourseBundleError(
            "Paketets pris är inte tillgängligt just nu",
            status_code=400,
        ) from exc


def _checkout_bundle_snapshot_courses(
    bundle: Mapping[str, Any],
    courses: Sequence[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    if len(courses) < 2:
        raise CourseBundleError("Paketet måste innehålla minst två kurser", status_code=400)

    teacher_id = str(bundle.get("teacher_id") or "").strip()
    if not teacher_id:
        raise CourseBundleError("Paketägare krävs", status_code=403)

    snapshot_courses: list[dict[str, Any]] = []
    seen_course_ids: set[str] = set()
    for expected_position, course in enumerate(courses, start=1):
        position = course.get("position")
        if isinstance(position, bool) or not isinstance(position, int):
            raise CourseBundleError("Paketets kursordning är ogiltig", status_code=400)
        if position != expected_position:
            raise CourseBundleError("Paketets kursordning är ogiltig", status_code=400)

        course_id = str(course.get("course_id") or "").strip()
        if not course_id:
            raise CourseBundleError("Paketet innehåller en ogiltig kurs", status_code=400)
        if course_id in seen_course_ids:
            raise CourseBundleError(
                "Paketet kan inte innehålla samma kurs flera gånger",
                status_code=400,
            )
        seen_course_ids.add(course_id)

        if str(course.get("teacher_id") or "").strip() != teacher_id:
            raise CourseBundleError("Paketet innehåller en kurs med fel ägare", status_code=403)

        _validate_bundle_course_eligibility(course)
        snapshot_courses.append({"course_id": course_id, "position": position})

    return snapshot_courses


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
        courses=courses,
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
    "parse_create_request",
    "parse_update_request",
    "parse_attach_request",
    "create_bundle",
    "update_bundle",
    "attach_course",
    "get_bundle",
    "list_teacher_bundles",
    "refresh_bundle_sellability",
    "ensure_bundle_stripe_mapping",
    "create_checkout_session",
    "CourseBundleError",
    "CourseBundleConfigError",
    "map_bundle_database_error",
    "map_bundle_snapshot_database_error",
]
