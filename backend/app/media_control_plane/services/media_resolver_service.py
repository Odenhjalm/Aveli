from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import logging
from typing import Any

from ...config import settings
from ...db import get_conn
from ...repositories import storage_objects
from ...services import media_resolver

logger = logging.getLogger(__name__)

_LEGACY_BUCKET_FALLBACK = "lesson-media"
_FALLBACK_POLICIES_ALLOWING_LEGACY = {"legacy_only", "if_no_ready_asset"}


class RuntimeMediaPlaybackMode(str, Enum):
    NONE = "none"
    PIPELINE_ASSET = "pipeline_asset"
    LEGACY_STORAGE = "legacy_storage"


LessonMediaPlaybackMode = RuntimeMediaPlaybackMode


class RuntimeMediaResolutionReason(str, Enum):
    OK_READY_ASSET = "ok_ready_asset"
    OK_LEGACY_OBJECT = "ok_legacy_object"
    LESSON_MEDIA_NOT_FOUND = "lesson_media_not_found"
    MISSING_ASSET_LINK = "missing_asset_link"
    ASSET_NOT_READY = "asset_not_ready"
    MISSING_STORAGE_IDENTITY = "missing_storage_identity"
    MISSING_STORAGE_OBJECT = "missing_storage_object"
    INVALID_KIND = "invalid_kind"
    INVALID_CONTENT_TYPE = "invalid_content_type"
    LEGACY_OBJECT_NOT_FOUND = "legacy_object_not_found"
    LEGACY_FALLBACK_REQUIRED = "legacy_fallback_required"
    UNSUPPORTED_MEDIA_CONTRACT = "unsupported_media_contract"


LessonMediaResolutionReason = RuntimeMediaResolutionReason


@dataclass(slots=True)
class RuntimeMediaResolution:
    lesson_media_id: str | None
    media_asset_id: str | None
    legacy_media_object_id: str | None
    kind: str | None
    content_type: str | None
    media_state: str | None
    storage_bucket: str | None
    storage_path: str | None
    is_playable: bool
    playback_mode: RuntimeMediaPlaybackMode
    failure_reason: RuntimeMediaResolutionReason
    failure_detail: str | None = None
    lesson_id: str | None = None
    asset_purpose: str | None = None
    requires_legacy_fallback: bool = False
    runtime_media_id: str = ""
    reference_type: str | None = None
    auth_scope: str | None = None
    home_player_upload_id: str | None = None
    teacher_id: str | None = None
    course_id: str | None = None
    duration_seconds: int | None = None
    active: bool = True
    fallback_policy: str | None = None

    def log_fields(self) -> dict[str, Any]:
        return {
            "runtime_media_id": self.runtime_media_id,
            "reference_type": self.reference_type,
            "auth_scope": self.auth_scope,
            "lesson_media_id": self.lesson_media_id,
            "home_player_upload_id": self.home_player_upload_id,
            "teacher_id": self.teacher_id,
            "course_id": self.course_id,
            "lesson_id": self.lesson_id,
            "media_asset_id": self.media_asset_id,
            "legacy_media_object_id": self.legacy_media_object_id,
            "kind": self.kind,
            "content_type": self.content_type,
            "media_state": self.media_state,
            "duration_seconds": self.duration_seconds,
            "storage_bucket": self.storage_bucket,
            "storage_path": self.storage_path,
            "active": self.active,
            "is_playable": self.is_playable,
            "playback_mode": self.playback_mode.value,
            "failure_reason": self.failure_reason.value,
            "failure_detail": self.failure_detail,
            "asset_purpose": self.asset_purpose,
            "requires_legacy_fallback": self.requires_legacy_fallback,
            "fallback_policy": self.fallback_policy,
        }


LessonMediaResolution = RuntimeMediaResolution


def _normalize_text(value: Any) -> str | None:
    normalized = str(value or "").strip()
    return normalized or None


def _normalize_path(value: Any) -> str | None:
    normalized = _normalize_text(value)
    if normalized is None:
        return None
    return normalized.replace("\\", "/").lstrip("/")


def _normalize_kind(raw_kind: Any, *, content_type: str | None, asset_media_type: str | None) -> str | None:
    normalized = _normalize_text(raw_kind)
    if normalized is not None:
        lowered = normalized.lower()
        if lowered == "pdf":
            return "document"
        return lowered
    if asset_media_type:
        return asset_media_type
    if not content_type:
        return None
    if content_type.startswith("audio/"):
        return "audio"
    if content_type.startswith("video/"):
        return "video"
    if content_type.startswith("image/"):
        return "image"
    if content_type == "application/pdf":
        return "document"
    return None


def _normalize_content_type(row: dict[str, Any]) -> str | None:
    object_content_type = _normalize_text(row.get("object_content_type"))
    if object_content_type is not None:
        return object_content_type.lower()

    asset_media_type = _normalize_text(row.get("asset_media_type"))
    asset_state = _normalize_text(row.get("asset_state"))
    if asset_state == "ready" and asset_media_type == "audio":
        return "audio/mpeg"

    asset_content_type = _normalize_text(row.get("asset_original_content_type"))
    if asset_content_type is not None:
        return asset_content_type.lower()
    return None


def _choose_legacy_storage(row: dict[str, Any]) -> tuple[str | None, str | None, str | None]:
    object_path = _normalize_path(row.get("object_storage_path"))
    object_bucket = _normalize_text(row.get("object_storage_bucket"))
    legacy_path = _normalize_path(row.get("lesson_storage_path"))
    legacy_bucket = _normalize_text(row.get("lesson_storage_bucket"))

    if object_path:
        return object_bucket or legacy_bucket or _LEGACY_BUCKET_FALLBACK, object_path, "media_object"
    if legacy_path:
        return legacy_bucket or object_bucket or _LEGACY_BUCKET_FALLBACK, legacy_path, "runtime_media"

    if row.get("media_id") and not row.get("media_object_id"):
        return None, None, "missing_media_object"
    if object_bucket or legacy_bucket:
        return None, None, "incomplete_storage_identity"
    return None, None, None


def _asset_ready_storage(row: dict[str, Any]) -> tuple[str | None, str | None]:
    storage_path = _normalize_path(
        row.get("asset_streaming_object_path") or row.get("asset_original_object_path")
    )
    storage_bucket = _normalize_text(
        row.get("asset_streaming_storage_bucket") or row.get("asset_storage_bucket")
    )
    if storage_path and storage_bucket is None:
        storage_bucket = settings.media_source_bucket
    return storage_bucket, storage_path


def _fallback_policy_allows_legacy(fallback_policy: str | None) -> bool:
    return (fallback_policy or "") in _FALLBACK_POLICIES_ALLOWING_LEGACY


class MediaResolverService:
    async def lookup_runtime_media_id_for_lesson_media(self, lesson_media_id: str) -> str | None:
        normalized_lesson_media_id = _normalize_text(lesson_media_id)
        if normalized_lesson_media_id is None:
            return None

        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT id
                FROM app.runtime_media
                WHERE lesson_media_id = %s
                LIMIT 1
                """,
                (normalized_lesson_media_id,),
            )
            row = await cur.fetchone()
        if not row:
            return None
        return str(row["id"])

    async def resolve_runtime_media(self, runtime_media_id: str) -> RuntimeMediaResolution:
        normalized_runtime_media_id = _normalize_text(runtime_media_id)
        if normalized_runtime_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id=None,
                failure_detail="runtime_media_id is required",
            )
            self._log_resolution(result)
            return result

        row = await self._fetch_runtime_media_contract_row(normalized_runtime_media_id)
        if not row:
            result = self._not_found_resolution(
                runtime_media_id=normalized_runtime_media_id,
                lesson_media_id=None,
                failure_detail="runtime_media row missing",
            )
            self._log_resolution(result)
            return result

        result = await self._resolve_row(row)
        self._log_resolution(result)
        return result

    async def resolve_lesson_media(self, lesson_media_id: str) -> RuntimeMediaResolution:
        normalized_lesson_media_id = _normalize_text(lesson_media_id)
        if normalized_lesson_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id="",
                failure_detail="lesson_media_id is required",
            )
            self._log_resolution(result)
            return result

        runtime_media_id = await self.lookup_runtime_media_id_for_lesson_media(normalized_lesson_media_id)
        if runtime_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id=normalized_lesson_media_id,
                failure_detail="runtime_media row missing for lesson_media",
            )
            self._log_resolution(result)
            return result

        result = await self.resolve_runtime_media(runtime_media_id)
        if result.lesson_media_id is None:
            result.lesson_media_id = normalized_lesson_media_id
        return result

    async def _fetch_runtime_media_contract_row(
        self,
        runtime_media_id: str,
    ) -> dict[str, Any] | None:
        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT
                  rm.id AS runtime_media_id,
                  rm.reference_type,
                  rm.auth_scope,
                  rm.fallback_policy,
                  rm.active,
                  rm.lesson_media_id,
                  rm.home_player_upload_id,
                  rm.teacher_id,
                  rm.course_id,
                  rm.lesson_id,
                  rm.kind AS lesson_kind,
                  rm.media_asset_id,
                  rm.media_object_id AS media_id,
                  rm.legacy_storage_path AS lesson_storage_path,
                  rm.legacy_storage_bucket AS lesson_storage_bucket,
                  mo.id AS media_object_id,
                  mo.storage_path AS object_storage_path,
                  mo.storage_bucket AS object_storage_bucket,
                  mo.content_type AS object_content_type,
                  ma.id AS asset_row_id,
                  ma.media_type AS asset_media_type,
                  ma.purpose AS asset_purpose,
                  ma.state AS asset_state,
                  ma.original_object_path AS asset_original_object_path,
                  ma.storage_bucket AS asset_storage_bucket,
                  ma.streaming_object_path AS asset_streaming_object_path,
                  ma.streaming_storage_bucket AS asset_streaming_storage_bucket,
                  ma.original_content_type AS asset_original_content_type,
                  ma.streaming_format AS asset_streaming_format,
                  ma.error_message AS asset_error_message,
                  coalesce(ma.duration_seconds, lm.duration_seconds) AS duration_seconds
                FROM app.runtime_media rm
                LEFT JOIN app.lesson_media lm ON lm.id = rm.lesson_media_id
                LEFT JOIN app.media_objects mo ON mo.id = rm.media_object_id
                LEFT JOIN app.media_assets ma ON ma.id = rm.media_asset_id
                WHERE rm.id = %s
                LIMIT 1
                """,
                (runtime_media_id,),
            )
            return await cur.fetchone()

    async def _resolve_row(self, row: dict[str, Any]) -> RuntimeMediaResolution:
        runtime_media_id = str(row["runtime_media_id"])
        lesson_media_id = _normalize_text(row.get("lesson_media_id"))
        lesson_id = _normalize_text(row.get("lesson_id"))
        reference_type = _normalize_text(row.get("reference_type"))
        auth_scope = _normalize_text(row.get("auth_scope"))
        home_player_upload_id = _normalize_text(row.get("home_player_upload_id"))
        teacher_id = _normalize_text(row.get("teacher_id"))
        course_id = _normalize_text(row.get("course_id"))
        media_asset_id = _normalize_text(row.get("media_asset_id"))
        asset_row_id = _normalize_text(row.get("asset_row_id"))
        legacy_media_object_id = _normalize_text(row.get("media_id"))
        asset_purpose = _normalize_text(row.get("asset_purpose"))
        media_state = _normalize_text(row.get("asset_state"))
        fallback_policy = _normalize_text(row.get("fallback_policy"))
        active = bool(row.get("active", True))
        duration_seconds = row.get("duration_seconds")
        if duration_seconds is not None:
            duration_seconds = int(duration_seconds)

        if not active:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                legacy_media_object_id=legacy_media_object_id,
                kind=_normalize_text(row.get("lesson_kind")),
                content_type=_normalize_content_type(row),
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
                failure_detail="runtime_media row is inactive",
                asset_purpose=asset_purpose,
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=False,
                fallback_policy=fallback_policy,
            )

        content_type = _normalize_content_type(row)
        asset_media_type = _normalize_text(row.get("asset_media_type"))
        kind = _normalize_kind(
            row.get("lesson_kind"),
            content_type=content_type,
            asset_media_type=asset_media_type,
        )

        if kind is None and content_type is None and media_asset_id is None and legacy_media_object_id is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=None,
                legacy_media_object_id=None,
                kind=None,
                content_type=None,
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
                failure_detail="runtime_media has no asset or legacy storage reference",
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=active,
                fallback_policy=fallback_policy,
            )

        legacy_bucket, legacy_path, legacy_source = _choose_legacy_storage(row)
        can_fallback_to_legacy = _fallback_policy_allows_legacy(fallback_policy)

        if media_asset_id:
            if asset_row_id is None:
                if can_fallback_to_legacy and legacy_path:
                    fallback_result = await self._legacy_resolution(
                        runtime_media_id=runtime_media_id,
                        lesson_media_id=lesson_media_id,
                        lesson_id=lesson_id,
                        reference_type=reference_type,
                        auth_scope=auth_scope,
                        home_player_upload_id=home_player_upload_id,
                        teacher_id=teacher_id,
                        course_id=course_id,
                        media_asset_id=media_asset_id,
                        legacy_media_object_id=legacy_media_object_id,
                        kind=kind,
                        content_type=content_type,
                        media_state=media_state,
                        duration_seconds=duration_seconds,
                        asset_purpose=asset_purpose,
                        fallback_policy=fallback_policy,
                        legacy_bucket=legacy_bucket,
                        legacy_path=legacy_path,
                        legacy_source=legacy_source,
                        failure_reason=RuntimeMediaResolutionReason.LEGACY_FALLBACK_REQUIRED,
                        failure_detail="media_asset link is broken; using legacy storage",
                        requires_legacy_fallback=True,
                    )
                    if fallback_result is not None:
                        return fallback_result

                reason = (
                    RuntimeMediaResolutionReason.LEGACY_OBJECT_NOT_FOUND
                    if legacy_media_object_id and legacy_source == "missing_media_object"
                    else RuntimeMediaResolutionReason.MISSING_ASSET_LINK
                )
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=None,
                    storage_path=None,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=reason,
                    failure_detail="media_asset row missing",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            if media_state != "ready":
                if can_fallback_to_legacy and legacy_path:
                    fallback_result = await self._legacy_resolution(
                        runtime_media_id=runtime_media_id,
                        lesson_media_id=lesson_media_id,
                        lesson_id=lesson_id,
                        reference_type=reference_type,
                        auth_scope=auth_scope,
                        home_player_upload_id=home_player_upload_id,
                        teacher_id=teacher_id,
                        course_id=course_id,
                        media_asset_id=media_asset_id,
                        legacy_media_object_id=legacy_media_object_id,
                        kind=kind,
                        content_type=content_type,
                        media_state=media_state,
                        duration_seconds=duration_seconds,
                        asset_purpose=asset_purpose,
                        fallback_policy=fallback_policy,
                        legacy_bucket=legacy_bucket,
                        legacy_path=legacy_path,
                        legacy_source=legacy_source,
                        failure_reason=RuntimeMediaResolutionReason.LEGACY_FALLBACK_REQUIRED,
                        failure_detail=f"media_asset state is {media_state or 'unknown'}; using legacy storage",
                        requires_legacy_fallback=True,
                    )
                    if fallback_result is not None:
                        return fallback_result

                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=None,
                    storage_path=None,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.ASSET_NOT_READY,
                    failure_detail=f"media_asset state is {media_state or 'unknown'}",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            asset_bucket, asset_path = _asset_ready_storage(row)
            if not asset_path:
                if can_fallback_to_legacy and legacy_path:
                    fallback_result = await self._legacy_resolution(
                        runtime_media_id=runtime_media_id,
                        lesson_media_id=lesson_media_id,
                        lesson_id=lesson_id,
                        reference_type=reference_type,
                        auth_scope=auth_scope,
                        home_player_upload_id=home_player_upload_id,
                        teacher_id=teacher_id,
                        course_id=course_id,
                        media_asset_id=media_asset_id,
                        legacy_media_object_id=legacy_media_object_id,
                        kind=kind,
                        content_type=content_type,
                        media_state=media_state,
                        duration_seconds=duration_seconds,
                        asset_purpose=asset_purpose,
                        fallback_policy=fallback_policy,
                        legacy_bucket=legacy_bucket,
                        legacy_path=legacy_path,
                        legacy_source=legacy_source,
                        failure_reason=RuntimeMediaResolutionReason.LEGACY_FALLBACK_REQUIRED,
                        failure_detail="ready media_asset missing playback storage; using legacy storage",
                        requires_legacy_fallback=True,
                    )
                    if fallback_result is not None:
                        return fallback_result

                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=None,
                    storage_path=None,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.MISSING_STORAGE_IDENTITY,
                    failure_detail="ready media_asset has no playback storage path",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            if asset_bucket is None:
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=None,
                    storage_path=None,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.MISSING_STORAGE_IDENTITY,
                    failure_detail="ready media_asset has no playback storage bucket",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            if asset_purpose == "lesson_audio" and not media_resolver.is_derived_audio_path(asset_path):
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=asset_bucket,
                    storage_path=asset_path,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.UNSUPPORTED_MEDIA_CONTRACT,
                    failure_detail="lesson_audio assets must resolve to derived audio playback",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            asset_exists = await self._storage_object_exists(
                storage_bucket=asset_bucket,
                storage_path=asset_path,
            )
            if not asset_exists:
                if can_fallback_to_legacy and legacy_path:
                    fallback_result = await self._legacy_resolution(
                        runtime_media_id=runtime_media_id,
                        lesson_media_id=lesson_media_id,
                        lesson_id=lesson_id,
                        reference_type=reference_type,
                        auth_scope=auth_scope,
                        home_player_upload_id=home_player_upload_id,
                        teacher_id=teacher_id,
                        course_id=course_id,
                        media_asset_id=media_asset_id,
                        legacy_media_object_id=legacy_media_object_id,
                        kind=kind,
                        content_type=content_type,
                        media_state=media_state,
                        duration_seconds=duration_seconds,
                        asset_purpose=asset_purpose,
                        fallback_policy=fallback_policy,
                        legacy_bucket=legacy_bucket,
                        legacy_path=legacy_path,
                        legacy_source=legacy_source,
                        failure_reason=RuntimeMediaResolutionReason.LEGACY_FALLBACK_REQUIRED,
                        failure_detail="ready media_asset playback object is missing; using legacy storage",
                        requires_legacy_fallback=True,
                    )
                    if fallback_result is not None:
                        return fallback_result

                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    legacy_media_object_id=legacy_media_object_id,
                    kind=kind,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=asset_bucket,
                    storage_path=asset_path,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.MISSING_STORAGE_OBJECT,
                    failure_detail="ready media_asset playback object is missing",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                    fallback_policy=fallback_policy,
                )

            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                legacy_media_object_id=legacy_media_object_id,
                kind=kind,
                content_type=content_type,
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=asset_bucket,
                storage_path=asset_path,
                is_playable=True,
                playback_mode=RuntimeMediaPlaybackMode.PIPELINE_ASSET,
                failure_reason=RuntimeMediaResolutionReason.OK_READY_ASSET,
                asset_purpose=asset_purpose,
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=active,
                fallback_policy=fallback_policy,
            )

        if legacy_path:
            fallback_result = await self._legacy_resolution(
                runtime_media_id=runtime_media_id,
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                media_asset_id=None,
                legacy_media_object_id=legacy_media_object_id,
                kind=kind,
                content_type=content_type,
                media_state=media_state or "ready",
                duration_seconds=duration_seconds,
                asset_purpose=asset_purpose,
                fallback_policy=fallback_policy,
                legacy_bucket=legacy_bucket,
                legacy_path=legacy_path,
                legacy_source=legacy_source,
                failure_reason=RuntimeMediaResolutionReason.OK_LEGACY_OBJECT,
                failure_detail=None,
                requires_legacy_fallback=False,
            )
            if fallback_result is not None:
                return fallback_result

        failure_reason = RuntimeMediaResolutionReason.MISSING_ASSET_LINK
        if legacy_media_object_id and legacy_source == "missing_media_object":
            failure_reason = RuntimeMediaResolutionReason.LEGACY_OBJECT_NOT_FOUND
        elif legacy_source == "incomplete_storage_identity":
            failure_reason = RuntimeMediaResolutionReason.MISSING_STORAGE_IDENTITY

        return RuntimeMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=lesson_id,
            media_asset_id=None,
            legacy_media_object_id=legacy_media_object_id,
            kind=kind,
            content_type=content_type,
            media_state=media_state,
            duration_seconds=duration_seconds,
            storage_bucket=None,
            storage_path=None,
            is_playable=False,
            playback_mode=RuntimeMediaPlaybackMode.NONE,
            failure_reason=failure_reason,
            failure_detail="legacy storage identity is not complete",
            runtime_media_id=runtime_media_id,
            reference_type=reference_type,
            auth_scope=auth_scope,
            home_player_upload_id=home_player_upload_id,
            teacher_id=teacher_id,
            course_id=course_id,
            active=active,
            fallback_policy=fallback_policy,
        )

    async def _legacy_resolution(
        self,
        *,
        runtime_media_id: str,
        lesson_media_id: str | None,
        lesson_id: str | None,
        reference_type: str | None,
        auth_scope: str | None,
        home_player_upload_id: str | None,
        teacher_id: str | None,
        course_id: str | None,
        media_asset_id: str | None,
        legacy_media_object_id: str | None,
        kind: str | None,
        content_type: str | None,
        media_state: str | None,
        duration_seconds: int | None,
        asset_purpose: str | None,
        fallback_policy: str | None,
        legacy_bucket: str | None,
        legacy_path: str | None,
        legacy_source: str | None,
        failure_reason: RuntimeMediaResolutionReason,
        failure_detail: str | None,
        requires_legacy_fallback: bool,
    ) -> RuntimeMediaResolution | None:
        if legacy_path is None or legacy_bucket is None:
            return None

        storage_exists = await self._storage_object_exists(
            storage_bucket=legacy_bucket,
            storage_path=legacy_path,
        )
        if not storage_exists:
            not_found_reason = RuntimeMediaResolutionReason.MISSING_STORAGE_OBJECT
            if legacy_media_object_id and legacy_source == "missing_media_object":
                not_found_reason = RuntimeMediaResolutionReason.LEGACY_OBJECT_NOT_FOUND
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                legacy_media_object_id=legacy_media_object_id,
                kind=kind,
                content_type=content_type,
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=legacy_bucket,
                storage_path=legacy_path,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=not_found_reason,
                failure_detail="legacy storage object is missing",
                asset_purpose=asset_purpose,
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=True,
                fallback_policy=fallback_policy,
            )

        return RuntimeMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=lesson_id,
            media_asset_id=media_asset_id,
            legacy_media_object_id=legacy_media_object_id,
            kind=kind,
            content_type=content_type,
            media_state=media_state,
            duration_seconds=duration_seconds,
            storage_bucket=legacy_bucket,
            storage_path=legacy_path,
            is_playable=True,
            playback_mode=RuntimeMediaPlaybackMode.LEGACY_STORAGE,
            failure_reason=failure_reason,
            failure_detail=failure_detail,
            asset_purpose=asset_purpose,
            requires_legacy_fallback=requires_legacy_fallback,
            runtime_media_id=runtime_media_id,
            reference_type=reference_type,
            auth_scope=auth_scope,
            home_player_upload_id=home_player_upload_id,
            teacher_id=teacher_id,
            course_id=course_id,
            active=True,
            fallback_policy=fallback_policy,
        )

    async def _storage_object_exists(
        self,
        *,
        storage_bucket: str,
        storage_path: str,
    ) -> bool:
        existence, storage_table_available = await storage_objects.fetch_storage_object_existence(
            [(storage_bucket, storage_path)]
        )
        if not storage_table_available:
            return True
        return existence.get((storage_bucket, storage_path), False)

    def _not_found_resolution(
        self,
        *,
        runtime_media_id: str,
        lesson_media_id: str | None,
        failure_detail: str,
    ) -> RuntimeMediaResolution:
        return RuntimeMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=None,
            media_asset_id=None,
            legacy_media_object_id=None,
            kind=None,
            content_type=None,
            media_state=None,
            duration_seconds=None,
            storage_bucket=None,
            storage_path=None,
            is_playable=False,
            playback_mode=RuntimeMediaPlaybackMode.NONE,
            failure_reason=RuntimeMediaResolutionReason.LESSON_MEDIA_NOT_FOUND,
            failure_detail=failure_detail,
            runtime_media_id=runtime_media_id,
        )

    def _log_resolution(self, result: RuntimeMediaResolution) -> None:
        if not result.is_playable:
            logger.warning("RUNTIME_MEDIA_RESOLUTION_FAILED", extra=result.log_fields())
            return
        if result.requires_legacy_fallback:
            logger.info("RUNTIME_MEDIA_RESOLUTION_FALLBACK", extra=result.log_fields())
            return
        logger.debug("RUNTIME_MEDIA_RESOLVED", extra=result.log_fields())


media_resolver_service = MediaResolverService()


__all__ = [
    "LessonMediaPlaybackMode",
    "LessonMediaResolution",
    "LessonMediaResolutionReason",
    "MediaResolverService",
    "RuntimeMediaPlaybackMode",
    "RuntimeMediaResolution",
    "RuntimeMediaResolutionReason",
    "media_resolver_service",
]
