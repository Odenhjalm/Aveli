from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import logging
from typing import Any

from ...db import get_conn
from ...repositories import storage_objects
from ...services import media_resolver

logger = logging.getLogger(__name__)


class RuntimeMediaPlaybackMode(str, Enum):
    NONE = "none"
    PIPELINE_ASSET = "pipeline_asset"


LessonMediaPlaybackMode = RuntimeMediaPlaybackMode


class RuntimeMediaResolutionReason(str, Enum):
    OK_READY_ASSET = "ok_ready_asset"
    LESSON_MEDIA_NOT_FOUND = "lesson_media_not_found"
    MISSING_ASSET_LINK = "missing_asset_link"
    ASSET_NOT_READY = "asset_not_ready"
    MISSING_STORAGE_IDENTITY = "missing_storage_identity"
    MISSING_STORAGE_OBJECT = "missing_storage_object"
    INVALID_KIND = "invalid_kind"
    INVALID_CONTENT_TYPE = "invalid_content_type"
    UNSUPPORTED_MEDIA_CONTRACT = "unsupported_media_contract"


LessonMediaResolutionReason = RuntimeMediaResolutionReason


@dataclass(slots=True)
class RuntimeMediaResolution:
    lesson_media_id: str | None
    media_asset_id: str | None
    media_type: str | None
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
    runtime_media_id: str = ""
    reference_type: str | None = None
    auth_scope: str | None = None
    home_player_upload_id: str | None = None
    teacher_id: str | None = None
    course_id: str | None = None
    duration_seconds: int | None = None
    active: bool = True

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
            "media_type": self.media_type,
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
        }


LessonMediaResolution = RuntimeMediaResolution


def _exact_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value or None
    return str(value)


def _exact_content_type(row: dict[str, Any]) -> str | None:
    return _exact_text(row.get("asset_original_content_type"))


def _asset_ready_storage(row: dict[str, Any]) -> tuple[str | None, str | None]:
    return (
        _exact_text(row.get("asset_streaming_storage_bucket")),
        _exact_text(row.get("asset_streaming_object_path")),
    )


class MediaResolverService:
    async def lookup_runtime_media_id_for_lesson_media(self, lesson_media_id: str) -> str | None:
        exact_lesson_media_id = _exact_text(lesson_media_id)
        if exact_lesson_media_id is None:
            return None

        async with get_conn() as cur:
            await cur.execute(
                """
                SELECT id
                FROM app.runtime_media
                WHERE lesson_media_id = %s
                  AND active = true
                  AND app.is_test_row_visible(is_test, test_session_id)
                ORDER BY updated_at DESC, created_at DESC
                LIMIT 1
                """,
                (exact_lesson_media_id,),
            )
            row = await cur.fetchone()
        if not row:
            return None
        return str(row["id"])

    async def resolve_runtime_media(
        self,
        runtime_media_id: str,
        *,
        emit_logs: bool = True,
    ) -> RuntimeMediaResolution:
        exact_runtime_media_id = _exact_text(runtime_media_id)
        if exact_runtime_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id=None,
                failure_detail="runtime_media_id is required",
            )
            if emit_logs:
                self._log_resolution(result)
            return result

        row = await self._fetch_runtime_media_contract_row(exact_runtime_media_id)
        if not row:
            result = self._not_found_resolution(
                runtime_media_id=exact_runtime_media_id,
                lesson_media_id=None,
                failure_detail="runtime_media row missing",
            )
            if emit_logs:
                self._log_resolution(result)
            return result

        result = await self._resolve_row(row)
        if emit_logs:
            self._log_resolution(result)
        return result

    async def resolve_lesson_media(
        self,
        lesson_media_id: str,
        *,
        emit_logs: bool = True,
    ) -> RuntimeMediaResolution:
        exact_lesson_media_id = _exact_text(lesson_media_id)
        if exact_lesson_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id="",
                failure_detail="lesson_media_id is required",
            )
            if emit_logs:
                self._log_resolution(result)
            return result

        runtime_media_id = await self.lookup_runtime_media_id_for_lesson_media(exact_lesson_media_id)
        if runtime_media_id is None:
            result = self._not_found_resolution(
                runtime_media_id="",
                lesson_media_id=exact_lesson_media_id,
                failure_detail="runtime_media row missing for lesson_media",
            )
            if emit_logs:
                self._log_resolution(result)
            return result

        result = await self.resolve_runtime_media(runtime_media_id, emit_logs=emit_logs)
        if result.lesson_media_id is None:
            result.lesson_media_id = exact_lesson_media_id
        return result

    async def inspect_runtime_media(self, runtime_media_id: str) -> RuntimeMediaResolution:
        return await self.resolve_runtime_media(runtime_media_id, emit_logs=False)

    async def inspect_lesson_media(self, lesson_media_id: str) -> RuntimeMediaResolution:
        return await self.resolve_lesson_media(lesson_media_id, emit_logs=False)

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
                  rm.active,
                  rm.lesson_media_id,
                  rm.home_player_upload_id,
                  rm.teacher_id,
                  rm.course_id,
                  rm.lesson_id,
                  rm.media_asset_id,
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
                LEFT JOIN app.media_assets ma ON ma.id = rm.media_asset_id
                WHERE rm.id = %s
                  AND app.is_test_row_visible(rm.is_test, rm.test_session_id)
                LIMIT 1
                """,
                (runtime_media_id,),
            )
            return await cur.fetchone()

    async def _resolve_row(self, row: dict[str, Any]) -> RuntimeMediaResolution:
        runtime_media_id = str(row["runtime_media_id"])
        lesson_media_id = _exact_text(row.get("lesson_media_id"))
        lesson_id = _exact_text(row.get("lesson_id"))
        reference_type = _exact_text(row.get("reference_type"))
        auth_scope = _exact_text(row.get("auth_scope"))
        home_player_upload_id = _exact_text(row.get("home_player_upload_id"))
        teacher_id = _exact_text(row.get("teacher_id"))
        course_id = _exact_text(row.get("course_id"))
        media_asset_id = _exact_text(row.get("media_asset_id"))
        asset_row_id = _exact_text(row.get("asset_row_id"))
        asset_purpose = _exact_text(row.get("asset_purpose"))
        media_state = _exact_text(row.get("asset_state"))
        active = bool(row.get("active", True))
        duration_seconds = row.get("duration_seconds")
        if duration_seconds is not None:
            duration_seconds = int(duration_seconds)

        if not active:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=_exact_text(row.get("asset_media_type")),
                content_type=_exact_content_type(row),
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
            )

        content_type = _exact_content_type(row)
        media_type = _exact_text(row.get("asset_media_type"))

        if media_asset_id is not None and media_type is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=None,
                content_type=content_type,
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.INVALID_KIND,
                failure_detail="media_asset media_type is missing",
                asset_purpose=asset_purpose,
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=active,
            )

        if media_type is None and content_type is None and media_asset_id is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=None,
                media_type=None,
                content_type=None,
                media_state=media_state,
                duration_seconds=duration_seconds,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
                failure_detail="runtime_media has no canonical asset-backed playback source",
                runtime_media_id=runtime_media_id,
                reference_type=reference_type,
                auth_scope=auth_scope,
                home_player_upload_id=home_player_upload_id,
                teacher_id=teacher_id,
                course_id=course_id,
                active=active,
            )

        if media_asset_id:
            if asset_row_id is None:
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
                    content_type=content_type,
                    media_state=media_state,
                    duration_seconds=duration_seconds,
                    storage_bucket=None,
                    storage_path=None,
                    is_playable=False,
                    playback_mode=RuntimeMediaPlaybackMode.NONE,
                    failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
                    failure_detail="media_asset row missing",
                    asset_purpose=asset_purpose,
                    runtime_media_id=runtime_media_id,
                    reference_type=reference_type,
                    auth_scope=auth_scope,
                    home_player_upload_id=home_player_upload_id,
                    teacher_id=teacher_id,
                    course_id=course_id,
                    active=active,
                )

            if media_state != "ready":
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
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
                )

            asset_bucket, asset_path = _asset_ready_storage(row)
            if not asset_path:
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
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
                )

            if asset_bucket is None:
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
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
                )

            if asset_purpose == "lesson_audio" and not media_resolver.is_derived_audio_path(asset_path):
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
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
                )

            asset_exists = await self._storage_object_exists(
                storage_bucket=asset_bucket,
                storage_path=asset_path,
            )
            if not asset_exists:
                return RuntimeMediaResolution(
                    lesson_media_id=lesson_media_id,
                    lesson_id=lesson_id,
                    media_asset_id=media_asset_id,
                    media_type=media_type,
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
                )

            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=media_type,
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
                )

        return RuntimeMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=lesson_id,
            media_asset_id=None,
            media_type=media_type,
            content_type=content_type,
            media_state=media_state,
            duration_seconds=duration_seconds,
            storage_bucket=None,
            storage_path=None,
            is_playable=False,
            playback_mode=RuntimeMediaPlaybackMode.NONE,
            failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
            failure_detail="runtime_media has no canonical asset-backed playback source",
            runtime_media_id=runtime_media_id,
            reference_type=reference_type,
            auth_scope=auth_scope,
            home_player_upload_id=home_player_upload_id,
            teacher_id=teacher_id,
            course_id=course_id,
            active=active,
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
            media_type=None,
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
