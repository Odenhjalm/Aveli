from __future__ import annotations

import hashlib
import logging
import os
import re
from pathlib import Path
from typing import Any, Mapping, Sequence
from urllib.parse import quote
from uuid import UUID, uuid4

import stripe
from fastapi import HTTPException, status
from psycopg import DataError, Error as PsycopgError, IntegrityError
from psycopg import errors as psycopg_errors
from starlette.concurrency import run_in_threadpool

from ..config import settings
from .. import stripe_mode
from ..media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    media_resolver_service as canonical_media_resolver,
)
from ..repositories import courses as courses_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import runtime_media as runtime_media_repo
from ..utils import lesson_content as lesson_content_utils
from ..utils import lesson_markdown_validator
from . import lesson_playback_service
from . import media_cleanup
from . import studio_authority
from . import storage_service

logger = logging.getLogger(__name__)
_CANONICAL_COURSE_STRIPE_CURRENCY = "sek"
_COURSE_DELETE_BLOCKED_DETAIL = "Course delete blocked by dependent rows"
COURSE_CREATE_SLUG_CONFLICT_DETAIL = "Kursens identifierare är redan upptagen"
COURSE_CREATE_INVALID_DATA_DETAIL = "Kursen kunde inte skapas"
COURSE_CREATE_TECHNICAL_DETAIL = "Ett tekniskt fel uppstod vid skapande av kurs"
_COURSE_SLUG_UNIQUE_CONSTRAINT = "courses_slug_key"
_INVALID_LESSON_MARKDOWN_DETAIL = (
    "Invalid lesson markdown. Formatting must be corrected before saving."
)
_LESSON_MEDIA_TOKEN_PATTERN = re.compile(
    r"!(image|audio|video|document)\(([A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*)\)",
    re.IGNORECASE,
)

_LEARNER_MEDIA_TYPES = frozenset({"audio", "image", "video", "document"})
_LEARNER_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)
_COURSE_COVER_FORBIDDEN_PUBLIC_FIELDS = frozenset(
    {
        "cover_url",
        "coverUrl",
        "resolved_cover_url",
        "resolvedCoverUrl",
        "signed_cover_url",
        "signedCoverUrl",
        "signed_cover_url_expires_at",
        "signedCoverUrlExpiresAt",
    }
)
_COURSE_PROGRESSION_FORBIDDEN_PUBLIC_FIELDS = frozenset({"step"})


class CourseCreationError(Exception):
    status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    def __init__(self, detail: str, *, status_code: int | None = None) -> None:
        super().__init__(detail)
        if status_code is not None:
            self.status_code = status_code
        self.detail = detail


class LessonContentPreconditionRequired(Exception):
    pass


class LessonContentPreconditionFailed(Exception):
    pass


def _safe_course_create_log_value(value: Any, *, limit: int = 160) -> str | None:
    if value is None:
        return None
    text = str(value).replace("\r", " ").replace("\n", " ").strip()
    if len(text) <= limit:
        return text
    return f"{text[: limit - 3]}..."


def _course_create_db_constraint_name(exc: BaseException) -> str | None:
    diag = getattr(exc, "diag", None)
    constraint_name = getattr(diag, "constraint_name", None)
    if isinstance(constraint_name, str) and constraint_name:
        return constraint_name
    return None


def _course_create_db_log_context(
    payload: Mapping[str, Any],
    exc: BaseException,
    *,
    mapped_detail: str | None = None,
    repository_title: str | None = None,
    repository_slug: str | None = None,
) -> dict[str, Any]:
    return {
        "course_create_title": repository_title
        if repository_title is not None
        else _safe_course_create_log_value(payload.get("title")),
        "course_create_slug": repository_slug
        if repository_slug is not None
        else _safe_course_create_log_value(payload.get("slug")),
        "db_error_type": exc.__class__.__name__,
        "db_sqlstate": getattr(exc, "sqlstate", None),
        "db_constraint_name": _course_create_db_constraint_name(exc),
        "db_mapped_detail": mapped_detail,
    }


def _is_course_slug_conflict(exc: BaseException) -> bool:
    if not isinstance(exc, psycopg_errors.UniqueViolation):
        return False
    constraint_name = _course_create_db_constraint_name(exc)
    if constraint_name == _COURSE_SLUG_UNIQUE_CONSTRAINT:
        return True
    return _COURSE_SLUG_UNIQUE_CONSTRAINT in str(exc)


def map_course_create_database_error(exc: PsycopgError) -> CourseCreationError:
    if _is_course_slug_conflict(exc):
        return CourseCreationError(
            COURSE_CREATE_SLUG_CONFLICT_DETAIL,
            status_code=status.HTTP_409_CONFLICT,
        )
    if isinstance(exc, (DataError, IntegrityError)):
        return CourseCreationError(
            COURSE_CREATE_INVALID_DATA_DETAIL,
            status_code=422,
        )
    return CourseCreationError(
        COURSE_CREATE_TECHNICAL_DETAIL,
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
    )


def build_lesson_content_etag(lesson_id: str, content_markdown: str) -> str:
    payload = f"{str(lesson_id).strip()}\0{content_markdown}".encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()
    return f'"lesson-content:{digest}"'


def _if_match_contains_etag(if_match: str | None, expected_etag: str) -> bool:
    value = str(if_match or "").strip()
    if not value:
        return False
    return expected_etag in {candidate.strip() for candidate in value.split(",")}


def _course_required_enrollment_source(course: Mapping[str, Any] | None) -> str | None:
    if not course:
        return None
    required_source = str(course.get("required_enrollment_source") or "").strip().lower()
    if required_source in {"purchase", "intro_enrollment"}:
        return required_source
    return None


def build_course_access_model(course: Mapping[str, Any] | None) -> dict[str, Any]:
    required_source = _course_required_enrollment_source(course)
    return {
        "required_enrollment_source": required_source,
        "enrollable": required_source == "intro_enrollment",
        "purchasable": required_source == "purchase",
    }


def attach_course_access_model(
    courses: dict[str, Any] | list[dict[str, Any]] | None,
) -> None:
    if courses is None:
        return
    rows = [courses] if isinstance(courses, dict) else courses
    for row in rows:
        row.update(build_course_access_model(row))


def _course_teacher_payload(course: Mapping[str, Any]) -> dict[str, Any] | None:
    existing = course.get("teacher")
    if isinstance(existing, Mapping):
        return dict(existing)

    teacher_id = course.get("teacher_id")
    if teacher_id is None:
        return None

    display_name = course.get("teacher_display_name")
    if isinstance(display_name, str):
        display_name = display_name.strip() or None
    elif display_name is not None:
        display_name = None

    return {
        "user_id": teacher_id,
        "display_name": display_name,
    }


def attach_course_teacher_read_contract(
    courses: dict[str, Any] | list[dict[str, Any]] | None,
) -> None:
    if courses is None:
        return
    rows = [courses] if isinstance(courses, dict) else courses
    for row in rows:
        row["teacher"] = _course_teacher_payload(row)


def _validate_course_drip_configuration(
    *,
    drip_enabled: bool,
    drip_interval_days: int | None,
) -> None:
    if drip_enabled and drip_interval_days is None:
        raise ValueError("drip_interval_days is required when drip_enabled is true")
    if not drip_enabled and drip_interval_days is not None:
        raise ValueError("drip_interval_days must be null when drip_enabled is false")


def _reject_legacy_cover_url_write(payload: Mapping[str, Any]) -> None:
    if "cover_url" in payload:
        raise ValueError("cover_url is deprecated")


def strip_legacy_course_cover_output_fields(row: dict[str, Any]) -> None:
    for field in _COURSE_COVER_FORBIDDEN_PUBLIC_FIELDS:
        row.pop(field, None)


def reject_legacy_course_cover_output_fields(row: Mapping[str, Any]) -> None:
    forbidden = sorted(
        field for field in _COURSE_COVER_FORBIDDEN_PUBLIC_FIELDS if field in row
    )
    if forbidden:
        raise ValueError(
            "legacy course cover public fields are forbidden: " + ", ".join(forbidden)
        )


def reject_legacy_course_progression_output_fields(row: Mapping[str, Any]) -> None:
    forbidden = sorted(
        field for field in _COURSE_PROGRESSION_FORBIDDEN_PUBLIC_FIELDS if field in row
    )
    if forbidden:
        raise ValueError(
            "legacy course progression public fields are forbidden: "
            + ", ".join(forbidden)
        )


def _course_requires_stripe_mapping(course: Mapping[str, Any]) -> bool:
    amount_cents = int(course.get("price_amount_cents") or 0)
    return amount_cents > 0


def _is_course_sellable_subject(course: Mapping[str, Any]) -> bool:
    teacher_id = str(course.get("teacher_id") or "").strip()
    visibility = str(course.get("visibility") or "").strip()
    content_ready = course.get("content_ready") is True
    try:
        amount_cents = int(course.get("price_amount_cents") or 0)
    except (TypeError, ValueError):
        return False
    stripe_product_id = str(course.get("stripe_product_id") or "").strip()
    active_price_id = str(course.get("active_stripe_price_id") or "").strip()
    required_source = _course_required_enrollment_source(course)
    return (
        bool(teacher_id)
        and visibility == "public"
        and content_ready
        and amount_cents > 0
        and bool(stripe_product_id)
        and bool(active_price_id)
        and required_source == "purchase"
    )


def _course_publish_product_idempotency_key(course_id: str) -> str:
    return f"course:{course_id}:product"


def _course_publish_price_idempotency_key(
    *,
    course_id: str,
    product_id: str,
    amount_cents: int,
) -> str:
    return (
        f"course:{course_id}:price:"
        f"{product_id}:{amount_cents}:{_CANONICAL_COURSE_STRIPE_CURRENCY}"
    )


def _referenced_lesson_media_ids(markdown: str) -> set[str]:
    return {
        str(match.group(2) or "").strip()
        for match in _LESSON_MEDIA_TOKEN_PATTERN.finditer(markdown)
        if str(match.group(2) or "").strip()
    }


def _require_stripe_for_course_mapping() -> None:
    try:
        context = stripe_mode.resolve_stripe_context()
    except stripe_mode.StripeConfigurationError as exc:
        raise RuntimeError(str(exc)) from exc
    stripe.api_key = context.secret_key


async def _stripe_create_course_product(
    course: Mapping[str, Any],
    *,
    teacher_id: str,
    idempotency_key: str | None = None,
) -> str:
    course_id = str(course.get("id") or "").strip()
    title = str(course.get("title") or "").strip() or "Course"
    create_kwargs: dict[str, Any] = {
        "name": title,
        "metadata": {
            "course_id": course_id,
            "teacher_id": teacher_id,
            "type": "course",
        },
    }
    if idempotency_key:
        create_kwargs["idempotency_key"] = idempotency_key

    try:
        product = await run_in_threadpool(
            lambda: stripe.Product.create(**create_kwargs)
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise RuntimeError("Failed to create Stripe product for course") from exc

    product_id = product.get("id")
    if not isinstance(product_id, str) or not product_id.strip():
        raise RuntimeError("Stripe did not return a course product id")
    return product_id


async def _stripe_retrieve_course_product(product_id: str) -> Mapping[str, Any]:
    try:
        product = await run_in_threadpool(lambda: stripe.Product.retrieve(product_id))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise RuntimeError("Failed to load Stripe product for course") from exc
    if not isinstance(product, Mapping):
        raise RuntimeError("Stripe returned an invalid course product payload")
    return product


async def _stripe_create_course_price(
    *,
    product_id: str,
    amount_cents: int,
    idempotency_key: str | None = None,
) -> str:
    create_kwargs: dict[str, Any] = {
        "product": product_id,
        "unit_amount": amount_cents,
        "currency": _CANONICAL_COURSE_STRIPE_CURRENCY,
    }
    if idempotency_key:
        create_kwargs["idempotency_key"] = idempotency_key

    try:
        price = await run_in_threadpool(lambda: stripe.Price.create(**create_kwargs))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise RuntimeError("Failed to create Stripe price for course") from exc

    price_id = price.get("id")
    if not isinstance(price_id, str) or not price_id.strip():
        raise RuntimeError("Stripe did not return a course price id")
    return price_id


async def _stripe_retrieve_price(price_id: str) -> Mapping[str, Any]:
    try:
        price = await run_in_threadpool(lambda: stripe.Price.retrieve(price_id))
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise RuntimeError("Failed to load Stripe price for course") from exc
    if not isinstance(price, Mapping):
        raise RuntimeError("Stripe returned an invalid course price payload")
    return price


async def fetch_course(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> dict[str, Any] | None:
    row = await courses_repo.get_course(course_id=course_id, slug=slug)
    course = dict(row) if row else None
    if course is not None:
        attach_course_access_model(course)
        attach_course_teacher_read_contract(course)
        await attach_course_cover_read_contract(course)
    return course


async def fetch_course_pricing(slug: str) -> dict[str, Any] | None:
    row = await courses_repo.get_course_pricing_by_slug(slug)
    return dict(row) if row else None


async def fetch_course_public_content(course_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_course_public_content(course_id)
    return dict(row) if row else None


async def upsert_course_public_content(
    course_id: str,
    *,
    short_description: str,
) -> dict[str, Any]:
    row = await courses_repo.upsert_course_public_content(
        course_id,
        short_description=short_description,
    )
    return dict(row)


async def fetch_course_access_subject(course_id: str) -> dict[str, Any] | None:
    return await fetch_course(course_id=course_id)


async def list_courses(
    *,
    teacher_id: str | None = None,
    limit: int | None = None,
    search: str | None = None,
) -> Sequence[dict[str, Any]]:
    rows = [
        dict(row)
        for row in await courses_repo.list_courses(
            teacher_id=teacher_id,
            limit=limit,
            search=search,
        )
    ]
    attach_course_access_model(rows)
    attach_course_teacher_read_contract(rows)
    await attach_course_cover_read_contract(rows)
    return rows


async def list_public_courses(
    *,
    search: str | None = None,
    limit: int | None = None,
    group_position: int | None = None,
) -> Sequence[dict[str, Any]]:
    rows = [
        dict(row)
        for row in await courses_repo.list_public_course_discovery(
            search=search,
            limit=limit,
            group_position=group_position,
        )
    ]
    attach_course_access_model(rows)
    attach_course_teacher_read_contract(rows)
    await attach_course_cover_read_contract(rows)
    return rows


async def fetch_public_course_detail_rows(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> Sequence[dict[str, Any]]:
    rows = list(
        await courses_repo.get_public_course_detail_rows(
            course_id=course_id,
            slug=slug,
        )
    )
    attach_course_access_model(rows)
    attach_course_teacher_read_contract(rows)
    return rows


async def list_my_courses(user_id: str) -> Sequence[dict[str, Any]]:
    rows = [dict(row) for row in await courses_repo.list_my_courses(str(user_id))]
    attach_course_access_model(rows)
    attach_course_teacher_read_contract(rows)
    await attach_course_cover_read_contract(rows)
    return rows


async def list_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_course_lessons(course_id))


async def list_course_lesson_structure(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_lesson_structure_surface(course_id))


async def list_studio_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_studio_course_lessons(course_id))


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_lesson(lesson_id)
    return dict(row) if row else None


def _normalized_surface_media_type(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized not in _LEARNER_MEDIA_TYPES:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical lesson media type is unavailable",
        )
    return normalized


def _normalized_surface_media_state(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized not in _LEARNER_MEDIA_STATES:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical lesson media state is unavailable",
        )
    return normalized


def _canonical_lesson_surface_unavailable() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        detail="Canonical lesson content is unavailable",
    )


def _require_lesson_surface_string(value: Any) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise _canonical_lesson_surface_unavailable()
    return normalized


def _require_lesson_surface_position(value: Any) -> int:
    if isinstance(value, bool) or value is None:
        raise _canonical_lesson_surface_unavailable()
    try:
        position = int(value)
    except (TypeError, ValueError) as exc:
        raise _canonical_lesson_surface_unavailable() from exc
    if position < 1:
        raise _canonical_lesson_surface_unavailable()
    return position


def _normalize_lesson_surface_markdown(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value
    raise _canonical_lesson_surface_unavailable()


def _canonical_lesson_surface_lesson(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": _require_lesson_surface_string(row.get("id")),
        "course_id": _require_lesson_surface_string(row.get("course_id")),
        "lesson_title": _require_lesson_surface_string(row.get("lesson_title")),
        "position": _require_lesson_surface_position(row.get("position")),
        "content_markdown": _normalize_lesson_surface_markdown(
            row.get("content_markdown")
        ),
    }


async def read_protected_lesson_content_surface(
    lesson_id: str,
    *,
    user_id: str,
) -> dict[str, Any] | None:
    normalized_user_id = str(user_id or "").strip()
    if not normalized_user_id:
        raise ValueError("user_id is required for protected lesson-content reads")

    rows = [
        dict(row)
        for row in await courses_repo.get_lesson_content_surface_rows(
            lesson_id=lesson_id,
            user_id=normalized_user_id,
        )
    ]
    if not rows:
        return None

    lesson = _canonical_lesson_surface_lesson(rows[0])

    media_rows: list[dict[str, Any]] = []
    seen_lesson_media_ids: set[str] = set()
    for row in rows:
        lesson_media_id = row.get("lesson_media_id")
        if lesson_media_id is None:
            continue

        normalized_lesson_media_id = _require_lesson_surface_string(lesson_media_id)
        if normalized_lesson_media_id in seen_lesson_media_ids:
            continue
        seen_lesson_media_ids.add(normalized_lesson_media_id)

        resolution = await canonical_media_resolver.resolve_lesson_media(
            normalized_lesson_media_id,
            emit_logs=False,
        )
        if (
            not resolution.is_playable
            or resolution.playback_mode != LessonMediaPlaybackMode.PIPELINE_ASSET
            or not resolution.media_asset_id
            or resolution.media_state != "ready"
        ):
            continue

        media_type = _normalized_surface_media_type(resolution.media_type)
        media_state = _normalized_surface_media_state(resolution.media_state)
        playback = await lesson_playback_service.resolve_lesson_media_playback(
            lesson_media_id=normalized_lesson_media_id,
            user_id=normalized_user_id,
        )
        resolved_url = str(playback.get("resolved_url") or "").strip()
        if not resolved_url:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Canonical media composition is unavailable",
            )

        media_rows.append(
            {
                "id": normalized_lesson_media_id,
                "lesson_id": lesson["id"],
                "media_asset_id": str(resolution.media_asset_id),
                "position": _require_lesson_surface_position(
                    row.get("lesson_media_position")
                ),
                "media_type": media_type,
                "state": media_state,
                "media": {
                    "media_id": str(resolution.media_asset_id),
                    "state": media_state,
                    "resolved_url": resolved_url,
                },
            }
        )

    return {
        "lesson": lesson,
        "media": media_rows,
    }


async def fetch_studio_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_studio_lesson(lesson_id)
    return dict(row) if row else None


def _studio_content_media_item(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "lesson_media_id": row["lesson_media_id"],
        "media_asset_id": row.get("media_asset_id"),
        "position": row["position"],
        "media_type": row["media_type"],
        "state": row["state"],
    }


async def read_studio_lesson_content(
    lesson_id: str,
    *,
    teacher_id: str,
) -> dict[str, Any] | None:
    row = await courses_repo.get_studio_lesson_content(lesson_id)
    if row is None:
        return None

    course_id = str(row.get("course_id") or "").strip()
    if not await is_course_owner(teacher_id, course_id):
        raise PermissionError("Not course owner")

    content_markdown = str(row.get("content_markdown") or "")
    media_rows = await list_studio_lesson_media(lesson_id)
    body = {
        "lesson_id": row["lesson_id"],
        "content_markdown": content_markdown,
        "media": [_studio_content_media_item(item) for item in media_rows],
    }
    return {
        "body": body,
        "etag": build_lesson_content_etag(str(row["lesson_id"]), content_markdown),
    }


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    return await courses_repo.get_lesson_course_ids(lesson_id)


async def list_lesson_media(
    lesson_id: str,
    *,
    mode: str | None = None,
    user_id: str | None = None,
) -> Sequence[dict[str, Any]]:
    rows = [dict(row) for row in await courses_repo.list_lesson_media(lesson_id)]
    normalized_rows: list[dict[str, Any]] = []
    for row in rows:
        media_type = str(row.get("media_type") or row.get("kind") or "").strip().lower()
        item = {
            "id": row["id"],
            "lesson_id": row["lesson_id"],
            "media_asset_id": row.get("media_asset_id"),
            "position": row["position"],
            "media_type": media_type,
            "kind": media_type,
            "state": row["state"],
            "media": None,
        }
        if "preview_ready" in row:
            item["preview_ready"] = bool(row.get("preview_ready"))
        if "original_name" in row:
            item["original_name"] = row.get("original_name")
        normalized_rows.append(item)

    if mode != "student_render":
        return normalized_rows

    normalized_user_id = str(user_id or "").strip()
    if not normalized_user_id:
        raise ValueError("user_id is required for student_render lesson media")

    learner_rows: list[dict[str, Any]] = []
    for item in normalized_rows:
        lesson_media_id = str(item["id"])
        resolution = await canonical_media_resolver.resolve_lesson_media(
            lesson_media_id,
            emit_logs=False,
        )
        media_asset_id = str(resolution.media_asset_id or "").strip()
        if (
            not resolution.is_playable
            or resolution.playback_mode != LessonMediaPlaybackMode.PIPELINE_ASSET
            or not media_asset_id
        ):
            learner_rows.append(item)
            continue

        try:
            playback = await lesson_playback_service.resolve_lesson_media_playback(
                lesson_media_id=lesson_media_id,
                user_id=normalized_user_id,
            )
        except HTTPException as exc:
            if exc.status_code == status.HTTP_403_FORBIDDEN:
                raise
            learner_rows.append(item)
            continue
        resolved_url = str(playback.get("resolved_url") or "").strip()
        if not resolved_url:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Canonical media composition is unavailable",
            )
        item["media"] = {
            "media_id": media_asset_id,
            "state": item["state"],
            "resolved_url": resolved_url,
        }

        learner_rows.append(item)

    return learner_rows


async def list_studio_lesson_media(lesson_id: str) -> Sequence[dict[str, Any]]:
    rows = [
        dict(row) for row in await courses_repo.list_lesson_media_for_studio(lesson_id)
    ]
    return [
        {
            "lesson_media_id": row["lesson_media_id"],
            "lesson_id": row["lesson_id"],
            "media_asset_id": row.get("media_asset_id"),
            "position": row["position"],
            "media_type": row["media_type"],
            "state": row["state"],
            "preview_ready": bool(row.get("preview_ready")),
            "original_name": row.get("original_name"),
        }
        for row in rows
    ]


async def list_home_audio_media(
    user_id: str,
    *,
    limit: int = 12,
) -> Sequence[dict[str, Any]]:
    from . import home_audio_service

    return await home_audio_service.list_home_audio_media(user_id, limit=limit)


def _normalize_cover_media_id(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _canonical_course_cover_source_prefix(course_id: str) -> str:
    return (Path("media") / "source" / "cover" / "courses" / course_id).as_posix() + "/"


def _canonical_course_cover_derived_prefix(course_id: str) -> str:
    return (
        Path("media") / "derived" / "cover" / "courses" / course_id
    ).as_posix() + "/"


def _exact_cover_media_id(value: Any) -> str | None:
    if value is None:
        return None
    normalized = str(value).strip()
    if not normalized:
        raise ValueError("cover_media_id must be a UUID or null")
    try:
        return str(UUID(normalized))
    except (TypeError, ValueError) as exc:
        raise ValueError("cover_media_id must be a UUID or null") from exc


def _require_course_cover_asset_contract(
    *,
    course_id: str,
    media_id: str,
    asset: Mapping[str, Any] | None,
) -> Mapping[str, Any]:
    if asset is None:
        raise ValueError("cover_media_id does not reference an existing media asset")

    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    state = str(asset.get("state") or "").strip().lower()
    playback_format = str(asset.get("playback_format") or "").strip().lower()
    original_object_path = (
        str(asset.get("original_object_path") or "").strip().lstrip("/")
    )
    playback_object_path = (
        str(asset.get("playback_object_path") or "").strip().lstrip("/")
    )

    if media_type != "image":
        raise ValueError("cover_media_id must reference image media")
    if purpose != "course_cover":
        raise ValueError("cover_media_id must reference course cover media")
    if not original_object_path.startswith(
        _canonical_course_cover_source_prefix(course_id)
    ):
        raise ValueError("cover_media_id is not scoped to this course")
    if state != "ready":
        raise ValueError("cover_media_id must reference ready media")
    if not playback_object_path:
        raise ValueError("cover_media_id is missing ready media output")
    if playback_format != "jpg":
        raise ValueError("cover_media_id ready media output must be jpg")
    if not playback_object_path.startswith(
        _canonical_course_cover_derived_prefix(course_id)
    ):
        raise ValueError("cover_media_id ready output is not scoped to this course")

    return asset


def _course_cover_payload_from_ready_asset(
    *,
    media_id: str,
    asset: Mapping[str, Any],
) -> dict[str, Any] | None:
    state = str(asset.get("state") or "").strip().lower()
    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    playback_object_path = str(asset.get("playback_object_path") or "").strip()
    playback_format = str(asset.get("playback_format") or "").strip().lower()
    if (
        state != "ready"
        or media_type != "image"
        or purpose != "course_cover"
        or not playback_object_path
        or playback_format != "jpg"
    ):
        return None
    resolved_url = _resolve_course_cover_delivery_url(playback_object_path)
    if not str(resolved_url or "").strip():
        return None
    return {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": resolved_url,
    }


def _course_cover_local_mode_enabled() -> bool:
    app_env = (
        os.environ.get("APP_ENV")
        or os.environ.get("ENVIRONMENT")
        or os.environ.get("ENV")
        or ""
    ).strip().lower()
    return (
        app_env == "local"
        and str(settings.mcp_mode).strip().lower() == "local"
        and not settings.cloud_runtime
    )


def _course_cover_local_relative_path(storage_path: str) -> str | None:
    normalized_path = str(storage_path or "").strip().replace("\\", "/").lstrip("/")
    bucket = str(settings.media_public_bucket or "").strip().strip("/")
    if not normalized_path or not bucket:
        return None
    relative_path = Path(normalized_path)
    if relative_path.is_absolute() or ".." in relative_path.parts:
        return None
    return (Path(bucket) / relative_path).as_posix()


def _course_cover_local_file_path(storage_path: str) -> Path | None:
    relative_path = _course_cover_local_relative_path(storage_path)
    if relative_path is None:
        return None
    media_root = Path(settings.media_root).expanduser().resolve(strict=False)
    candidate = (media_root / relative_path).resolve(strict=False)
    if not str(candidate).startswith(str(media_root)):
        return None
    return candidate


def _local_backend_base_url() -> str | None:
    for key in ("API_BASE_URL", "BACKEND_BASE_URL", "QA_API_BASE_URL", "QA_BASE_URL"):
        value = str(os.environ.get(key) or "").strip().rstrip("/")
        if value:
            return value
    raw_port = str(os.environ.get("PORT") or "8080").strip() or "8080"
    try:
        port = int(raw_port)
    except ValueError:
        return None
    if port <= 0:
        return None
    return f"http://127.0.0.1:{port}"


def _resolve_course_cover_delivery_url(storage_path: str) -> str | None:
    normalized_path = str(storage_path or "").strip()
    if not normalized_path:
        return None

    if _course_cover_local_mode_enabled():
        local_file_path = _course_cover_local_file_path(normalized_path)
        relative_path = _course_cover_local_relative_path(normalized_path)
        if (
            local_file_path is not None
            and relative_path is not None
            and local_file_path.is_file()
        ):
            base_url = _local_backend_base_url()
            if not base_url:
                logger.error(
                    "COURSE_COVER_LOCAL_BASE_URL_MISSING path=%s",
                    normalized_path,
                )
                return None
            return (
                f"{base_url}/community/meditations/audio"
                f"?path={quote(relative_path, safe='/')}"
            )

    try:
        resolved_url = storage_service.get_storage_service(
            settings.media_public_bucket
        ).public_url(normalized_path)
    except storage_service.StorageServiceError:
        return None
    resolved_value = str(resolved_url or "").strip()
    return resolved_value or None


async def _validate_course_cover_assignment(
    *,
    course_id: str,
    cover_media_id: Any,
) -> str | None:
    media_id = _exact_cover_media_id(cover_media_id)
    if media_id is None:
        return None
    asset = await media_assets_repo.get_course_cover_pipeline_asset(media_id)
    _require_course_cover_asset_contract(
        course_id=course_id,
        media_id=media_id,
        asset=asset,
    )
    cover = _course_cover_payload_from_ready_asset(
        media_id=media_id,
        asset=asset,
    )
    if cover is None or cover.get("state") != "ready" or not cover.get("resolved_url"):
        raise ValueError("cover_media_id does not resolve to a renderable cover")
    return media_id


async def _resolve_course_cover_runtime_media(
    *,
    course_id: str,
    media_id: str,
) -> dict[str, Any] | None:
    runtime_row = await runtime_media_repo.get_course_cover_runtime_media(
        course_id=course_id,
        media_asset_id=media_id,
    )
    if runtime_row is None:
        return None

    asset_state = str(runtime_row.get("state") or "").strip().lower() or "placeholder"
    if asset_state != "ready":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_NOT_READY media_id=%s state=%s",
            media_id,
            asset_state,
        )
        return None

    asset_media_type = str(runtime_row.get("media_type") or "").strip().lower()
    asset_purpose = str(runtime_row.get("purpose") or "").strip().lower()
    storage_path = str(runtime_row.get("playback_object_path") or "").strip()
    playback_format = str(runtime_row.get("playback_format") or "").strip().lower()

    if asset_media_type != "image":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_INVALID media_id=%s media_type=%s",
            media_id,
            asset_media_type or "<missing>",
        )
        return None

    if asset_purpose != "course_cover":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_INVALID_PURPOSE media_id=%s purpose=%s",
            media_id,
            asset_purpose or "<missing>",
        )
        return None

    if not storage_path:
        logger.error(
            "COURSE_COVER_RESOLVED_STORAGE_IDENTITY_MISSING media_id=%s path=%s",
            media_id,
            storage_path or "<missing>",
        )
        return None

    if playback_format != "jpg":
        logger.error(
            "COURSE_COVER_RESOLVED_FORMAT_INVALID media_id=%s playback_format=%s",
            media_id,
            playback_format or "<missing>",
        )
        return None

    resolved_url = _resolve_course_cover_delivery_url(storage_path)
    if not str(resolved_url or "").strip():
        logger.error(
            "COURSE_COVER_RESOLVED_URL_MISSING media_id=%s path=%s",
            media_id,
            storage_path,
        )
        return None
    return {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": resolved_url,
    }


def _course_cover_payload(
    *,
    media_id: str,
    cover: Mapping[str, Any] | None,
) -> dict[str, Any] | None:
    if cover is None:
        return None
    state = str(cover.get("state") or "").strip().lower()
    resolved_url = str(cover.get("resolved_url") or "").strip()
    if state != "ready" or not resolved_url:
        return None
    return {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": resolved_url,
    }


async def resolve_course_cover(
    *,
    course_id: str | None = None,
    cover_media_id: str | None,
) -> dict[str, Any] | None:
    media_id = _normalize_cover_media_id(cover_media_id)
    exact_course_id = str(course_id or "").strip()
    if media_id is None or not exact_course_id:
        return None

    cover = await _resolve_course_cover_runtime_media(
        course_id=exact_course_id,
        media_id=media_id,
    )
    return _course_cover_payload(media_id=media_id, cover=cover)


async def attach_course_cover_read_contract(
    courses: dict[str, Any] | list[dict[str, Any]] | None,
) -> None:
    if courses is None:
        return

    rows = [courses] if isinstance(courses, dict) else list(courses)
    if not rows:
        return

    for row in rows:
        strip_legacy_course_cover_output_fields(row)
        media_id = _normalize_cover_media_id(row.get("cover_media_id"))
        if media_id is None:
            row["cover"] = None
            continue
        row["cover"] = _course_cover_payload(
            media_id=media_id,
            cover=await _resolve_course_cover_runtime_media(
                course_id=str(row.get("id") or "").strip(),
                media_id=media_id,
            ),
        )


async def create_course(
    payload: dict[str, Any],
    *,
    teacher_id: str | None = None,
) -> dict[str, Any]:
    _reject_legacy_cover_url_write(payload)
    if "group_position" in payload:
        raise ValueError(
            "group_position is not accepted for course create; courses append within the family automatically"
        )
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_teacher_id:
        raise ValueError("teacher_id is required")

    _validate_course_drip_configuration(
        drip_enabled=bool(payload["drip_enabled"]),
        drip_interval_days=payload["drip_interval_days"],
    )
    create_payload = dict(payload)
    create_payload.pop("teacher_id", None)
    create_payload["teacher_id"] = normalized_teacher_id
    if "cover_media_id" in create_payload:
        if create_payload["cover_media_id"] is not None:
            create_payload.setdefault("id", str(uuid4()))
            try:
                create_payload["cover_media_id"] = await _validate_course_cover_assignment(
                    course_id=str(create_payload["id"]),
                    cover_media_id=create_payload["cover_media_id"],
                )
            except PsycopgError as exc:
                mapped_error = map_course_create_database_error(exc)
                logger.exception(
                    "Course create cover validation database error",
                    extra=_course_create_db_log_context(
                        create_payload,
                        exc,
                        mapped_detail=mapped_error.detail,
                    ),
                )
                raise mapped_error from exc
        else:
            create_payload["cover_media_id"] = None
    try:
        row = await courses_repo.create_course(create_payload)
    except courses_repo.CourseCreateDatabaseError as exc:
        mapped_error = map_course_create_database_error(exc.cause)
        logger.warning(
            "Course create database error mapped",
            extra=_course_create_db_log_context(
                create_payload,
                exc.cause,
                mapped_detail=mapped_error.detail,
                repository_title=exc.title,
                repository_slug=exc.slug,
            ),
        )
        raise mapped_error from exc
    except PsycopgError as exc:
        mapped_error = map_course_create_database_error(exc)
        logger.exception(
            "Course create database error",
            extra=_course_create_db_log_context(
                create_payload,
                exc,
                mapped_detail=mapped_error.detail,
            ),
        )
        raise mapped_error from exc
    course = dict(row)
    return course


async def update_course(
    course_id: str,
    patch: dict[str, Any],
    *,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    _reject_legacy_cover_url_write(patch)
    forbidden_transition_fields = sorted(
        field for field in ("course_group_id", "group_position") if field in patch
    )
    if forbidden_transition_fields:
        raise ValueError(
            "course family transitions must use the explicit reorder or move-family operations"
        )
    existing_course = await courses_repo.get_course(course_id=course_id)
    if existing_course is None:
        return None
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_teacher_id:
        raise PermissionError("Course owner required")
    if not await courses_repo.is_course_owner(course_id, normalized_teacher_id):
        raise PermissionError("Not course owner")

    patch = dict(patch)
    patch.pop("teacher_id", None)
    if "cover_media_id" in patch:
        patch["cover_media_id"] = await _validate_course_cover_assignment(
            course_id=course_id,
            cover_media_id=patch["cover_media_id"],
        )
    drip_enabled = (
        patch["drip_enabled"]
        if "drip_enabled" in patch
        else existing_course["drip_enabled"]
    )
    drip_interval_days = (
        patch["drip_interval_days"]
        if "drip_interval_days" in patch
        else existing_course["drip_interval_days"]
    )
    _validate_course_drip_configuration(
        drip_enabled=bool(drip_enabled),
        drip_interval_days=drip_interval_days,
    )

    row = await courses_repo.update_course(course_id, patch)
    if row is None:
        return None
    return dict(row)


async def reorder_course_within_family(
    course_id: str,
    *,
    group_position: int,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_teacher_id:
        raise PermissionError("Course owner required")

    existing_course = await courses_repo.get_course(course_id=course_id)
    if existing_course is None:
        return None
    if not await courses_repo.is_course_owner(course_id, normalized_teacher_id):
        raise PermissionError("Not course owner")

    row = await courses_repo.update_course(
        course_id,
        {"group_position": int(group_position)},
    )
    if row is None:
        return None
    return dict(row)


async def move_course_to_family(
    course_id: str,
    *,
    course_group_id: str,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_teacher_id:
        raise PermissionError("Course owner required")

    existing_course = await courses_repo.get_course(course_id=course_id)
    if existing_course is None:
        return None
    if not await courses_repo.is_course_owner(course_id, normalized_teacher_id):
        raise PermissionError("Not course owner")

    target_course_group_id = str(course_group_id or "").strip()
    if not target_course_group_id:
        raise ValueError("course_group_id is required")
    if target_course_group_id == str(existing_course["course_group_id"]):
        raise ValueError(
            "move-family requires a different course_group_id; use reorder for same-family changes"
        )

    row = await courses_repo.update_course(
        course_id,
        {"course_group_id": target_course_group_id},
    )
    if row is None:
        return None
    return dict(row)


async def delete_course(course_id: str, teacher_id: str | None = None) -> bool:
    if teacher_id is None:
        raise RuntimeError("Teacher context required")
    target_course_id = str(course_id or "").strip()
    await studio_authority.enforce_teacher_owns_course(
        teacher_id,
        target_course_id,
    )
    try:
        return await courses_repo.delete_course(target_course_id)
    except (
        psycopg_errors.ForeignKeyViolation,
        psycopg_errors.RestrictViolation,
    ) as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=_COURSE_DELETE_BLOCKED_DETAIL,
        ) from exc


def _publish_validation_error(message: str) -> None:
    raise ValueError(message)


def _validate_publish_lesson_order(lessons: Sequence[Mapping[str, Any]]) -> None:
    positions: list[int] = []
    for lesson in lessons:
        title = str(lesson.get("lesson_title") or "").strip()
        if not title:
            _publish_validation_error("Lektion saknar titel")
        try:
            position = int(lesson.get("position"))
        except (TypeError, ValueError):
            _publish_validation_error("Lektionernas ordning är ogiltig")
        if position <= 0:
            _publish_validation_error("Lektionernas ordning är ogiltig")
        positions.append(position)

    expected = list(range(1, len(positions) + 1))
    if sorted(positions) != expected:
        _publish_validation_error("Lektionernas ordning är ogiltig")


async def _validate_referenced_lesson_media_ready(
    *,
    markdown: str,
    media_rows: Sequence[Mapping[str, Any]],
) -> None:
    referenced_ids = _referenced_lesson_media_ids(markdown)
    if not referenced_ids:
        return

    rows_by_id = {
        str(row.get("id") or "").strip(): row
        for row in media_rows
        if str(row.get("id") or "").strip()
    }
    for lesson_media_id in referenced_ids:
        row = rows_by_id.get(lesson_media_id)
        if row is None:
            _publish_validation_error("Lektionens mediareferenser är ogiltiga")
        state = str(row.get("state") or "").strip().lower()
        if state != "ready":
            _publish_validation_error("Lektionens media är inte redo")

        resolution = await canonical_media_resolver.resolve_lesson_media(
            lesson_media_id,
            emit_logs=False,
        )
        if (
            not resolution.is_playable
            or resolution.playback_mode != LessonMediaPlaybackMode.PIPELINE_ASSET
            or resolution.media_state != "ready"
            or not resolution.media_asset_id
        ):
            _publish_validation_error("Lektionens media är inte redo")
        row_media_asset_id = str(row.get("media_asset_id") or "").strip()
        if not row_media_asset_id or row_media_asset_id != str(
            resolution.media_asset_id
        ):
            _publish_validation_error("Lektionens mediareferenser är ogiltiga")


async def _derive_course_content_ready(course_id: str) -> bool:
    lessons = [
        dict(row) for row in await courses_repo.list_course_publish_lessons(course_id)
    ]
    if not lessons:
        _publish_validation_error("Kursen saknar lektioner")

    _validate_publish_lesson_order(lessons)

    for lesson in lessons:
        lesson_id = str(lesson.get("id") or "").strip()
        if not lesson_id:
            _publish_validation_error("Kursens lektionsstruktur är ogiltig")
        if str(lesson.get("course_id") or "").strip() != course_id:
            _publish_validation_error("Kursens lektionsstruktur är ogiltig")
        if lesson.get("has_content") is not True:
            _publish_validation_error("Lektion saknar innehåll")

        content_markdown = str(lesson.get("content_markdown") or "")
        if not content_markdown.strip():
            _publish_validation_error("Lektion saknar innehåll")

        media_rows = list(await list_lesson_media(lesson_id))
        lesson_media_kinds, media_url_aliases = (
            lesson_content_utils.build_lesson_media_write_contract(media_rows)
        )
        try:
            normalized_markdown = (
                lesson_content_utils.normalize_lesson_markdown_for_storage(
                    content_markdown,
                    lesson_media_kinds=lesson_media_kinds,
                    media_url_aliases=media_url_aliases,
                )
            )
        except ValueError as exc:
            raise ValueError("Lektionens mediareferenser är ogiltiga") from exc

        if normalized_markdown != content_markdown:
            _publish_validation_error("Lektionens innehåll är inte normaliserat")
        await _validate_referenced_lesson_media_ready(
            markdown=content_markdown,
            media_rows=media_rows,
        )

    return True


async def _validate_course_publish_readiness(
    course: Mapping[str, Any],
    *,
    teacher_id: str,
) -> int:
    course_id = str(course.get("id") or "").strip()
    if not course_id:
        _publish_validation_error("Kursen hittades inte")

    if str(course.get("teacher_id") or "").strip() != teacher_id:
        raise PermissionError("Du saknar behörighet att publicera kursen")
    if not await courses_repo.is_course_owner(course_id, teacher_id):
        raise PermissionError("Du saknar behörighet att publicera kursen")

    title = str(course.get("title") or "").strip()
    if not title:
        _publish_validation_error("Kursen saknar titel")
    slug = str(course.get("slug") or "").strip()
    if not slug:
        _publish_validation_error("Kursen saknar slug")
    existing_slug_course = await courses_repo.get_course(slug=slug)
    if (
        existing_slug_course is not None
        and str(existing_slug_course.get("id") or "").strip() != course_id
    ):
        _publish_validation_error("Kursens slug används redan")

    if not str(course.get("course_group_id") or "").strip():
        _publish_validation_error("Kursens struktur är ogiltig")
    try:
        group_position = int(course.get("group_position"))
    except (TypeError, ValueError):
        _publish_validation_error("Kursens struktur är ogiltig")
    if group_position < 0:
        _publish_validation_error("Kursens struktur är ogiltig")

    try:
        _validate_course_drip_configuration(
            drip_enabled=bool(course.get("drip_enabled")),
            drip_interval_days=course.get("drip_interval_days"),
        )
    except ValueError as exc:
        raise ValueError("Kursens droppinställningar är ogiltiga") from exc

    cover_media_id = course.get("cover_media_id")
    if cover_media_id is not None:
        try:
            await _validate_course_cover_assignment(
                course_id=course_id,
                cover_media_id=cover_media_id,
            )
        except ValueError as exc:
            raise ValueError("Kursens omslagsbild är ogiltig") from exc

    try:
        amount_cents = int(course.get("price_amount_cents") or 0)
    except (TypeError, ValueError):
        _publish_validation_error("Kursen saknar giltigt pris")
    if amount_cents <= 0:
        _publish_validation_error("Kursen saknar giltigt pris")

    await _derive_course_content_ready(course_id)
    return amount_cents


def _validate_publish_stripe_product(
    product: Mapping[str, Any],
    *,
    expected_product_id: str,
    course_id: str,
    teacher_id: str,
) -> None:
    product_id = str(product.get("id") or "").strip()
    if product_id != expected_product_id:
        raise RuntimeError("Course Stripe product mapping is inconsistent")
    if product.get("active") is False:
        raise RuntimeError("Course Stripe product is inactive")

    metadata = product.get("metadata") or {}
    if not isinstance(metadata, Mapping):
        raise RuntimeError("Course Stripe product metadata is invalid")
    if (
        str(metadata.get("course_id") or "").strip() != course_id
        or str(metadata.get("teacher_id") or "").strip() != teacher_id
        or str(metadata.get("type") or "").strip() != "course"
    ):
        raise RuntimeError("Course Stripe product metadata is inconsistent")


def _publish_stripe_price_matches(
    price: Mapping[str, Any],
    *,
    product_id: str,
    amount_cents: int,
) -> bool:
    mapped_product_id = str(price.get("product") or "").strip()
    if mapped_product_id != product_id:
        raise RuntimeError("Course Stripe price mapping is inconsistent")
    unit_amount = price.get("unit_amount")
    currency = str(price.get("currency") or "").strip().lower()
    is_active = bool(price.get("active", True))
    return (
        is_active
        and unit_amount == amount_cents
        and currency == _CANONICAL_COURSE_STRIPE_CURRENCY
    )


async def _resolve_publish_stripe_mapping(
    course: Mapping[str, Any],
    *,
    teacher_id: str,
    amount_cents: int,
) -> tuple[str, str]:
    course_id = str(course.get("id") or "").strip()
    product_id = str(course.get("stripe_product_id") or "").strip() or None
    active_price_id = str(course.get("active_stripe_price_id") or "").strip() or None

    _require_stripe_for_course_mapping()

    if active_price_id and not product_id:
        raise RuntimeError("Course Stripe mapping is incomplete")

    if product_id:
        product = await _stripe_retrieve_course_product(product_id)
        _validate_publish_stripe_product(
            product,
            expected_product_id=product_id,
            course_id=course_id,
            teacher_id=teacher_id,
        )
    else:
        product_id = await _stripe_create_course_product(
            course,
            teacher_id=teacher_id,
            idempotency_key=_course_publish_product_idempotency_key(course_id),
        )

    if active_price_id:
        price = await _stripe_retrieve_price(active_price_id)
        if _publish_stripe_price_matches(
            price,
            product_id=product_id,
            amount_cents=amount_cents,
        ):
            return product_id, active_price_id

    price_id = await _stripe_create_course_price(
        product_id=product_id,
        amount_cents=amount_cents,
        idempotency_key=_course_publish_price_idempotency_key(
            course_id=course_id,
            product_id=product_id,
            amount_cents=amount_cents,
        ),
    )
    return product_id, price_id


async def publish_course(
    course_id: str,
    *,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    normalized_course_id = str(course_id or "").strip()
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_course_id:
        raise ValueError("Kursen hittades inte")
    if not normalized_teacher_id:
        raise PermissionError("Du saknar behörighet att publicera kursen")

    course = await courses_repo.get_course_publish_subject(normalized_course_id)
    if course is None:
        return None

    amount_cents = await _validate_course_publish_readiness(
        course,
        teacher_id=normalized_teacher_id,
    )
    product_id, price_id = await _resolve_publish_stripe_mapping(
        course,
        teacher_id=normalized_teacher_id,
        amount_cents=amount_cents,
    )
    try:
        updated = await courses_repo.publish_course_state(
            normalized_course_id,
            stripe_product_id=product_id,
            active_stripe_price_id=price_id,
        )
    except Exception as exc:
        raise RuntimeError("Course publish state could not be persisted") from exc
    if updated is None:
        raise RuntimeError("Course publish state could not be persisted")
    return dict(updated)


async def refresh_course_sellability(course_id: str) -> dict[str, Any] | None:
    normalized_course_id = str(course_id or "").strip()
    if not normalized_course_id:
        raise ValueError("course_id is required")

    subject = await courses_repo.get_course_sellability_subject(normalized_course_id)
    if subject is None:
        return None

    target_sellable = _is_course_sellable_subject(subject)
    current_sellable = bool(subject.get("sellable"))
    if current_sellable != target_sellable:
        updated = await courses_repo.update_course_sellability(
            normalized_course_id,
            sellable=target_sellable,
        )
        return dict(updated) if updated is not None else None

    row = await courses_repo.get_course(course_id=normalized_course_id)
    return dict(row) if row else None


async def ensure_course_stripe_mapping(
    course_id: str, teacher_id: str
) -> dict[str, Any]:
    del course_id, teacher_id
    raise RuntimeError("Kursens Stripe-koppling hanteras endast via publicering")


async def create_lesson(*args: Any, **kwargs: Any) -> dict[str, Any]:
    del args, kwargs
    raise RuntimeError(
        "Legacy mixed lesson create is disabled; use separate structure and content surfaces"
    )


async def create_lesson_structure(
    course_id: str,
    *,
    lesson_title: str,
    position: int,
    teacher_id: str | None = None,
) -> dict[str, Any]:
    if teacher_id is None:
        raise RuntimeError("Teacher context required")
    await studio_authority.enforce_teacher_owns_course(
        teacher_id,
        course_id,
    )
    row = await courses_repo.create_lesson_structure(
        course_id=course_id,
        lesson_title=lesson_title,
        position=position,
    )
    return dict(row)


async def update_lesson_structure(
    lesson_id: str,
    patch: dict[str, Any],
    *,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    if teacher_id is None:
        raise RuntimeError("Teacher context required")
    lesson = await studio_authority._get_lesson_or_404(lesson_id)
    await studio_authority.enforce_teacher_owns_course(
        teacher_id,
        str(lesson["course_id"]),
    )
    structure_patch: dict[str, Any] = {}
    if "lesson_title" in patch:
        structure_patch["lesson_title"] = patch["lesson_title"]
    if "position" in patch:
        structure_patch["position"] = patch["position"]
    row = await courses_repo.update_lesson_structure(lesson_id, structure_patch)
    return dict(row) if row else None


async def update_lesson_content(
    lesson_id: str,
    *,
    content_markdown: str,
    if_match: str | None,
    teacher_id: str,
) -> dict[str, Any] | None:
    current = await read_studio_lesson_content(
        lesson_id,
        teacher_id=teacher_id,
    )
    if current is None:
        return None

    current_body = current["body"]
    current_etag = current["etag"]
    if not str(if_match or "").strip():
        raise LessonContentPreconditionRequired("If-Match is required")
    if not _if_match_contains_etag(if_match, current_etag):
        raise LessonContentPreconditionFailed("Lesson content is stale")

    media_rows = await list_lesson_media(lesson_id)
    lesson_media_kinds, media_url_aliases = (
        lesson_content_utils.build_lesson_media_write_contract(media_rows)
    )
    normalized_markdown = lesson_content_utils.normalize_lesson_markdown_for_storage(
        content_markdown,
        lesson_media_kinds=lesson_media_kinds,
        media_url_aliases=media_url_aliases,
    )
    try:
        validation = await run_in_threadpool(
            lesson_markdown_validator.validate_lesson_markdown,
            normalized_markdown,
        )
    except lesson_markdown_validator.LessonMarkdownValidationRuntimeError:
        logger.exception(
            "LESSON_MARKDOWN_VALIDATION_UNAVAILABLE",
            extra={
                "lesson_id": lesson_id,
                "submitted_markdown": content_markdown,
                "normalized_markdown": normalized_markdown,
            },
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Lesson markdown validation unavailable.",
        ) from None
    if not validation.ok:
        logger.warning(
            "LESSON_MARKDOWN_VALIDATION_FAILED",
            extra={
                "lesson_id": lesson_id,
                "failure_reason": validation.failure_reason,
                "submitted_markdown": content_markdown,
                "normalized_markdown": normalized_markdown,
                "canonical_markdown": validation.canonical_markdown,
            },
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=_INVALID_LESSON_MARKDOWN_DETAIL,
        )
    row = await courses_repo.update_lesson_content_if_current(
        lesson_id,
        normalized_markdown,
        expected_content_markdown=str(current_body["content_markdown"]),
    )
    if row is None:
        raise LessonContentPreconditionFailed("Lesson content is stale")

    updated_body = {
        "lesson_id": row["lesson_id"],
        "content_markdown": row["content_markdown"],
    }
    return {
        "body": updated_body,
        "etag": build_lesson_content_etag(
            str(row["lesson_id"]),
            str(row["content_markdown"]),
        ),
    }


async def upsert_lesson(
    course_id: str, payload: dict[str, Any]
) -> dict[str, Any] | None:
    del course_id, payload
    raise RuntimeError(
        "Legacy mixed lesson upsert is disabled; use separate structure and content surfaces"
    )


async def reorder_lessons(
    course_id: str,
    ordered_lesson_ids: Sequence[str],
    *,
    teacher_id: str | None = None,
) -> None:
    if teacher_id is None:
        raise RuntimeError("Teacher context required")
    await studio_authority.enforce_teacher_owns_course(
        teacher_id,
        course_id,
    )
    return await courses_repo.reorder_lessons(course_id, ordered_lesson_ids)


async def delete_lesson(lesson_id: str, teacher_id: str | None = None) -> bool:
    if teacher_id is None:
        raise RuntimeError("Teacher context required")
    lesson = await studio_authority._get_lesson_or_404(lesson_id)
    target_lesson_id = str(lesson["id"]).strip()
    await studio_authority.enforce_teacher_owns_course(
        teacher_id,
        str(lesson["course_id"]),
    )
    media_asset_ids = await courses_repo.list_lesson_media_asset_ids(target_lesson_id)
    deleted = await courses_repo.delete_lesson(target_lesson_id)
    if deleted:
        await media_cleanup.request_lifecycle_evaluation(
            media_asset_ids=media_asset_ids,
            trigger_source="lesson_delete",
            subject_type="lesson",
            subject_id=target_lesson_id,
        )
    return deleted


async def is_course_owner(user_id: str, course_id: str) -> bool:
    normalized_user_id = str(user_id or "").strip()
    normalized_course_id = str(course_id or "").strip()
    if not normalized_user_id or not normalized_course_id:
        return False
    return await courses_repo.is_course_owner(normalized_course_id, normalized_user_id)


async def is_course_teacher_or_instructor(user_id: str, course_id: str) -> bool:
    return await is_course_owner(user_id, course_id)


async def is_user_enrolled(user_id: str, course_id: str) -> bool:
    return await courses_repo.is_enrolled(str(user_id), str(course_id))


async def get_course_enrollment(user_id: str, course_id: str) -> dict[str, Any] | None:
    return await courses_repo.get_course_enrollment(str(user_id), str(course_id))


def _canonical_course_state_payload(
    *,
    course: Mapping[str, Any],
    enrollment: Mapping[str, Any] | None,
    required_enrollment_source: str | None,
    can_access: bool,
) -> dict[str, Any]:
    access_model = build_course_access_model(course)
    return {
        "course_id": str(course.get("id") or ""),
        "group_position": int(course.get("group_position") or 0),
        "required_enrollment_source": required_enrollment_source,
        "enrollable": bool(access_model["enrollable"]),
        "purchasable": bool(access_model["purchasable"]),
        "can_access": bool(can_access),
        "enrollment": dict(enrollment) if enrollment is not None else None,
    }


async def read_canonical_course_access(user_id: str, course_id: str) -> dict[str, Any]:
    course = await fetch_course(course_id=course_id)
    normalized_user_id = str(user_id or "").strip()
    enrollment = (
        await get_course_enrollment(normalized_user_id, course_id)
        if course is not None and normalized_user_id
        else None
    )
    required_enrollment_source = _course_required_enrollment_source(course)
    source_matches = (
        enrollment is not None
        and required_enrollment_source is not None
        and str(enrollment.get("source") or "").strip().lower()
        == required_enrollment_source
    )
    return {
        "course": course,
        "enrollment": enrollment,
        "required_enrollment_source": required_enrollment_source,
        "can_access": bool(source_matches),
    }


async def read_canonical_course_state(
    user_id: str, course_id: str
) -> dict[str, Any] | None:
    access = await read_canonical_course_access(user_id, course_id)
    course = access["course"]
    if course is None:
        return None
    return _canonical_course_state_payload(
        course=course,
        enrollment=access["enrollment"],
        required_enrollment_source=access["required_enrollment_source"],
        can_access=access["can_access"],
    )


async def read_canonical_lesson_access(user_id: str, lesson_id: str) -> dict[str, Any]:
    lesson = await fetch_lesson(lesson_id)
    if lesson is None:
        return {
            "lesson": None,
            "course": None,
            "enrollment": None,
            "required_enrollment_source": None,
            "current_unlock_position": 0,
            "can_access": False,
        }

    course_id = str(lesson.get("course_id") or "").strip()
    course_access = await read_canonical_course_access(user_id, course_id)
    enrollment = course_access["enrollment"]
    current_unlock_position = (
        int(enrollment.get("current_unlock_position") or 0)
        if enrollment is not None
        else 0
    )
    lesson_position = int(lesson.get("position") or 0)
    can_access = bool(
        course_access["can_access"]
        and lesson_position >= 1
        and lesson_position <= current_unlock_position
    )
    return {
        **course_access,
        "lesson": lesson,
        "current_unlock_position": current_unlock_position,
        "can_access": can_access,
    }


async def can_user_read_course(user_id: str, course: Mapping[str, Any]) -> bool:
    course_id = str(course.get("id") or "").strip()
    if not course_id:
        return False
    access = await read_canonical_course_access(user_id, course_id)
    return bool(access["can_access"])


async def can_user_read_lesson(user_id: str, lesson: Mapping[str, Any]) -> bool:
    lesson_id = str(lesson.get("id") or "").strip()
    if not lesson_id:
        return False
    access = await read_canonical_lesson_access(user_id, lesson_id)
    return bool(access["can_access"])


async def create_intro_course_enrollment(
    *,
    user_id: str,
    course_id: str,
) -> dict[str, Any]:
    course = await fetch_course(course_id=course_id)
    if course is None:
        raise LookupError("course not found")

    if build_course_access_model(course)["enrollable"] is not True:
        raise PermissionError("purchase enrollment required")

    enrollment = await courses_repo.create_course_enrollment(
        user_id=str(user_id),
        course_id=str(course_id),
        source="intro_enrollment",
    )
    return _canonical_course_state_payload(
        course=course,
        enrollment=enrollment,
        required_enrollment_source="intro_enrollment",
        can_access=True,
    )
