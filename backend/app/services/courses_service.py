from __future__ import annotations

import logging
from typing import Any, Mapping, Sequence

from fastapi import HTTPException, status

from ..config import settings
from ..media_control_plane.services.media_resolver_service import (
    LessonMediaPlaybackMode,
    media_resolver_service as canonical_media_resolver,
)
from ..repositories import courses as courses_repo
from ..repositories import home_audio_runtime as home_audio_runtime_repo
from ..repositories import media_assets as media_assets_repo
from ..repositories import storage_objects
from . import lesson_playback_service
from . import storage_service
from ..utils import media_signer

logger = logging.getLogger(__name__)

_HOME_AUDIO_MEDIA_STATES = frozenset(
    {"pending_upload", "uploaded", "processing", "ready", "failed"}
)


def _is_admin_profile(profile: Mapping[str, Any] | None) -> bool:
    if not profile:
        return False
    if profile.get("is_admin"):
        return True
    role = str(profile.get("role_v2") or "").strip().lower()
    return role == "admin"


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
    del teacher_id
    rows = [dict(row) for row in await courses_repo.list_courses(limit=limit, search=search)]
    await attach_course_cover_read_contract(rows)
    return rows


async def list_public_courses(
    *,
    published_only: bool = True,
    search: str | None = None,
    limit: int | None = None,
) -> Sequence[dict[str, Any]]:
    del published_only
    rows = [
        dict(row)
        for row in await courses_repo.list_public_courses(search=search, limit=limit)
    ]
    await attach_course_cover_read_contract(rows)
    return rows


async def list_my_courses(user_id: str) -> Sequence[dict[str, Any]]:
    rows = [dict(row) for row in await courses_repo.list_my_courses(str(user_id))]
    await attach_course_cover_read_contract(rows)
    return rows


async def list_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_course_lessons(course_id))


async def list_studio_course_lessons(course_id: str) -> Sequence[dict[str, Any]]:
    return list(await courses_repo.list_studio_course_lessons(course_id))


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_lesson(lesson_id)
    return dict(row) if row else None


async def fetch_studio_lesson(lesson_id: str) -> dict[str, Any] | None:
    row = await courses_repo.get_studio_lesson(lesson_id)
    return dict(row) if row else None


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
    media_asset_id: str,
    media_state: str,
    playback_cache: dict[str, dict[str, Any]],
) -> dict[str, Any] | None:
    cached = playback_cache.get(media_asset_id)
    if cached is not None:
        return cached

    resolved_url: str | None = None
    if media_state == "ready":
        try:
            playback = await lesson_playback_service.resolve_media_asset_playback(
                media_asset_id=media_asset_id
            )
        except HTTPException:
            return None
        resolved_url = str(playback.get("resolved_url") or "").strip() or None

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

        media_state = _normalized_home_audio_state(row.get("media_state"))
        media = await _compose_home_audio_media(
            media_asset_id=media_asset_id,
            media_state=media_state,
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
        "source": "placeholder",
    }


async def _resolve_course_cover_read_model(media_id: str) -> dict[str, Any]:
    media_asset = await media_assets_repo.get_media_asset(media_id)
    if media_asset is None:
        return _course_cover_placeholder(media_id=media_id, state="placeholder")

    asset_state = str(media_asset.get("state") or "").strip().lower() or "placeholder"
    if asset_state != "ready":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_NOT_READY media_id=%s state=%s",
            media_id,
            asset_state,
        )
        return _course_cover_placeholder(media_id=media_id, state=asset_state)

    asset_purpose = str(media_asset.get("purpose") or "").strip().lower()
    asset_media_type = str(media_asset.get("media_type") or "").strip().lower()
    if not asset_media_type and asset_purpose == "course_cover":
        asset_media_type = "image"
    storage_bucket = str(
        media_asset.get("streaming_storage_bucket")
        or media_asset.get("storage_bucket")
        or settings.media_public_bucket
        or ""
    ).strip()
    storage_path = str(
        media_asset.get("playback_object_path")
        or media_asset.get("streaming_object_path")
        or ""
    ).strip()

    if asset_purpose != "course_cover" or asset_media_type != "image":
        logger.error(
            "COURSE_COVER_RESOLVED_ASSET_INVALID media_id=%s purpose=%s media_type=%s",
            media_id,
            asset_purpose or "<missing>",
            asset_media_type or "<missing>",
        )
        return _course_cover_placeholder(media_id=media_id, state="invalid")

    if not storage_bucket or not storage_path:
        logger.error(
            "COURSE_COVER_RESOLVED_STORAGE_IDENTITY_MISSING media_id=%s bucket=%s path=%s",
            media_id,
            storage_bucket or "<missing>",
            storage_path or "<missing>",
        )
        return _course_cover_placeholder(media_id=media_id, state="missing")

    existence, storage_catalog_available = await storage_objects.fetch_storage_object_existence(
        [(storage_bucket, storage_path)]
    )
    if not storage_catalog_available or not existence.get((storage_bucket, storage_path), False):
        return _course_cover_placeholder(media_id=media_id, state="missing")

    resolved_url = storage_service.get_storage_service(storage_bucket).public_url(storage_path)
    return {
        "media_id": media_id,
        "state": "ready",
        "resolved_url": resolved_url,
        "source": "control_plane",
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
    del course_id

    media_id = _normalize_cover_media_id(cover_media_id)
    if media_id is None:
        return None

    cover = await _resolve_course_cover_read_model(media_id)
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
            cover=await _resolve_course_cover_read_model(media_id),
        )


async def create_course(payload: dict[str, Any]) -> dict[str, Any]:
    _reject_legacy_cover_url_write(payload)
    _validate_course_drip_configuration(
        drip_enabled=bool(payload["drip_enabled"]),
        drip_interval_days=payload["drip_interval_days"],
    )
    row = await courses_repo.create_course(payload)
    return dict(row)


async def update_course(course_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
    _reject_legacy_cover_url_write(patch)
    existing_course = await courses_repo.get_course(course_id=course_id)
    if existing_course is None:
        return None

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
    return dict(row) if row else None


async def delete_course(course_id: str) -> bool:
    return await courses_repo.delete_course(course_id)


async def create_lesson(
    course_id: str,
    *,
    lesson_title: str,
    content_markdown: str,
    position: int,
    lesson_id: str | None = None,
) -> dict[str, Any]:
    row = await courses_repo.create_lesson(
        lesson_id=lesson_id,
        course_id=course_id,
        lesson_title=lesson_title,
        content_markdown=content_markdown,
        position=position,
    )
    return dict(row)


async def upsert_lesson(course_id: str, payload: dict[str, Any]) -> dict[str, Any] | None:
    existing_id = str(payload.get("id") or "").strip()
    lesson_id = existing_id or None
    if lesson_id is None:
        required_fields = {"lesson_title", "content_markdown", "position"}
        missing = sorted(field for field in required_fields if field not in payload)
        if missing:
            raise ValueError(f"missing lesson fields: {', '.join(missing)}")
        return await create_lesson(
            course_id,
            lesson_title=str(payload["lesson_title"]),
            content_markdown=str(payload["content_markdown"]),
            position=int(payload["position"]),
        )

    patch: dict[str, Any] = {}
    if "lesson_title" in payload:
        patch["lesson_title"] = payload["lesson_title"]
    if "content_markdown" in payload:
        patch["content_markdown"] = payload["content_markdown"]
    if "position" in payload:
        patch["position"] = payload["position"]
    row = await courses_repo.update_lesson(lesson_id, patch)
    return dict(row) if row else None


async def reorder_lessons(course_id: str, ordered_lesson_ids: Sequence[str]) -> None:
    return await courses_repo.reorder_lessons(course_id, ordered_lesson_ids)


async def delete_lesson(lesson_id: str) -> bool:
    return await courses_repo.delete_lesson(lesson_id)


async def is_course_owner(course_id: str, user_id: str) -> bool:
    del course_id, user_id
    return False


async def is_course_teacher_or_instructor(course_id: str, user_id: str) -> bool:
    del course_id, user_id
    return False


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
