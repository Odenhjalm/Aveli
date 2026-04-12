from __future__ import annotations

import logging
import hashlib
from pathlib import Path
from typing import Any, Mapping, Sequence
from uuid import UUID, uuid4

import stripe
from fastapi import HTTPException, status
from psycopg import errors as psycopg_errors
from starlette.concurrency import run_in_threadpool

from ..config import settings
from .. import stripe_mode
from ..media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    media_resolver_service as canonical_media_resolver,
)
from ..repositories import courses as courses_repo
from ..repositories import home_audio_runtime as home_audio_runtime_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import runtime_media as runtime_media_repo
from ..utils import lesson_content as lesson_content_utils
from . import lesson_playback_service
from . import media_cleanup
from . import studio_authority
from . import storage_service

logger = logging.getLogger(__name__)
_CANONICAL_COURSE_STRIPE_CURRENCY = "sek"
_SELLABLE_COURSE_STEPS = frozenset({"step1", "step2", "step3"})
_COURSE_DELETE_BLOCKED_DETAIL = "Course delete blocked by dependent rows"

_HOME_AUDIO_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)
_LEARNER_MEDIA_TYPES = frozenset({"audio", "image", "video", "document"})
_LEARNER_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)


class LessonContentPreconditionRequired(Exception):
    pass


class LessonContentPreconditionFailed(Exception):
    pass


def build_lesson_content_etag(lesson_id: str, content_markdown: str) -> str:
    payload = f"{str(lesson_id).strip()}\0{content_markdown}".encode("utf-8")
    digest = hashlib.sha256(payload).hexdigest()
    return f'"lesson-content:{digest}"'


def _if_match_contains_etag(if_match: str | None, expected_etag: str) -> bool:
    value = str(if_match or "").strip()
    if not value:
        return False
    return expected_etag in {candidate.strip() for candidate in value.split(",")}


def _source_matches_course_step(*, course_step: str, enrollment_source: str) -> bool:
    normalized_step = str(course_step or "").strip().lower()
    normalized_source = str(enrollment_source or "").strip().lower()
    if normalized_step == "intro":
        return normalized_source == "intro_enrollment"
    return normalized_source == "purchase"


def _course_expected_source(course: Mapping[str, Any] | None) -> str | None:
    if not course:
        return None
    normalized_step = str(course.get("step") or "").strip().lower()
    if normalized_step == "intro":
        return "intro_enrollment"
    if normalized_step in {"step1", "step2", "step3"}:
        return "purchase"
    return None


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


def _course_requires_stripe_mapping(course: Mapping[str, Any]) -> bool:
    normalized_step = str(course.get("step") or "").strip().lower()
    amount_cents = int(course.get("price_amount_cents") or 0)
    return normalized_step in _SELLABLE_COURSE_STEPS and amount_cents > 0


def _is_course_sellable_subject(course: Mapping[str, Any]) -> bool:
    normalized_step = str(course.get("step") or "").strip().lower()
    teacher_id = str(course.get("teacher_id") or "").strip()
    amount_cents = int(course.get("price_amount_cents") or 0)
    stripe_product_id = str(course.get("stripe_product_id") or "").strip()
    active_price_id = str(course.get("active_stripe_price_id") or "").strip()
    return (
        normalized_step in _SELLABLE_COURSE_STEPS
        and bool(teacher_id)
        and amount_cents > 0
        and bool(stripe_product_id)
        and bool(active_price_id)
    )


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
) -> str:
    course_id = str(course.get("id") or "").strip()
    title = str(course.get("title") or "").strip() or "Course"

    try:
        product = await run_in_threadpool(
            lambda: stripe.Product.create(
                name=title,
                metadata={
                    "course_id": course_id,
                    "teacher_id": teacher_id,
                    "type": "course",
                },
            )
        )
    except stripe.error.StripeError as exc:  # type: ignore[attr-defined]
        raise RuntimeError("Failed to create Stripe product for course") from exc

    product_id = product.get("id")
    if not isinstance(product_id, str) or not product_id.strip():
        raise RuntimeError("Stripe did not return a course product id")
    return product_id


async def _stripe_create_course_price(*, product_id: str, amount_cents: int) -> str:
    try:
        price = await run_in_threadpool(
            lambda: stripe.Price.create(
                product=product_id,
                unit_amount=amount_cents,
                currency=_CANONICAL_COURSE_STRIPE_CURRENCY,
            )
        )
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
    await attach_course_cover_read_contract(rows)
    return rows


async def list_public_courses(
    *,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[dict[str, Any]]:
    rows = [
        dict(row)
        for row in await courses_repo.list_public_course_discovery(
            search=search,
            limit=limit,
        )
    ]
    await attach_course_cover_read_contract(rows)
    return rows


async def fetch_public_course_detail_rows(
    *,
    course_id: str | None = None,
    slug: str | None = None,
) -> Sequence[dict[str, Any]]:
    return list(
        await courses_repo.get_public_course_detail_rows(
            course_id=course_id,
            slug=slug,
        )
    )


async def list_my_courses(user_id: str) -> Sequence[dict[str, Any]]:
    rows = [dict(row) for row in await courses_repo.list_my_courses(str(user_id))]
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

    lesson = {
        "id": rows[0]["id"],
        "course_id": rows[0]["course_id"],
        "lesson_title": rows[0]["lesson_title"],
        "position": rows[0]["position"],
        "content_markdown": rows[0].get("content_markdown"),
    }

    media_rows: list[dict[str, Any]] = []
    seen_lesson_media_ids: set[str] = set()
    for row in rows:
        lesson_media_id = row.get("lesson_media_id")
        if lesson_media_id is None:
            continue

        normalized_lesson_media_id = str(lesson_media_id)
        if normalized_lesson_media_id in seen_lesson_media_ids:
            continue
        seen_lesson_media_ids.add(normalized_lesson_media_id)

        resolution = await canonical_media_resolver.resolve_lesson_media(
            normalized_lesson_media_id,
            emit_logs=False,
        )
        media_type = _normalized_surface_media_type(resolution.media_type)
        media_state = _normalized_surface_media_state(resolution.media_state)
        item = {
            "id": lesson_media_id,
            "lesson_id": row["id"],
            "media_asset_id": row.get("media_asset_id"),
            "position": row.get("lesson_media_position") or 0,
            "media_type": media_type,
            "kind": media_type,
            "state": media_state,
            "media": None,
        }

        if (
            resolution.is_playable
            and resolution.playback_mode == LessonMediaPlaybackMode.PIPELINE_ASSET
            and resolution.media_asset_id
        ):
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
            item["media"] = {
                "media_id": str(resolution.media_asset_id),
                "state": media_state,
                "resolved_url": resolved_url,
            }

        media_rows.append(item)

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
        media_type = str(
            row.get("media_type") or row.get("kind") or ""
        ).strip().lower()
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
    rows = [dict(row) for row in await courses_repo.list_lesson_media_for_studio(lesson_id)]
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


def _normalized_home_audio_state(value: Any) -> str:
    normalized = str(value or "").strip().lower()
    if normalized not in _HOME_AUDIO_MEDIA_STATES:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Canonical home audio media state is unavailable",
        )
    return normalized


async def _compose_home_audio_media(
    *,
    source_type: str,
    lesson_id: str | None,
    media_asset_id: str,
    playback_cache: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    cached = playback_cache.get(media_asset_id)
    if cached is not None:
        return cached

    runtime_row = (
        await runtime_media_repo.get_home_player_runtime_media(
            media_asset_id=media_asset_id,
        )
        if source_type == "direct_upload"
        else await runtime_media_repo.get_lesson_runtime_media(
            lesson_id=str(lesson_id or "").strip(),
            media_asset_id=media_asset_id,
        )
    )
    if runtime_row is None:
        return None

    media_state = _normalized_home_audio_state(runtime_row.get("state"))
    resolved_url: str | None = None
    if media_state == "ready":
        playback_object_path = str(runtime_row.get("playback_object_path") or "").strip()
        playback_format = str(runtime_row.get("playback_format") or "").strip().lower()
        media_type = str(runtime_row.get("media_type") or "").strip().lower()
        if not playback_object_path or playback_format != "mp3" or media_type != "audio":
            return None
        try:
            presigned = await storage_service.get_storage_service(
                settings.media_source_bucket
            ).get_presigned_url(
                playback_object_path,
                ttl=settings.media_playback_url_ttl_seconds,
                filename=playback_object_path.rsplit("/", 1)[-1] or "media.mp3",
                download=False,
            )
        except storage_service.StorageServiceError:
            return None
        resolved_url = str(presigned.url or "").strip() or None

    media = {
        "media_id": media_asset_id,
        "state": media_state,
        "resolved_url": resolved_url,
    }
    playback_cache[media_asset_id] = media
    return media


async def list_home_audio_media(
    user_id: str,
    *,
    limit: int = 12,
) -> Sequence[dict[str, Any]]:
    normalized_user_id = str(user_id or "").strip()
    if not normalized_user_id:
        raise ValueError("user_id is required for home audio")

    capped_limit = max(1, min(int(limit or 12), 50))
    candidate_limit = max(100, min(capped_limit * 4, 250))

    direct_rows = await home_audio_runtime_repo.list_home_audio_direct_upload_sources(
        limit=candidate_limit
    )
    course_link_rows = await home_audio_runtime_repo.list_home_audio_course_link_sources(
        limit=candidate_limit
    )

    candidates = [
        {"source_type": "direct_upload", **dict(row)} for row in direct_rows
    ] + [{"source_type": "course_link", **dict(row)} for row in course_link_rows]
    candidates.sort(
        key=lambda row: (
            row.get("created_at"),
            str(row.get("media_asset_id") or ""),
        ),
        reverse=True,
    )

    lesson_access_cache: dict[str, bool] = {}
    playback_cache: dict[str, dict[str, Any]] = {}
    items: list[dict[str, Any]] = []

    for row in candidates:
        if len(items) >= capped_limit:
            break

        source_type = str(row.get("source_type") or "").strip()
        teacher_id = str(row.get("teacher_id") or "").strip()
        media_asset_id = str(row.get("media_asset_id") or "").strip()
        if not teacher_id or not media_asset_id:
            continue

        if source_type == "direct_upload":
            if teacher_id != normalized_user_id:
                continue
        elif source_type == "course_link":
            lesson_id = str(row.get("lesson_id") or "").strip()
            if not lesson_id:
                continue
            can_access = lesson_access_cache.get(lesson_id)
            if can_access is None:
                access = await read_canonical_lesson_access(
                    normalized_user_id,
                    lesson_id,
                )
                can_access = bool(access["can_access"])
                lesson_access_cache[lesson_id] = can_access
            if not can_access:
                continue
        else:
            continue

        media = await _compose_home_audio_media(
            source_type=source_type,
            lesson_id=row.get("lesson_id"),
            media_asset_id=media_asset_id,
            playback_cache=playback_cache,
        )
        if media is None:
            continue

        items.append(
            {
                "source_type": source_type,
                "title": str(row.get("title") or "").strip(),
                "lesson_title": (
                    None
                    if source_type == "direct_upload"
                    else str(row.get("lesson_title") or "").strip() or None
                ),
                "course_id": row.get("course_id"),
                "course_title": (
                    str(row.get("course_title") or "").strip() or None
                    if source_type == "course_link"
                    else None
                ),
                "course_slug": (
                    str(row.get("course_slug") or "").strip() or None
                    if source_type == "course_link"
                    else None
                ),
                "teacher_id": row.get("teacher_id"),
                "teacher_name": str(row.get("teacher_name") or "").strip() or None,
                "created_at": row.get("created_at"),
                "media": media,
            }
        )

    return items


def _normalize_cover_media_id(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _course_cover_placeholder(*, media_id: str | None, state: str) -> dict[str, Any]:
    return {
        "media_id": media_id,
        "state": state,
        "resolved_url": None,
    }


def _canonical_course_cover_source_prefix(course_id: str) -> str:
    return (
        Path("media") / "source" / "cover" / "courses" / course_id
    ).as_posix() + "/"


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
    playback_object_path = str(asset.get("playback_object_path") or "").strip()
    if state != "ready" or not playback_object_path:
        return None
    resolved_url = storage_service.get_storage_service(
        settings.media_public_bucket
    ).public_url(playback_object_path)
    if not str(resolved_url or "").strip():
        return None
    return {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": resolved_url,
    }


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
) -> dict[str, Any]:
    runtime_row = await runtime_media_repo.get_course_cover_runtime_media(
        course_id=course_id,
        media_asset_id=media_id,
    )
    if runtime_row is None:
        return _course_cover_placeholder(media_id=media_id, state="placeholder")

    asset_state = str(runtime_row.get("state") or "").strip().lower() or "placeholder"
    if asset_state != "ready":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_NOT_READY media_id=%s state=%s",
            media_id,
            asset_state,
        )
        return _course_cover_placeholder(media_id=media_id, state=asset_state)

    asset_media_type = str(runtime_row.get("media_type") or "").strip().lower()
    storage_path = str(runtime_row.get("playback_object_path") or "").strip()

    if asset_media_type != "image":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_INVALID media_id=%s media_type=%s",
            media_id,
            asset_media_type or "<missing>",
        )
        return _course_cover_placeholder(media_id=media_id, state="invalid")

    if not storage_path:
        logger.error(
            "COURSE_COVER_RESOLVED_STORAGE_IDENTITY_MISSING media_id=%s path=%s",
            media_id,
            storage_path or "<missing>",
        )
        return _course_cover_placeholder(media_id=media_id, state="missing")

    resolved_url = storage_service.get_storage_service(
        settings.media_public_bucket
    ).public_url(storage_path)
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
    return {
        "media_id": media_id,
        "state": cover.get("state"),
        "resolved_url": cover.get("resolved_url"),
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
        row.pop("cover_url", None)
        row.pop("signed_cover_url", None)
        row.pop("signed_cover_url_expires_at", None)
        media_id = _normalize_cover_media_id(row.get("cover_media_id"))
        if media_id is None:
            row.pop("cover", None)
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
            create_payload["cover_media_id"] = await _validate_course_cover_assignment(
                course_id=str(create_payload["id"]),
                cover_media_id=create_payload["cover_media_id"],
            )
        else:
            create_payload["cover_media_id"] = None
    row = await courses_repo.create_course(create_payload)
    course = dict(row)
    try:
        ensured = await ensure_course_stripe_mapping(
            str(course["id"]),
            normalized_teacher_id,
        )
    except RuntimeError:
        await courses_repo.delete_course(str(course["id"]))
        raise
    return dict(ensured)


async def update_course(
    course_id: str,
    patch: dict[str, Any],
    *,
    teacher_id: str | None = None,
) -> dict[str, Any] | None:
    _reject_legacy_cover_url_write(patch)
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

    previous_values = {
        key: existing_course[key]
        for key in patch.keys()
        if key in existing_course
    }
    row = await courses_repo.update_course(course_id, patch)
    if row is None:
        return None
    course = dict(row)

    should_refresh_mapping = bool(
        {"price_amount_cents", "step"} & set(patch.keys())
    )
    if not should_refresh_mapping:
        return course

    try:
        ensured = await ensure_course_stripe_mapping(course_id, normalized_teacher_id)
    except RuntimeError:
        if previous_values:
            await courses_repo.update_course(course_id, previous_values)
        raise
    return dict(ensured)


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


async def ensure_course_stripe_mapping(course_id: str, teacher_id: str) -> dict[str, Any]:
    normalized_course_id = str(course_id or "").strip()
    normalized_teacher_id = str(teacher_id or "").strip()
    if not normalized_course_id:
        raise ValueError("course_id is required")
    if not normalized_teacher_id:
        raise PermissionError("Course owner required")
    if not await courses_repo.is_course_owner(normalized_course_id, normalized_teacher_id):
        raise PermissionError("Not course owner")

    course = await courses_repo.get_course(course_id=normalized_course_id)
    if course is None:
        raise LookupError("course not found")
    if not _course_requires_stripe_mapping(course):
        refreshed = await refresh_course_sellability(normalized_course_id)
        return dict(refreshed) if refreshed is not None else dict(course)

    _require_stripe_for_course_mapping()

    amount_cents = int(course.get("price_amount_cents") or 0)
    product_id = str(course.get("stripe_product_id") or "").strip() or None
    active_price_id = str(course.get("active_stripe_price_id") or "").strip() or None

    if active_price_id and not product_id:
        raise RuntimeError("Course Stripe mapping is incomplete")

    if product_id is None:
        product_id = await _stripe_create_course_product(
            course,
            teacher_id=normalized_teacher_id,
        )

    desired_price_id = active_price_id
    if active_price_id:
        price = await _stripe_retrieve_price(active_price_id)
        mapped_product_id = str(price.get("product") or "").strip()
        if mapped_product_id != product_id:
            raise RuntimeError("Course Stripe mapping is inconsistent")

        unit_amount = price.get("unit_amount")
        currency = str(price.get("currency") or "").strip().lower()
        is_active = bool(price.get("active", True))
        if (
            not is_active
            or unit_amount != amount_cents
            or currency != _CANONICAL_COURSE_STRIPE_CURRENCY
        ):
            desired_price_id = await _stripe_create_course_price(
                product_id=product_id,
                amount_cents=amount_cents,
            )
    else:
        desired_price_id = await _stripe_create_course_price(
            product_id=product_id,
            amount_cents=amount_cents,
        )

    if desired_price_id is None:
        raise RuntimeError("Course Stripe price mapping could not be resolved")

    if (
        str(course.get("stripe_product_id") or "").strip() == product_id
        and str(course.get("active_stripe_price_id") or "").strip() == desired_price_id
    ):
        refreshed = await refresh_course_sellability(normalized_course_id)
        return dict(refreshed) if refreshed is not None else dict(course)

    updated = await courses_repo.update_course_stripe_mapping(
        normalized_course_id,
        stripe_product_id=product_id,
        active_stripe_price_id=desired_price_id,
    )
    if updated is None:
        raise RuntimeError("Course Stripe mapping could not be persisted")
    refreshed = await refresh_course_sellability(normalized_course_id)
    return dict(refreshed) if refreshed is not None else dict(updated)


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


async def upsert_lesson(course_id: str, payload: dict[str, Any]) -> dict[str, Any] | None:
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
    expected_source: str | None,
) -> dict[str, Any]:
    return {
        "course_id": str(course.get("id") or ""),
        "course_step": str(course.get("step") or ""),
        "required_enrollment_source": expected_source,
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
    expected_source = _course_expected_source(course)
    source_matches = (
        enrollment is not None
        and expected_source is not None
        and str(enrollment.get("source") or "").strip().lower() == expected_source
    )
    return {
        "course": course,
        "enrollment": enrollment,
        "expected_source": expected_source,
        "can_access": bool(source_matches),
    }


async def read_canonical_course_state(user_id: str, course_id: str) -> dict[str, Any] | None:
    access = await read_canonical_course_access(user_id, course_id)
    course = access["course"]
    if course is None:
        return None
    return _canonical_course_state_payload(
        course=course,
        enrollment=access["enrollment"],
        expected_source=access["expected_source"],
    )


async def read_canonical_lesson_access(user_id: str, lesson_id: str) -> dict[str, Any]:
    lesson = await fetch_lesson(lesson_id)
    if lesson is None:
        return {
            "lesson": None,
            "course": None,
            "enrollment": None,
            "expected_source": None,
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

    course_step = str(course.get("step") or "").strip().lower()
    if course_step != "intro":
        raise PermissionError("purchase enrollment required")

    enrollment = await courses_repo.create_course_enrollment(
        user_id=str(user_id),
        course_id=str(course_id),
        source="intro_enrollment",
    )
    return _canonical_course_state_payload(
        course=course,
        enrollment=enrollment,
        expected_source="intro_enrollment",
    )
