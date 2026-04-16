from __future__ import annotations

import asyncio
import logging
import os
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from collections.abc import Awaitable, Callable
from typing import Any

import httpx

from ..config import settings
from ..observability import log_buffer
from ..repositories import media_assets as media_assets_repo
from ..services import storage_service

logger = logging.getLogger(__name__)


class SourceNotReadyError(RuntimeError):
    """Raised when the source object is not yet available."""


_worker_task: asyncio.Task[None] | None = None
_logged_missing_source_assets: set[str] = set()
_verification_mode: bool = False
_worker_run_started_at: float | None = None


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _enabled() -> bool:
    return settings.mcp_workers_enabled


def _env_worker_enabled() -> bool:
    return os.environ.get("RUN_MEDIA_WORKER", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "y",
        "on",
    }


def _enablement_state() -> dict[str, bool]:
    enabled_by_mcp_mode = _enabled()
    enabled_by_env = _env_worker_enabled()
    return {
        "enabled_by_mcp_mode": enabled_by_mcp_mode,
        "enabled_by_env": enabled_by_env,
        "enabled_by_config": enabled_by_mcp_mode,
        "final_state": enabled_by_mcp_mode or enabled_by_env,
    }


def _truncate(message: str, limit: int = 500) -> str:
    if len(message) <= limit:
        return message
    return message[: limit - 3] + "..."


def _derive_audio_output_path(source_path: str, ext: str) -> str:
    normalized = source_path.lstrip("/")
    prefix = "media/source/audio/"
    if normalized.startswith(prefix):
        normalized = "media/derived/audio/" + normalized[len(prefix) :]
    else:
        normalized = "media/derived/audio/" + normalized
    return Path(normalized).with_suffix(f".{ext}").as_posix()


def _derive_cover_output_path(source_path: str, ext: str) -> str:
    normalized = source_path.lstrip("/")
    prefix = "media/source/cover/"
    if normalized.startswith(prefix):
        normalized = "media/derived/cover/" + normalized[len(prefix) :]
    else:
        normalized = "media/derived/cover/" + normalized
    return Path(normalized).with_suffix(f".{ext}").as_posix()


def _derive_profile_media_output_path(source_path: str, ext: str) -> str:
    normalized = source_path.lstrip("/")
    for source_prefix, derived_prefix in (
        ("media/source/profile-avatar/", "media/derived/profile-avatar/"),
        ("media/source/profile-media/", "media/derived/profile-media/"),
        ("media/source/profile/", "media/derived/profile/"),
    ):
        if normalized.startswith(source_prefix):
            normalized = derived_prefix + normalized[len(source_prefix) :]
            break
    else:
        normalized = "media/derived/profile-media/" + normalized
    return Path(normalized).with_suffix(f".{ext}").as_posix()


def _audio_source_suffix(asset: dict) -> str:
    for raw in (
        asset.get("original_filename"),
        asset.get("original_object_path"),
    ):
        suffix = Path(str(raw or "")).suffix.lower()
        if suffix:
            return suffix
    ingest_format = str(asset.get("ingest_format") or "").strip().lower()
    if ingest_format:
        return f".{ingest_format}"
    return ".wav"


def _normalized_media_kind(asset: dict) -> str | None:
    media_type = str(asset.get("media_type") or "").strip().lower()
    if media_type in {"audio", "video", "image", "document"}:
        return media_type
    return None


def _media_kind_requires_preview(kind: str) -> bool:
    return kind in {"image", "video"}


async def _storage_object_exists(
    *,
    storage: storage_service.StorageService,
    object_path: str,
) -> bool:
    normalized_path = str(object_path or "").strip().lstrip("/")
    if not normalized_path:
        return False
    try:
        await storage.get_presigned_url(
            normalized_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError:
        return False
    return True


async def _verify_ready_contract(
    *,
    asset: dict,
    playback_storage: storage_service.StorageService,
    playback_object_path: str,
    playback_content_type: str | None,
    duration_seconds: int | None,
    preview_storage: storage_service.StorageService | None = None,
    preview_object_path: str | None = None,
) -> None:
    kind = _normalized_media_kind(asset)
    if kind is None:
        raise RuntimeError("Ready verification failed: kind metadata is missing")

    if not str(playback_content_type or "").strip():
        raise RuntimeError(
            "Ready verification failed: content_type metadata is missing"
        )

    if kind in {"audio", "video"} and duration_seconds is None:
        raise RuntimeError("Ready verification failed: duration metadata is missing")

    if not await _storage_object_exists(
        storage=playback_storage,
        object_path=playback_object_path,
    ):
        raise RuntimeError("Ready verification failed: playback object is missing")

    resolved_preview_storage = preview_storage or playback_storage
    resolved_preview_path = preview_object_path or playback_object_path
    if _media_kind_requires_preview(kind):
        if not await _storage_object_exists(
            storage=resolved_preview_storage,
            object_path=resolved_preview_path,
        ):
            raise RuntimeError("Ready verification failed: preview object is missing")


async def _verification_idle_loop() -> None:
    while True:
        try:
            await asyncio.sleep(3600)
        except asyncio.CancelledError:
            break


async def start_worker(*, verification_mode: bool = False) -> None:
    global _worker_task, _verification_mode, _worker_run_started_at
    enablement = _enablement_state()
    if not enablement["final_state"]:
        logger.info("Media transcode worker disabled", extra=enablement)
        return
    if _worker_task is not None:
        return
    _verification_mode = verification_mode
    _worker_run_started_at = time.time()
    if verification_mode:
        _worker_task = asyncio.create_task(_verification_idle_loop())
        logger.info(
            "Media transcode worker started in no-write verification mode",
            extra={**enablement, "verification_mode": True, "write_suppressed": True},
        )
        return
    queue_contract_supported = (
        await media_assets_repo.media_processing_queue_supported()
    )
    if not queue_contract_supported:
        logger.info(
            "Media transcode worker unavailable for current local baseline",
            extra={**enablement, "queue_contract_supported": False},
        )
        return
    released = await media_assets_repo.release_processing_media_assets(
        stale_after_seconds=settings.media_transcode_stale_lock_seconds
    )
    if released:
        logger.info("Released %s stale media transcode locks", released)
    _worker_task = asyncio.create_task(_poll_loop())
    logger.info("Media transcode worker started", extra=enablement)


async def stop_worker() -> None:
    global _worker_task, _verification_mode, _worker_run_started_at
    if _worker_task is None:
        return
    _worker_task.cancel()
    try:
        await _worker_task
    except asyncio.CancelledError:
        pass
    _worker_task = None
    _verification_mode = False
    _worker_run_started_at = None
    logger.info("Media transcode worker stopped")


async def get_metrics() -> dict[str, Any]:
    enablement = _enablement_state()
    queue_contract_supported = (
        await media_assets_repo.media_processing_queue_supported()
    )
    summary = await media_assets_repo.get_media_processing_worker_summary(
        stale_after_seconds=settings.media_transcode_stale_lock_seconds
    )
    if _worker_run_started_at is None:
        last_error = None
    else:
        last_error = next(
            iter(
                log_buffer.list_events(
                    limit=1,
                    min_level="ERROR",
                    logger_names={__name__},
                    since_epoch_seconds=_worker_run_started_at,
                )
            ),
            None,
        )
    return {
        "worker_running": _worker_task is not None and not _worker_task.done(),
        **(
            enablement
            | {
                "final_state": bool(
                    enablement["final_state"]
                    if _verification_mode
                    else enablement["final_state"] and queue_contract_supported
                )
            }
        ),
        "queue_contract_supported": queue_contract_supported,
        "poll_interval_seconds": settings.media_transcode_poll_interval_seconds,
        "batch_size": settings.media_transcode_batch_size,
        "max_attempts": settings.media_transcode_max_attempts,
        "queue_summary": summary,
        "last_error": last_error,
        "verification_mode": _verification_mode,
        "write_suppressed": _verification_mode,
    }


async def _poll_loop() -> None:
    while True:
        try:
            await _log_skipped_missing_source_assets()
            batch = await media_assets_repo.fetch_and_lock_pending_media_assets(
                limit=settings.media_transcode_batch_size,
                max_attempts=settings.media_transcode_max_attempts,
            )
            if not batch:
                await asyncio.sleep(settings.media_transcode_poll_interval_seconds)
                continue
            for index, asset in enumerate(batch):
                try:
                    await _process_asset(asset)
                except asyncio.CancelledError:
                    _uncancel_current_task()
                    await _reschedule_cancelled_assets(batch[index:])
                    raise
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.exception("Media transcode poller error: %s", exc)
            await asyncio.sleep(settings.media_transcode_poll_interval_seconds)


async def _log_skipped_missing_source_assets() -> None:
    missing_assets = await media_assets_repo.list_pending_media_assets_missing_source(
        limit=settings.media_transcode_batch_size,
        max_attempts=settings.media_transcode_max_attempts,
    )
    for asset in missing_assets:
        media_id = str(asset.get("id") or "").strip()
        if not media_id or media_id in _logged_missing_source_assets:
            continue
        _logged_missing_source_assets.add(media_id)
        logger.warning(
            "Media transcode skipped asset because source object is missing "
            "media_id=%s purpose=%s media_type=%s bucket=%s path=%s state=%s attempts=%s",
            media_id,
            str(asset.get("purpose") or "").strip() or "<missing>",
            str(asset.get("media_type") or "").strip() or "<missing>",
            str(asset.get("storage_bucket") or "").strip() or "<missing>",
            str(asset.get("original_object_path") or "").strip() or "<missing>",
            str(asset.get("state") or "").strip() or "<missing>",
            int(asset.get("processing_attempts") or 0),
        )


def _uncancel_current_task() -> None:
    task = asyncio.current_task()
    if task is None:
        return
    uncancel = getattr(task, "uncancel", None)
    if callable(uncancel):
        uncancel()


async def _reschedule_cancelled_assets(batch: list[dict]) -> None:
    for asset in batch:
        media_id = asset.get("id")
        if not media_id:
            continue
        try:
            await media_assets_repo.defer_media_asset_processing(media_id=str(media_id))
        except Exception as exc:  # pragma: no cover - best-effort cleanup
            logger.warning(
                "Failed to reschedule cancelled media asset %s: %s",
                media_id,
                exc,
            )


async def _process_asset(asset: dict) -> None:
    media_id = str(asset.get("id"))
    attempts = int(asset.get("processing_attempts") or 0)
    if attempts >= settings.media_transcode_max_attempts:
        await media_assets_repo.mark_media_asset_failed(
            media_id=media_id,
            error_message="Max transcode attempts reached",
        )
        return

    attempt_consumed = False

    async def _consume_attempt() -> None:
        nonlocal attempt_consumed, attempts
        if attempt_consumed:
            return
        await media_assets_repo.increment_processing_attempts(media_id=media_id)
        attempt_consumed = True
        attempts += 1

    try:
        await _transcode_asset(asset, _consume_attempt)
    except SourceNotReadyError as exc:
        # Context7 invariant: source_object_must_exist_before_processing
        # Missing source objects are a wait condition (no retries consumed, no failure).
        # Guardrail: never sleep/retry in-process; always reschedule via next_retry_at.
        # TODO: consider a dedicated source-not-ready delay setting.
        delay_seconds = max(1, int(settings.media_transcode_poll_interval_seconds))
        await media_assets_repo.defer_media_asset_processing(
            media_id=media_id,
            next_retry_at=_now() + timedelta(seconds=delay_seconds),
        )
        logger.debug(
            "Source not ready for %s; deferring processing (%s)", media_id, exc
        )
    except Exception as exc:  # pragma: no cover - logged and recorded
        if not attempt_consumed:
            await _consume_attempt()
        delay = media_assets_repo.compute_backoff(
            attempts,
            max_seconds=settings.media_transcode_max_retry_seconds,
        )
        next_retry = _now() + delay
        await media_assets_repo.mark_media_asset_failed(
            media_id=media_id,
            error_message=_truncate(str(exc)),
            next_retry_at=next_retry,
        )
        logger.exception("Media transcode failed for %s: %s", media_id, exc)


ConsumeAttemptFn = Callable[[], Awaitable[None]]


async def _transcode_asset(asset: dict, consume_attempt: ConsumeAttemptFn) -> None:
    media_type = (asset.get("media_type") or "").lower()
    purpose = (asset.get("purpose") or "").lower()
    if media_type == "audio":
        await _transcode_audio_asset(asset, consume_attempt)
        return
    if media_type == "image" and purpose == "course_cover":
        await _transcode_cover_asset(asset, consume_attempt)
        return
    if media_type == "image" and purpose == "profile_media":
        await _transcode_profile_media_image_asset(asset, consume_attempt)
        return
    raise RuntimeError(f"Unsupported media asset type: {media_type}/{purpose}")


async def _transcode_audio_asset(
    asset: dict, consume_attempt: ConsumeAttemptFn
) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    source_bucket = asset.get(
        "storage_bucket"
    ) or storage_service.canonical_source_bucket_for_media_asset(asset)
    source_storage = storage_service.get_storage_service(source_bucket)
    try:
        signed = await source_storage.get_presigned_url(
            source_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError as exc:
        raise SourceNotReadyError(str(exc)) from exc
    output_path = _derive_audio_output_path(source_path, "mp3")

    with tempfile.TemporaryDirectory(prefix="aveli_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / f"source{_audio_source_suffix(asset)}"
        output_file = temp_root / "output.mp3"

        await _download_to_file(signed.url, input_file)
        await consume_attempt()
        await _run_ffmpeg_audio(input_file, output_file)
        duration = await _probe_duration(output_file)

        upload = await source_storage.create_upload_url(
            output_path,
            content_type="audio/mpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await _upload_file(upload.url, output_file, upload.headers)

    await _verify_ready_contract(
        asset=asset,
        playback_storage=source_storage,
        playback_object_path=output_path,
        playback_content_type="audio/mpeg",
        duration_seconds=duration,
    )

    updated = await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=str(asset["id"]),
        playback_object_path=output_path,
        playback_format="mp3",
        duration_seconds=duration,
        codec="mp3",
        playback_storage_bucket=source_storage.bucket,
    )
    if not updated:
        try:
            await source_storage.delete_object(output_path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Failed to cleanup derived audio after missing media asset %s (%s): %s",
                asset.get("id"),
                output_path,
                exc,
            )
        logger.info(
            "Media asset missing after audio transcode; cleaned up derived output media_id=%s output=%s",
            asset.get("id"),
            output_path,
        )
        return
    logger.info("Media transcode ready media_id=%s output=%s", asset["id"], output_path)


async def _transcode_cover_asset(
    asset: dict, consume_attempt: ConsumeAttemptFn
) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    source_bucket = asset.get(
        "storage_bucket"
    ) or storage_service.canonical_source_bucket_for_media_asset(asset)
    source_storage = storage_service.get_storage_service(source_bucket)
    try:
        signed = await source_storage.get_presigned_url(
            source_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError as exc:
        raise SourceNotReadyError(str(exc)) from exc
    output_path = _derive_cover_output_path(source_path, "jpg")

    with tempfile.TemporaryDirectory(prefix="aveli_cover_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "cover_source"
        output_file = temp_root / "cover.jpg"

        await _download_to_file(signed.url, input_file)
        await consume_attempt()
        await _run_ffmpeg_cover(input_file, output_file)

        public_storage = storage_service.get_storage_service(
            settings.media_public_bucket
        )
        upload = await public_storage.create_upload_url(
            output_path,
            content_type="image/jpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await _upload_file(upload.url, output_file, upload.headers)
    await _verify_ready_contract(
        asset=asset,
        playback_storage=public_storage,
        playback_object_path=output_path,
        playback_content_type="image/jpeg",
        duration_seconds=None,
        preview_storage=public_storage,
        preview_object_path=output_path,
    )

    result = await media_assets_repo.mark_course_cover_ready_from_worker(
        media_id=str(asset["id"]),
        playback_object_path=output_path,
        playback_storage_bucket=public_storage.bucket,
        playback_format="jpg",
        codec="jpeg",
    )
    if not result.get("updated"):
        try:
            await public_storage.delete_object(output_path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Failed to cleanup derived cover after missing media asset %s (%s): %s",
                asset.get("id"),
                output_path,
                exc,
            )
        logger.info(
            "Media asset missing after cover transcode; cleaned up derived output media_id=%s output=%s",
            asset.get("id"),
            output_path,
        )
        return

    logger.info(
        "Course cover ready media_id=%s output=%s",
        asset["id"],
        output_path,
    )


async def _transcode_profile_media_image_asset(
    asset: dict, consume_attempt: ConsumeAttemptFn
) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    source_bucket = asset.get(
        "storage_bucket"
    ) or storage_service.canonical_source_bucket_for_media_asset(asset)
    source_storage = storage_service.get_storage_service(source_bucket)
    try:
        signed = await source_storage.get_presigned_url(
            source_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError as exc:
        raise SourceNotReadyError(str(exc)) from exc
    output_path = _derive_profile_media_output_path(source_path, "jpg")

    with tempfile.TemporaryDirectory(prefix="aveli_profile_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "profile_media_source"
        output_file = temp_root / "profile_media.jpg"

        await _download_to_file(signed.url, input_file)
        await consume_attempt()
        await _run_ffmpeg_cover(input_file, output_file)

        public_storage = storage_service.get_storage_service(
            settings.media_public_bucket
        )
        upload = await public_storage.create_upload_url(
            output_path,
            content_type="image/jpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await _upload_file(upload.url, output_file, upload.headers)

    await _verify_ready_contract(
        asset=asset,
        playback_storage=public_storage,
        playback_object_path=output_path,
        playback_content_type="image/jpeg",
        duration_seconds=None,
        preview_storage=public_storage,
        preview_object_path=output_path,
    )

    updated = await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=str(asset["id"]),
        playback_object_path=output_path,
        playback_storage_bucket=public_storage.bucket,
        playback_format="jpg",
        codec="jpeg",
    )
    if not updated:
        try:
            await public_storage.delete_object(output_path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Failed to cleanup derived profile media after missing media asset %s (%s): %s",
                asset.get("id"),
                output_path,
                exc,
            )
        logger.info(
            "Media asset missing after profile media transcode; cleaned up derived output media_id=%s output=%s",
            asset.get("id"),
            output_path,
        )
        return

    logger.info(
        "Profile media image ready media_id=%s output=%s",
        asset["id"],
        output_path,
    )


async def _download_to_file(url: str, destination: Path) -> None:
    timeout = httpx.Timeout(10.0, read=None)
    async with httpx.AsyncClient(timeout=timeout) as client:
        async with client.stream("GET", url) as response:
            if response.status_code == 404:
                raise SourceNotReadyError("Source object not yet available")
            response.raise_for_status()
            with destination.open("wb") as handle:
                async for chunk in response.aiter_bytes(chunk_size=1024 * 1024):
                    handle.write(chunk)


async def _upload_file(url: str, source: Path, headers: dict[str, str] | None) -> None:
    timeout = httpx.Timeout(10.0, read=None)
    upload_headers = dict(headers or {})

    async def _file_stream(path: Path, chunk_size: int = 1024 * 1024):
        with path.open("rb") as handle:
            while True:
                chunk = await asyncio.to_thread(handle.read, chunk_size)
                if not chunk:
                    break
                yield chunk

    async with httpx.AsyncClient(timeout=timeout) as client:
        response = await client.put(
            url, headers=upload_headers, content=_file_stream(source)
        )
    if response.status_code >= 400:
        raise RuntimeError(f"Upload failed with status {response.status_code}")


async def _run_ffmpeg_audio(input_path: Path, output_path: Path) -> None:
    logger.info("Running ffmpeg audio input=%s output=%s", input_path, output_path)
    command = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-y",
        "-i",
        str(input_path),
        "-map_metadata",
        "-1",
        "-vn",
        "-c:a",
        "libmp3lame",
        "-b:a",
        "192k",
        str(output_path),
    ]
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        error = stderr.decode("utf-8", errors="ignore") or stdout.decode(
            "utf-8", errors="ignore"
        )
        raise RuntimeError(_truncate(error or "ffmpeg failed"))


async def _run_ffmpeg_cover(input_path: Path, output_path: Path) -> None:
    command = [
        "ffmpeg",
        "-hide_banner",
        "-nostdin",
        "-y",
        "-i",
        str(input_path),
        "-map_metadata",
        "-1",
        "-vf",
        "scale='min(1920,iw)':-2",
        "-q:v",
        "3",
        str(output_path),
    ]
    process = await asyncio.create_subprocess_exec(
        *command,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        error = stderr.decode("utf-8", errors="ignore") or stdout.decode(
            "utf-8", errors="ignore"
        )
        raise RuntimeError(_truncate(error or "ffmpeg failed"))


async def _probe_duration(path: Path) -> int | None:
    command = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "format=duration",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(path),
    ]
    try:
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError:
        return None
    stdout, _ = await process.communicate()
    if process.returncode != 0:
        return None
    raw = stdout.decode("utf-8", errors="ignore").strip()
    if not raw:
        return None
    try:
        return int(float(raw))
    except ValueError:
        return None


async def _run_worker_forever() -> None:
    from ..db import pool

    await pool.open(wait=True)
    try:
        await start_worker()
        while True:
            await asyncio.sleep(3600)
    finally:
        await stop_worker()
        await pool.close()


if __name__ == "__main__":
    from ..logging_utils import setup_logging

    setup_logging()
    enablement = _enablement_state()
    if not enablement["final_state"]:
        logger.info("Media transcode worker disabled", extra=enablement)
        raise SystemExit(0)
    try:
        asyncio.run(_run_worker_forever())
    except KeyboardInterrupt:
        logger.info("Media transcode worker stopped")
