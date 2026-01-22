from __future__ import annotations

import asyncio
import logging
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

from ..config import settings
from ..repositories import media_assets as media_assets_repo
from ..services import storage_service

logger = logging.getLogger(__name__)


class SourceNotReadyError(RuntimeError):
    """Raised when the source object is not yet available."""


_worker_task: asyncio.Task[None] | None = None


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _enabled() -> bool:
    return settings.media_transcode_enabled


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


async def start_worker() -> None:
    global _worker_task
    if not _enabled():
        logger.info("Media transcode worker disabled by configuration")
        return
    if _worker_task is not None:
        return
    released = await media_assets_repo.release_processing_media_assets(
        stale_after_seconds=settings.media_transcode_stale_lock_seconds
    )
    if released:
        logger.info("Released %s stale media transcode locks", released)
    _worker_task = asyncio.create_task(_poll_loop())
    logger.info("Media transcode worker started")


async def stop_worker() -> None:
    global _worker_task
    if _worker_task is None:
        return
    _worker_task.cancel()
    try:
        await _worker_task
    except asyncio.CancelledError:
        pass
    _worker_task = None
    logger.info("Media transcode worker stopped")


async def _poll_loop() -> None:
    while True:
        try:
            batch = await media_assets_repo.fetch_and_lock_pending_media_assets(
                limit=settings.media_transcode_batch_size
            )
            if not batch:
                await asyncio.sleep(settings.media_transcode_poll_interval_seconds)
                continue
            for asset in batch:
                await _process_asset(asset)
        except asyncio.CancelledError:
            break
        except Exception as exc:  # pragma: no cover - defensive logging
            logger.exception("Media transcode poller error: %s", exc)
            await asyncio.sleep(settings.media_transcode_poll_interval_seconds)


async def _process_asset(asset: dict) -> None:
    media_id = str(asset.get("id"))
    attempts = int(asset.get("processing_attempts") or 0)
    if attempts > settings.media_transcode_max_attempts:
        await media_assets_repo.mark_media_asset_failed(
            media_id=media_id,
            error_message="Max transcode attempts reached",
        )
        return

    try:
        await _transcode_asset(asset)
    except SourceNotReadyError as exc:
        next_retry = _now() + timedelta(seconds=15)
        await media_assets_repo.reschedule_media_asset(
            media_id=media_id,
            next_retry_at=next_retry,
        )
        logger.info("Source not ready for %s; retrying at %s", media_id, next_retry)
    except Exception as exc:  # pragma: no cover - logged and recorded
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


async def _transcode_asset(asset: dict) -> None:
    media_type = (asset.get("media_type") or "").lower()
    purpose = (asset.get("purpose") or "").lower()
    if media_type == "audio":
        await _transcode_audio_asset(asset)
        return
    if media_type == "image" and purpose == "course_cover":
        await _transcode_cover_asset(asset)
        return
    raise RuntimeError(f"Unsupported media asset type: {media_type}/{purpose}")


async def _transcode_audio_asset(asset: dict) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    source_bucket = asset.get("storage_bucket") or settings.media_source_bucket
    source_storage = storage_service.get_storage_service(source_bucket)
    signed = await source_storage.get_presigned_url(
        source_path,
        ttl=settings.media_playback_url_ttl_seconds,
        download=False,
    )
    output_path = _derive_audio_output_path(source_path, "mp3")

    with tempfile.TemporaryDirectory(prefix="aveli_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "source.wav"
        output_file = temp_root / "output.mp3"

        await _download_to_file(signed.url, input_file)
        await _run_ffmpeg_audio(input_file, output_file)
        duration = await _probe_duration(output_file)

        upload = await source_storage.create_upload_url(
            output_path,
            content_type="audio/mpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await _upload_file(upload.url, output_file, upload.headers)

    await media_assets_repo.mark_media_asset_ready(
        media_id=str(asset["id"]),
        streaming_object_path=output_path,
        streaming_format="mp3",
        duration_seconds=duration,
        codec="mp3",
        streaming_storage_bucket=source_storage.bucket,
    )
    logger.info("Media transcode ready media_id=%s output=%s", asset["id"], output_path)


async def _transcode_cover_asset(asset: dict) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    source_bucket = asset.get("storage_bucket") or settings.media_source_bucket
    source_storage = storage_service.get_storage_service(source_bucket)
    signed = await source_storage.get_presigned_url(
        source_path,
        ttl=settings.media_playback_url_ttl_seconds,
        download=False,
    )
    output_path = _derive_cover_output_path(source_path, "jpg")

    with tempfile.TemporaryDirectory(prefix="aveli_cover_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "cover_source"
        output_file = temp_root / "cover.jpg"

        await _download_to_file(signed.url, input_file)
        await _run_ffmpeg_cover(input_file, output_file)

        public_storage = storage_service.get_storage_service(settings.media_public_bucket)
        upload = await public_storage.create_upload_url(
            output_path,
            content_type="image/jpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
        await _upload_file(upload.url, output_file, upload.headers)
        public_url = public_storage.public_url(output_path)

    applied = await media_assets_repo.mark_course_cover_ready(
        media_id=str(asset["id"]),
        streaming_object_path=output_path,
        streaming_storage_bucket=public_storage.bucket,
        streaming_format="jpg",
        public_url=public_url,
        codec="jpeg",
    )
    logger.info(
        "Course cover ready media_id=%s output=%s applied=%s",
        asset["id"],
        output_path,
        applied,
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
    async with httpx.AsyncClient(timeout=timeout) as client:
        with source.open("rb") as handle:
            response = await client.put(url, headers=upload_headers, content=handle)
    if response.status_code >= 400:
        raise RuntimeError(f"Upload failed with status {response.status_code}")


async def _run_ffmpeg_audio(input_path: Path, output_path: Path) -> None:
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
