from __future__ import annotations

import asyncio
import logging
import os
from typing import Any, Mapping, Sequence
from urllib.parse import urlparse

import stripe
from starlette.concurrency import run_in_threadpool

from psycopg.types.json import Jsonb

from ..config import settings
from ..repositories import (
    courses as courses_repo,
    get_latest_order_for_course,
    get_latest_subscription,
    get_membership,
    get_profile,
    media_assets as media_assets_repo,
    runtime_media as runtime_media_repo,
    storage_objects,
)
from ..media_control_plane.services.media_resolver_service import (
    RuntimeMediaPlaybackMode,
    RuntimeMediaResolution,
    media_resolver_service as canonical_media_resolver,
)
from . import media_cleanup
from . import media_resolver
from ..services import storage_service
from ..utils.audio_content_types import resolve_runtime_audio_content_type
from ..utils.lesson_content import (
    build_lesson_media_write_contract,
    markdown_contains_legacy_document_media_links,
    normalize_lesson_markdown_for_storage,
    serialize_audio_embeds,
)
from ..utils import media_paths
from ..utils import media_signer
from ..utils import media_robustness
from ..utils.membership_status import is_membership_active


CoursePayload = Mapping[str, Any]
ModulePayload = Mapping[str, Any]
LessonPayload = Mapping[str, Any]

logger = logging.getLogger(__name__)


def _course_cover_contract_debug_enabled() -> bool:
    return os.getenv("COURSE_COVER_CONTRACT_DEBUG", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _course_cover_resolved_read_enabled() -> bool:
    return os.getenv("COURSE_COVER_RESOLVED_READ_ENABLED", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
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
    if status_value == "incomplete":
        user_id = (
            (profile or {}).get("user_id")
            or (subscription or {}).get("user_id")
            or "unknown"
        )
        logger.warning("Incomplete membership encountered for user %s", user_id)
    return is_membership_active(status_value or "", (subscription or {}).get("end_date"))


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


def _normalize_public_cover_key(value: Any) -> str | None:
    normalized = _normalize_storage_path(str(value or ""))
    if not normalized:
        return None
    public_bucket = settings.media_public_bucket.strip().strip("/")
    prefix = f"{public_bucket}/"
    if public_bucket and normalized.startswith(prefix):
        stripped = normalized[len(prefix) :].lstrip("/")
        return stripped or None
    return normalized


def _course_cover_log_context(course: Mapping[str, Any]) -> tuple[str, str, str]:
    return (
        str(course.get("id") or "").strip() or "<missing>",
        str(course.get("slug") or "").strip() or "<missing>",
        str(course.get("title") or "").strip() or "<missing>",
    )


def _log_course_cover_warning(
    event: str,
    *,
    course: Mapping[str, Any],
    cover_media_id: str | None,
    cover_url: str | None,
    asset: Mapping[str, Any] | None = None,
    reason: str | None = None,
    derived_bucket: str | None = None,
    derived_path: str | None = None,
    expected_key: str | None = None,
    actual_key: str | None = None,
) -> None:
    course_id, slug, title = _course_cover_log_context(course)
    asset_state = str((asset or {}).get("state") or "").strip().lower() or "<missing>"
    logger.warning(
        "%s course_id=%s slug=%s title=%s cover_media_id=%s asset_state=%s reason=%s derived_bucket=%s derived_path=%s expected_key=%s actual_key=%s cover_url=%s",
        event,
        course_id,
        slug,
        title,
        cover_media_id or "<missing>",
        asset_state,
        reason or "<missing>",
        derived_bucket or "<missing>",
        derived_path or "<missing>",
        expected_key or "<missing>",
        actual_key or "<missing>",
        cover_url or "<missing>",
    )


def _normalize_course_cover_media_id(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _usable_legacy_cover_url(cover_url: Any) -> str | None:
    preview = {"cover_url": cover_url}
    media_signer.attach_cover_links(preview)
    normalized = str(preview.get("cover_url") or "").strip()
    return normalized or None


def _build_course_cover_payload(
    *,
    media_id: str | None,
    state: str,
    resolved_url: str | None,
    source: str,
) -> dict[str, Any]:
    return {
        "media_id": media_id,
        "state": state,
        "resolved_url": resolved_url,
        "source": source,
    }


def _valid_course_cover_processing_state(raw_state: Any) -> str:
    normalized = str(raw_state or "").strip().lower()
    if normalized in {"ready", "uploaded", "processing", "failed"}:
        return normalized
    return "missing"


def _course_cover_candidate_from_asset(
    asset: Mapping[str, Any],
) -> tuple[str | None, str | None]:
    bucket = (
        str(
            asset.get("streaming_storage_bucket")
            or asset.get("storage_bucket")
            or ""
        ).strip()
        or None
    )
    raw_path = str(asset.get("streaming_object_path") or "").strip() or None
    if not bucket or not raw_path:
        return None, None
    try:
        normalized_path = media_paths.normalize_storage_path(bucket, raw_path)
    except (RuntimeError, ValueError):
        return bucket, None
    return bucket, normalized_path


async def _course_cover_object_exists(
    *,
    storage_bucket: str,
    storage_path: str,
    existence: Mapping[tuple[str, str], bool],
    storage_table_available: bool,
) -> bool:
    normalized_bucket = str(storage_bucket or "").strip()
    normalized_path = str(storage_path or "").strip().lstrip("/")
    if not normalized_bucket or not normalized_path:
        return False

    if storage_table_available:
        return existence.get((normalized_bucket, normalized_path), False)

    try:
        await storage_service.get_storage_service(
            normalized_bucket
        ).get_presigned_url(
            normalized_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError:
        return False
    except storage_service.StorageServiceError:
        return False
    return True


def _course_cover_public_url(
    *,
    storage_bucket: str,
    storage_path: str,
) -> str | None:
    normalized_bucket = str(storage_bucket or "").strip()
    normalized_path = str(storage_path or "").strip().lstrip("/")
    if not normalized_bucket or not normalized_path:
        return None
    if normalized_bucket != settings.media_public_bucket:
        return None
    try:
        return storage_service.get_storage_service(normalized_bucket).public_url(
            normalized_path
        )
    except storage_service.StorageServiceError:
        return None


async def resolve_course_cover(
    *,
    course_id: str,
    cover_media_id: str | None,
    cover_url: str | None,
) -> dict[str, Any]:
    asset = (
        await media_assets_repo.get_media_asset(cover_media_id)
        if cover_media_id
        else None
    )
    existence: dict[tuple[str, str], bool] = {}
    storage_table_available = True

    asset_bucket, asset_path = _course_cover_candidate_from_asset(asset) if asset else (None, None)
    if asset and asset_bucket and asset_path:
        existence, storage_table_available = await storage_objects.fetch_storage_object_existence(
            [(asset_bucket, asset_path)]
        )

    return await _resolve_course_cover_payload(
        {
            "id": course_id,
            "slug": None,
            "title": None,
            "cover_media_id": cover_media_id,
            "cover_url": cover_url,
        },
        asset=asset,
        existence=existence,
        storage_table_available=storage_table_available,
    )


async def _resolve_course_cover_payload(
    course: Mapping[str, Any],
    *,
    asset: Mapping[str, Any] | None,
    existence: Mapping[tuple[str, str], bool],
    storage_table_available: bool,
) -> dict[str, Any]:
    cover_media_id = _normalize_course_cover_media_id(course.get("cover_media_id"))
    cover_url = str(course.get("cover_url") or "").strip() or None
    legacy_url = _usable_legacy_cover_url(cover_url)
    course_row_id = str(course.get("id") or "").strip() or None
    if not cover_media_id:
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=None,
                cover_url=cover_url,
                reason="no_cover_media_id",
            )
            return _build_course_cover_payload(
                media_id=None,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=None,
            state="placeholder",
            resolved_url=None,
            source="placeholder",
        )

    if asset is None:
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_ASSET_MISSING",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            reason="asset_missing",
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                reason="asset_missing",
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state="placeholder",
            resolved_url=None,
            source="placeholder",
        )

    asset_course_id = str(asset.get("course_id") or "").strip() or None
    asset_purpose = str(asset.get("purpose") or "").strip().lower()
    asset_state = str(asset.get("state") or "").strip().lower()
    if asset_purpose != "course_cover" or asset_course_id != course_row_id:
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_ASSET_MISSING",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            asset=asset,
            reason="invalid_asset_contract",
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="invalid_asset_contract",
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state="placeholder",
            resolved_url=None,
            source="placeholder",
        )

    if asset_state != "ready":
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_ASSET_NOT_READY",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            asset=asset,
            reason="asset_not_ready",
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="asset_not_ready",
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state=_valid_course_cover_processing_state(asset_state),
            resolved_url=None,
            source="placeholder",
        )

    derived_bucket, derived_path = _course_cover_candidate_from_asset(asset)
    if not derived_bucket or not derived_path:
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_DERIVED_BYTES_MISSING",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            asset=asset,
            reason="missing_derived_identity",
            derived_bucket=derived_bucket,
            derived_path=derived_path,
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="missing_derived_identity",
                derived_bucket=derived_bucket,
                derived_path=derived_path,
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state="missing",
            resolved_url=None,
            source="placeholder",
        )

    exists = await _course_cover_object_exists(
        storage_bucket=derived_bucket,
        storage_path=derived_path,
        existence=existence,
        storage_table_available=storage_table_available,
    )
    if not exists:
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_DERIVED_BYTES_MISSING",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            asset=asset,
            reason="derived_object_missing",
            derived_bucket=derived_bucket,
            derived_path=derived_path,
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="derived_object_missing",
                derived_bucket=derived_bucket,
                derived_path=derived_path,
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state="missing",
            resolved_url=None,
            source="placeholder",
        )

    resolved_url = _course_cover_public_url(
        storage_bucket=derived_bucket,
        storage_path=derived_path,
    )
    if not resolved_url:
        _log_course_cover_warning(
            "COURSE_COVER_RESOLVED_DERIVED_BYTES_MISSING",
            course=course,
            cover_media_id=cover_media_id,
            cover_url=cover_url,
            asset=asset,
            reason="derived_object_not_public",
            derived_bucket=derived_bucket,
            derived_path=derived_path,
        )
        if legacy_url:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_LEGACY_FALLBACK_USED",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="derived_object_not_public",
                derived_bucket=derived_bucket,
                derived_path=derived_path,
            )
            return _build_course_cover_payload(
                media_id=cover_media_id,
                state="legacy_fallback",
                resolved_url=legacy_url,
                source="legacy_cover_url",
            )
        return _build_course_cover_payload(
            media_id=cover_media_id,
            state="missing",
            resolved_url=None,
            source="placeholder",
        )

    if legacy_url:
        expected_key = _normalize_public_cover_key(derived_path)
        actual_key = _normalize_public_cover_key(legacy_url)
        if expected_key != actual_key:
            _log_course_cover_warning(
                "COURSE_COVER_RESOLVED_SOURCE_DISAGREE",
                course=course,
                cover_media_id=cover_media_id,
                cover_url=cover_url,
                asset=asset,
                reason="legacy_cover_url_disagrees",
                derived_bucket=derived_bucket,
                derived_path=derived_path,
                expected_key=expected_key,
                actual_key=actual_key,
            )

    return _build_course_cover_payload(
        media_id=cover_media_id,
        state="ready",
        resolved_url=resolved_url,
        source="control_plane",
    )


async def attach_course_cover_read_contract(
    courses: Mapping[str, Any] | Sequence[Mapping[str, Any]] | None,
) -> None:
    if courses is None:
        return

    if isinstance(courses, Mapping):
        rows: list[dict[str, Any]] = [courses if isinstance(courses, dict) else dict(courses)]
    else:
        rows = [row if isinstance(row, dict) else dict(row) for row in courses]
    if not rows:
        return

    media_ids = sorted(
        {
            media_id
            for media_id in (
                _normalize_course_cover_media_id(row.get("cover_media_id")) for row in rows
            )
            if media_id
        }
    )
    asset_rows = await asyncio.gather(
        *(media_assets_repo.get_media_asset(media_id) for media_id in media_ids)
    )
    assets_by_id = {
        media_id: asset
        for media_id, asset in zip(media_ids, asset_rows, strict=False)
    }

    candidate_pairs = sorted(
        {
            (bucket, path)
            for asset in asset_rows
            if asset
            for bucket, path in [_course_cover_candidate_from_asset(asset)]
            if bucket and path
        }
    )
    existence, storage_table_available = await storage_objects.fetch_storage_object_existence(
        candidate_pairs
    )

    include_cover = _course_cover_resolved_read_enabled()
    for row in rows:
        cover_media_id = _normalize_course_cover_media_id(row.get("cover_media_id"))
        resolution = await _resolve_course_cover_payload(
            row,
            asset=assets_by_id.get(cover_media_id) if cover_media_id else None,
            existence=existence,
            storage_table_available=storage_table_available,
        )
        if include_cover:
            row["cover"] = resolution
        else:
            row.pop("cover", None)


async def warn_course_cover_contracts(
    courses: Mapping[str, Any] | Sequence[Mapping[str, Any]] | None,
) -> None:
    await attach_course_cover_read_contract(courses)


def _apply_audio_content_type_fallback(item: dict[str, Any]) -> None:
    resolved = resolve_runtime_audio_content_type(
        kind=str(item.get("kind") or ""),
        content_type=item.get("content_type"),
        storage_path=item.get("storage_path"),
    )
    if resolved is not None:
        item["content_type"] = resolved


def _home_playback_state(resolution: RuntimeMediaResolution) -> str:
    if resolution.is_playable:
        if (
            resolution.playback_mode == RuntimeMediaPlaybackMode.LEGACY_STORAGE
            and resolution.requires_legacy_fallback
        ):
            return "legacy_fallback"
        return "ready"
    if not resolution.active:
        return "inactive"
    if resolution.failure_reason.value == "asset_not_ready":
        return str(resolution.media_state or "processing")
    if resolution.failure_reason.value == "lesson_media_not_found":
        return "missing"
    if resolution.failure_reason.value in {
        "missing_storage_identity",
        "missing_storage_object",
        "legacy_object_not_found",
        "missing_asset_link",
        "unsupported_media_contract",
    }:
        return "failed"
    return "unavailable"


async def _attach_home_playback_metadata(item: dict[str, Any]) -> None:
    runtime_media_id = str(item["id"])
    resolution = await canonical_media_resolver.resolve_runtime_media(runtime_media_id)
    item["runtime_media_id"] = resolution.runtime_media_id or runtime_media_id
    item["title"] = str(item.get("title") or item.get("lesson_title") or "").strip()
    item["lesson_title"] = item["title"]
    if resolution.kind:
        item["kind"] = resolution.kind
    if resolution.content_type:
        item["content_type"] = resolution.content_type
    if resolution.duration_seconds is not None:
        item["duration_seconds"] = resolution.duration_seconds
    item["is_playable"] = resolution.is_playable
    item["playback_state"] = _home_playback_state(resolution)
    item["failure_reason"] = resolution.failure_reason.value
    item["media_state"] = resolution.media_state or item.get("playback_state")

    for field in (
        "storage_path",
        "storage_bucket",
        "media_id",
        "media_asset_id",
        "download_url",
        "signed_url",
        "signed_url_expires_at",
    ):
        item.pop(field, None)


_KNOWN_BUCKET_PREFIXES: set[str] = {
    "course-media",
    "public-media",
    "lesson-media",
    settings.media_source_bucket,
    settings.media_public_bucket,
}


def _normalize_storage_path(value: str) -> str:
    raw = str(value or "").strip()
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in ("api/files/", "storage/v1/object/public/", "storage/v1/object/sign/"):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break
    return normalized


def _storage_candidates(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> list[tuple[str, str]]:
    normalized_bucket = (storage_bucket or "").strip() or settings.media_source_bucket
    normalized_path = _normalize_storage_path(storage_path)
    if not normalized_path:
        return []

    candidates: list[tuple[str, str]] = []

    def _add(bucket: str, key: str) -> None:
        if not bucket or not key:
            return
        pair = (bucket, key)
        if pair not in candidates:
            candidates.append(pair)

    def _add_for_bucket(bucket: str) -> None:
        prefix = f"{bucket}/"
        if normalized_path.startswith(prefix):
            stripped = normalized_path[len(prefix) :].lstrip("/")
            if stripped:
                _add(bucket, stripped)
            _add(bucket, normalized_path)
        else:
            _add(bucket, normalized_path)

    _add_for_bucket(normalized_bucket)

    prefix_bucket = normalized_path.split("/", 1)[0]
    if prefix_bucket in _KNOWN_BUCKET_PREFIXES and prefix_bucket != normalized_bucket:
        _add_for_bucket(prefix_bucket)

    return candidates


def _failure_reason(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> str:
    bucket = (storage_bucket or "").strip() or None
    normalized_path = _normalize_storage_path(storage_path)
    if not normalized_path:
        return "unsupported"
    prefix_bucket = normalized_path.split("/", 1)[0]
    if bucket and prefix_bucket in _KNOWN_BUCKET_PREFIXES and prefix_bucket != bucket:
        return "bucket_mismatch"
    if bucket and normalized_path.startswith(f"{bucket}/"):
        return "key_format_drift"
    return "missing_object"


def _best_storage_candidate(
    *,
    storage_bucket: str | None,
    storage_path: str | None,
    existence: dict[tuple[str, str], bool],
    storage_table_available: bool,
) -> tuple[str | None, str | None, str | None, bool | None]:
    if not storage_path:
        return None, None, "unsupported", None

    normalized_bucket = (storage_bucket or "").strip() or None
    normalized_path = _normalize_storage_path(str(storage_path))
    if not normalized_path:
        return normalized_bucket, None, "unsupported", None

    if not storage_table_available:
        return normalized_bucket, normalized_path, "manual_review", None

    candidates = _storage_candidates(
        storage_bucket=normalized_bucket,
        storage_path=normalized_path,
    )
    for candidate_bucket, candidate_key in candidates:
        if existence.get((candidate_bucket, candidate_key), False):
            # Detect unfixable drift: bytes exist only at bucket-prefixed key.
            if (
                normalized_bucket
                and normalized_path.startswith(f"{normalized_bucket}/")
                and candidate_bucket == normalized_bucket
                and candidate_key == normalized_path
            ):
                return candidate_bucket, candidate_key, "manual_review", True
            if candidate_bucket != normalized_bucket:
                return candidate_bucket, candidate_key, "bucket_mismatch", True
            stripped = (
                normalized_path[len(f"{normalized_bucket}/") :].lstrip("/")
                if normalized_bucket
                else normalized_path
            )
            if normalized_bucket and candidate_key == stripped and stripped != normalized_path:
                return candidate_bucket, candidate_key, "key_format_drift", True
            return candidate_bucket, candidate_key, None, True

    return (
        normalized_bucket,
        normalized_path,
        _failure_reason(
            storage_bucket=normalized_bucket,
            storage_path=normalized_path,
        ),
        False,
    )


def _attach_media_robustness(
    item: dict[str, Any],
    *,
    existence: dict[tuple[str, str], bool],
    storage_table_available: bool,
) -> None:
    kind = media_robustness.normalize_media_kind(item.get("kind"))
    supported_kind = kind in media_robustness.SUPPORTED_MEDIA_KINDS

    if item.get("media_asset_id"):
        category = media_robustness.MediaCategory.pipeline_media_asset
        state = (item.get("media_state") or "").strip().lower()
        bucket = (item.get("storage_bucket") or "").strip() or None
        path = item.get("storage_path")
        resolved_bucket, resolved_key, reason, bytes_exist = _best_storage_candidate(
            storage_bucket=bucket,
            storage_path=str(path) if path is not None else None,
            existence=existence,
            storage_table_available=storage_table_available,
        )

        if not supported_kind and kind != "audio":
            status = media_robustness.MediaStatus.unsupported
        elif reason == "manual_review" or not storage_table_available:
            status = media_robustness.MediaStatus.manual_review
        elif state == "ready" and bytes_exist is True:
            status = media_robustness.MediaStatus.ok
        elif state == "ready" and bytes_exist is False:
            status = media_robustness.MediaStatus.missing_bytes
        elif state == "failed":
            status = media_robustness.MediaStatus.unsupported
        else:
            status = media_robustness.MediaStatus.ok

        if state in {"uploaded", "processing"}:
            recommended_action = media_robustness.MediaRecommendedAction.keep
        else:
            recommended_action = media_robustness.recommended_action_for_status(status)

        resolvable = bool(bytes_exist) and state == "ready" and supported_kind
        item["robustness_category"] = str(category)
        item["robustness_status"] = str(status)
        item["robustness_recommended_action"] = str(recommended_action)
        item["resolvable_for_editor"] = resolvable
        item["resolvable_for_student"] = resolvable
        return

    # Legacy lesson media.
    category = media_robustness.MediaCategory.legacy_lesson_media
    bucket = item.get("storage_bucket")
    path = item.get("storage_path")
    resolved_bucket, resolved_key, reason, bytes_exist = _best_storage_candidate(
        storage_bucket=str(bucket) if bucket is not None else None,
        storage_path=str(path) if path is not None else None,
        existence=existence,
        storage_table_available=storage_table_available,
    )

    if reason == "manual_review" or not storage_table_available:
        status = media_robustness.MediaStatus.manual_review
    elif not supported_kind:
        status = media_robustness.MediaStatus.unsupported
        reason = "unsupported"
    elif bytes_exist is False or reason == "missing_object":
        status = media_robustness.MediaStatus.missing_bytes
        reason = "missing_object"
    elif reason in {"bucket_mismatch", "key_format_drift"}:
        status = media_robustness.MediaStatus.needs_migration
    else:
        status = media_robustness.MediaStatus.ok_legacy

    recommended_action = media_robustness.recommended_action_for_status(status)
    resolvable = bool(bytes_exist) and supported_kind

    item["robustness_category"] = str(category)
    item["robustness_status"] = str(status)
    item["robustness_recommended_action"] = str(recommended_action)
    item["resolvable_for_editor"] = resolvable
    item["resolvable_for_student"] = resolvable


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
    materialized = _materialize_optional_row(row)
    await warn_course_cover_contracts(materialized)
    return materialized


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
    materialized = _materialize_rows(rows)
    await warn_course_cover_contracts(materialized)
    return materialized


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
    materialized = _materialize_rows(rows)
    await warn_course_cover_contracts(materialized)
    return materialized


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
    deleted = await courses_repo.delete_course(course_id)
    if deleted:
        await media_cleanup.garbage_collect_media()
    return deleted


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
    deleted = await courses_repo.delete_module(module_id)
    if deleted:
        await media_cleanup.garbage_collect_media()
    return deleted


async def list_lessons(module_id: str) -> Sequence[dict[str, Any]]:
    """Return lessons for the supplied module."""
    rows = await courses_repo.list_lessons(module_id)
    return _materialize_rows(rows)


async def canonicalize_lesson_content(
    markdown: str,
    lesson_id: str | None,
) -> str:
    lesson_media_kinds: dict[str, str] = {}
    media_url_aliases: dict[str, str] = {}

    normalized_lesson_id = str(lesson_id or "").strip() or None
    if normalized_lesson_id is not None:
        lesson_media_rows = await courses_repo.list_lesson_media(normalized_lesson_id)
        lesson_media_kinds, media_url_aliases = build_lesson_media_write_contract(
            lesson_media_rows
        )

    return normalize_lesson_markdown_for_storage(
        markdown,
        lesson_media_kinds=lesson_media_kinds,
        media_url_aliases=media_url_aliases,
    )


async def create_lesson(
    course_id: str,
    *,
    title: str,
    content_markdown: str | None = None,
    position: int = 0,
    is_intro: bool = False,
    lesson_id: str | None = None,
) -> dict[str, Any]:
    content_value = content_markdown
    if isinstance(content_value, str):
        serialized = serialize_audio_embeds(content_value)
        content_value = await canonicalize_lesson_content(serialized, lesson_id)

    row = await courses_repo.create_lesson(
        course_id,
        title=title,
        content_markdown=content_value,
        position=position,
        is_intro=is_intro,
        lesson_id=lesson_id,
    )
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def list_lesson_media(
    lesson_id: str,
    *,
    mode: str | None = None,
) -> Sequence[dict[str, Any]]:
    """Return media entries for a lesson with download URLs."""
    normalized_mode = (mode or "").strip().lower()
    editor_mode = normalized_mode in {"editor_insert", "editor_preview"}
    rows = await courses_repo.list_lesson_media(lesson_id)
    items: list[dict[str, Any]] = []
    for row in rows:
        item = _materialize_mapping(row)
        if not item.get("storage_bucket") and not item.get("media_asset_id"):
            item["storage_bucket"] = "lesson-media"
        _apply_audio_content_type_fallback(item)
        media_signer.attach_media_links(item, purpose=mode)
        items.append(item)

    candidate_pairs: list[tuple[str, str]] = []
    for item in items:
        storage_path = item.get("storage_path")
        if not storage_path:
            continue
        storage_bucket = item.get("storage_bucket")
        candidate_pairs.extend(
            _storage_candidates(
                storage_bucket=str(storage_bucket) if storage_bucket is not None else None,
                storage_path=str(storage_path),
            )
        )

    existence, storage_table_available = await storage_objects.fetch_storage_object_existence(
        candidate_pairs
    )
    for item in items:
        _attach_media_robustness(
            item,
            existence=existence,
            storage_table_available=storage_table_available,
        )

    public_bucket = settings.media_public_bucket

    def _looks_like_public_bucket_url(url: str) -> bool:
        normalized = url.strip()
        if not normalized:
            return False
        if normalized.startswith(f"/api/files/{public_bucket}/"):
            return True
        if settings.supabase_url is None:
            return False
        base = settings.supabase_url.unicode_string().rstrip("/")
        return normalized.startswith(
            f"{base}/storage/v1/object/public/{public_bucket}/"
        )

    def _is_editor_safe_image_fallback_url(url: str) -> bool:
        normalized = url.strip()
        if not normalized:
            return False
        lowered = normalized.lower()
        if (
            lowered.startswith("/studio/media/")
            or lowered.startswith("/api/media/")
            or lowered.startswith("/media/sign")
            or lowered.startswith("/media/stream/")
        ):
            return False
        if normalized.startswith("/api/files/"):
            return True
        return _looks_like_public_bucket_url(normalized)

    # Ensure public bucket URLs are aligned with the actual storage object key.
    #
    # When legacy rows store a bucket-prefixed key inside the bucket (eg
    # public-media/public-media/...),
    # `attach_media_links()` will strip the bucket prefix and emit a public URL
    # that 404s in production. We have the storage.objects existence map here,
    # so we can select the correct candidate key and fix the URL deterministically.
    for item in items:
        if item.get("media_asset_id"):
            continue
        storage_path = item.get("storage_path")
        if not storage_path:
            continue
        storage_bucket = item.get("storage_bucket")
        resolved_bucket, resolved_key, _, bytes_exist = _best_storage_candidate(
            storage_bucket=str(storage_bucket) if storage_bucket is not None else None,
            storage_path=str(storage_path),
            existence=existence,
            storage_table_available=storage_table_available,
        )
        if bytes_exist is not True or not resolved_bucket or not resolved_key:
            continue

        playback_url = item.get("playback_url")
        download_url = item.get("download_url")
        signed_url = item.get("signed_url")

        if resolved_bucket == public_bucket:
            try:
                public_url = storage_service.get_storage_service(
                    resolved_bucket
                ).public_url(resolved_key)
            except storage_service.StorageServiceError:
                public_url = None

            if public_url:
                item["download_url"] = public_url
                item["playback_url"] = public_url
            elif isinstance(signed_url, str) and signed_url.strip():
                # Supabase URL missing/misconfigured; prefer signed streaming to avoid a broken public link.
                item["playback_url"] = signed_url
                if isinstance(download_url, str) and _looks_like_public_bucket_url(download_url):
                    item["download_url"] = signed_url
            continue

        # Not a public bucket candidate. If we accidentally emitted a public-media URL due to
        # bucket/path drift, force playback to the signed stream (which already tries candidates).
        if isinstance(playback_url, str) and _looks_like_public_bucket_url(playback_url):
            if isinstance(signed_url, str) and signed_url.strip():
                item["playback_url"] = signed_url
        if isinstance(download_url, str) and _looks_like_public_bucket_url(download_url):
            if isinstance(signed_url, str) and signed_url.strip():
                item["download_url"] = signed_url
            else:
                item.pop("download_url", None)

    async def _attach_pipeline_playback_url(item: dict[str, Any]) -> None:
        if item.get("kind") != "audio":
            return

        if editor_mode:
            resolvable = item.get("resolvable_for_editor") is True
        else:
            resolvable = item.get("resolvable_for_student") is True
        if not resolvable:
            return

        bucket = (item.get("storage_bucket") or "").strip() or None
        path = item.get("storage_path")
        if path is None:
            return

        try:
            item["playback_url"] = await media_resolver.resolve_lesson_media_playback_url(
                lesson_media_id=str(item["id"]),
                storage_path=str(path),
                storage_bucket=bucket,
                media_object_id=(
                    str(item["media_id"]) if item.get("media_id") is not None else None
                ),
            )
        except (ValueError, storage_service.StorageServiceError):
            return

    audio_items = [item for item in items if item.get("kind") == "audio"]
    if audio_items:
        await asyncio.gather(*[_attach_pipeline_playback_url(item) for item in audio_items])

    if editor_mode:
        for item in items:
            if str(item.get("kind") or "").strip().lower() == "image":
                preview_candidate = item.get("download_url") or item.get("playback_url")
                if (
                    isinstance(preview_candidate, str)
                    and _is_editor_safe_image_fallback_url(preview_candidate)
                ):
                    item["preferredUrl"] = preview_candidate
            item.pop("playback_url", None)
            item.pop("download_url", None)
            item.pop("signed_url", None)
            item.pop("thumbnail_url", None)
            item.pop("poster_frame", None)
    else:
        for item in items:
            item.pop("storage_path", None)
            item.pop("storage_bucket", None)
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
    await runtime_media_repo.sync_home_player_upload_runtime_media()
    rows = await courses_repo.list_home_audio_media(
        user_id,
        include_all_courses=False,
        limit=limit,
    )
    items = [_materialize_mapping(row) for row in rows]
    if items:
        await asyncio.gather(*(_attach_home_playback_metadata(item) for item in items))
    for item in items:
        _apply_audio_content_type_fallback(item)
    return items


async def upsert_lesson(
    course_id: str,
    payload: LessonPayload,
) -> dict[str, Any]:
    """Create or update lesson data."""
    lesson_payload: dict[str, Any] = dict(payload)
    lesson_id = str(lesson_payload.get("id") or "").strip() or None
    content_value = lesson_payload.get("content_markdown")
    if isinstance(content_value, str):
        serialized = serialize_audio_embeds(content_value)
        lesson_payload["content_markdown"] = await canonicalize_lesson_content(
            serialized,
            lesson_id,
        )

    row = await courses_repo.upsert_lesson(course_id, lesson_payload)
    materialized = _materialize_optional_row(row)
    return materialized or {}


async def delete_lesson(lesson_id: str) -> bool:
    """Delete a lesson via the repository layer."""
    deleted = await courses_repo.delete_lesson(lesson_id)
    if deleted:
        await media_cleanup.garbage_collect_media()
    return deleted


async def reorder_lessons(
    course_id: str,
    lesson_ids_in_order: Sequence[str],
) -> None:
    """Adjust lesson ordering for a course."""
    await courses_repo.reorder_lessons(course_id, lesson_ids_in_order)


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
    materialized = _materialize_rows(rows)
    await warn_course_cover_contracts(materialized)
    return materialized


async def fetch_lesson(lesson_id: str) -> dict[str, Any] | None:
    """Return a lesson by its id."""
    row = await courses_repo.get_lesson(lesson_id)
    materialized = _materialize_optional_row(row)
    content_markdown = materialized.get("content_markdown") if materialized else None
    if isinstance(content_markdown, str) and markdown_contains_legacy_document_media_links(
        content_markdown
    ):
        logger.warning(
            "LESSON_MEDIA_LEGACY_DOCUMENT_READ_COMPAT lesson_id=%s",
            lesson_id,
        )
    return materialized


async def lesson_course_ids(lesson_id: str) -> tuple[str | None, str | None]:
    """Return (module_id, course_id) for a lesson."""
    return await courses_repo.get_lesson_course_ids(lesson_id)


async def is_course_owner(user_id: str, course_id: str) -> bool:
    """Check if the user is the course owner."""
    return await courses_repo.is_course_owner(course_id, user_id)


async def is_course_teacher_or_instructor(user_id: str, course_id: str) -> bool:
    """Check if the user is the course creator or an assigned instructor."""
    return await courses_repo.is_course_teacher_or_instructor(course_id, user_id)


async def is_user_enrolled(user_id: str, course_id: str) -> bool:
    """Check whether the user is enrolled in the course."""
    return await courses_repo.is_enrolled(user_id, course_id)


async def enroll_free_intro(user_id: str, course_id: str) -> dict[str, Any]:
    """Apply intro access policy and enroll if allowed."""
    course = await fetch_course(course_id=course_id)
    if not course:
        return {"ok": False, "status": "not_found"}
    if not bool(course.get("is_free_intro")):
        return {"ok": False, "status": "not_free_intro"}

    if await courses_repo.user_owns_any_course_step(user_id, "step1"):
        await courses_repo.ensure_course_enrollment(user_id, course_id, source="free_intro")
        return {"ok": True, "status": "step1_unlimited"}

    membership = await get_membership(user_id)
    if not is_membership_active(
        (membership or {}).get("status") or "",
        (membership or {}).get("end_date"),
    ):
        return {"ok": False, "status": "subscription_required"}

    return await courses_repo.claim_intro_monthly_access(user_id, course_id, monthly_limit=1)


async def latest_order_for_course(user_id: str, course_id: str) -> dict[str, Any] | None:
    """Return the latest order for the given course/user pair."""
    return await get_latest_order_for_course(user_id, course_id)


async def course_access_snapshot(user_id: str, course_id: str) -> dict[str, Any]:
    """Return an access snapshot for course gating logic."""
    # Intro course limits were intentionally removed.
    # Access is no longer restricted by intro quotas.
    if await is_course_teacher_or_instructor(user_id, course_id):
        return {
            "can_access": True,
            "has_access": True,
            "access_reason": "teacher",
            "enrolled": False,
            "has_active_subscription": False,
            "latest_order": await latest_order_for_course(user_id, course_id),
        }

    enrolled = await is_user_enrolled(user_id, course_id)
    latest_order = await latest_order_for_course(user_id, course_id)
    profile = await get_profile(user_id)
    subscription = await get_latest_subscription(user_id)
    is_admin = _is_admin_profile(profile)
    has_active_subscription = (
        _has_active_subscription(profile, subscription) and not is_admin
    )
    has_access = enrolled or has_active_subscription or is_admin
    access_reason = "none"
    if enrolled:
        access_reason = "enrolled"
    elif has_active_subscription:
        access_reason = "subscription"
    elif is_admin:
        access_reason = "admin"

    return {
        "can_access": has_access,
        "access_reason": access_reason,
        "enrolled": enrolled,
        "has_active_subscription": has_active_subscription,
        "has_access": has_access,
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
    "is_course_teacher_or_instructor",
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
