from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import logging
from typing import Any

from ...config import settings
from ...db import get_conn

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
    runtime_media_id: str = ""
    course_id: str | None = None
    duration_seconds: int | None = None

    def log_fields(self) -> dict[str, Any]:
        return {
            "runtime_media_id": self.runtime_media_id,
            "lesson_media_id": self.lesson_media_id,
            "course_id": self.course_id,
            "lesson_id": self.lesson_id,
            "media_asset_id": self.media_asset_id,
            "media_type": self.media_type,
            "content_type": self.content_type,
            "media_state": self.media_state,
            "duration_seconds": self.duration_seconds,
            "storage_bucket": self.storage_bucket,
            "storage_path": self.storage_path,
            "is_playable": self.is_playable,
            "playback_mode": self.playback_mode.value,
            "failure_reason": self.failure_reason.value,
            "failure_detail": self.failure_detail,
        }


LessonMediaResolution = RuntimeMediaResolution


def _exact_text(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        return value or None
    return str(value)


def _derived_content_type(
    *,
    media_type: str | None,
    playback_format: str | None,
    ingest_format: str | None,
) -> str | None:
    exact_media_type = _exact_text(media_type)
    format_hint = (
        _exact_text(playback_format) or _exact_text(ingest_format) or ""
    ).strip().lower()
    if exact_media_type == "audio" and format_hint == "mp3":
        return "audio/mpeg"
    if exact_media_type == "image":
        if format_hint in {"jpg", "jpeg"}:
            return "image/jpeg"
        if format_hint == "png":
            return "image/png"
    if exact_media_type == "video" and format_hint == "mp4":
        return "video/mp4"
    if exact_media_type == "document" and format_hint == "pdf":
        return "application/pdf"
    return None


class MediaResolverService:
    async def lookup_runtime_media_id_for_lesson_media(self, lesson_media_id: str) -> str | None:
        exact_lesson_media_id = _exact_text(lesson_media_id)
        if exact_lesson_media_id is None:
            return None

        async with get_conn() as cur:
            await cur.execute(
                """
                select lesson_media_id
                from app.runtime_media
                where lesson_media_id = %s::uuid
                limit 1
                """,
                (exact_lesson_media_id,),
            )
            row = await cur.fetchone()
        if not row:
            return None
        return str(row["lesson_media_id"])

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

        runtime_media_id = await self.lookup_runtime_media_id_for_lesson_media(
            exact_lesson_media_id
        )
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
                select
                  rm.lesson_media_id as runtime_media_id,
                  rm.lesson_media_id,
                  rm.course_id,
                  rm.lesson_id,
                  rm.media_asset_id,
                  ma.media_type::text as media_type,
                  ma.state::text as media_state,
                  ma.original_object_path,
                  ma.ingest_format,
                  ma.playback_format,
                  %s::text as storage_bucket
                from app.runtime_media as rm
                join app.media_assets as ma
                  on ma.id = rm.media_asset_id
                where rm.lesson_media_id = %s::uuid
                limit 1
                """,
                (settings.media_source_bucket, runtime_media_id),
            )
            return await cur.fetchone()

    async def _resolve_row(self, row: dict[str, Any]) -> RuntimeMediaResolution:
        runtime_media_id = str(row["runtime_media_id"])
        lesson_media_id = _exact_text(row.get("lesson_media_id"))
        lesson_id = _exact_text(row.get("lesson_id"))
        course_id = _exact_text(row.get("course_id"))
        media_asset_id = _exact_text(row.get("media_asset_id"))
        media_type = _exact_text(row.get("media_type"))
        media_state = _exact_text(row.get("media_state"))
        storage_bucket = _exact_text(row.get("storage_bucket"))
        storage_path = _exact_text(row.get("original_object_path"))
        playback_format = _exact_text(row.get("playback_format"))
        ingest_format = _exact_text(row.get("ingest_format"))
        content_type = _derived_content_type(
            media_type=media_type,
            playback_format=playback_format,
            ingest_format=ingest_format,
        )

        if media_type is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=None,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.INVALID_KIND,
                failure_detail="media_asset media_type is missing",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        if media_asset_id is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=None,
                media_type=media_type,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_ASSET_LINK,
                failure_detail="runtime_media row has no media_asset link",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        if media_state != "ready":
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=media_type,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.ASSET_NOT_READY,
                failure_detail=f"media_asset state is {media_state or 'unknown'}",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        if storage_bucket is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=media_type,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=None,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_STORAGE_IDENTITY,
                failure_detail="media_source bucket is missing",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        if storage_path is None:
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=media_type,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=storage_bucket,
                storage_path=None,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.MISSING_STORAGE_OBJECT,
                failure_detail="media_asset original_object_path is missing",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        if media_type == "audio" and playback_format != "mp3":
            return RuntimeMediaResolution(
                lesson_media_id=lesson_media_id,
                lesson_id=lesson_id,
                media_asset_id=media_asset_id,
                media_type=media_type,
                content_type=content_type,
                media_state=media_state,
                storage_bucket=storage_bucket,
                storage_path=storage_path,
                is_playable=False,
                playback_mode=RuntimeMediaPlaybackMode.NONE,
                failure_reason=RuntimeMediaResolutionReason.UNSUPPORTED_MEDIA_CONTRACT,
                failure_detail="audio ready assets require playback_format = mp3",
                runtime_media_id=runtime_media_id,
                course_id=course_id,
            )

        return RuntimeMediaResolution(
            lesson_media_id=lesson_media_id,
            lesson_id=lesson_id,
            media_asset_id=media_asset_id,
            media_type=media_type,
            content_type=content_type,
            media_state=media_state,
            storage_bucket=storage_bucket,
            storage_path=storage_path,
            is_playable=True,
            playback_mode=RuntimeMediaPlaybackMode.PIPELINE_ASSET,
            failure_reason=RuntimeMediaResolutionReason.OK_READY_ASSET,
            runtime_media_id=runtime_media_id,
            course_id=course_id,
        )

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
