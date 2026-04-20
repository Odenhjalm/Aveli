from __future__ import annotations

import asyncio
import hashlib
import logging
import os
import re
import shutil
import subprocess
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
_REPO_ROOT = Path(__file__).resolve().parents[3]
_DEFAULT_LOCAL_SOURCE_ROOT = (
    _REPO_ROOT / "canonical_projection_export_v2_clean" / "media"
)


class SourceNotReadyError(RuntimeError):
    """Raised when the source object is not yet available."""


_worker_task: asyncio.Task[None] | None = None
_logged_missing_source_assets: set[str] = set()
_verification_mode: bool = False
_worker_run_started_at: float | None = None
_DOWNLOAD_CHUNK_TIMEOUT_SECONDS = 5.0
_FFMPEG_TIMEOUT_SECONDS = 180.0
_FFPROBE_TIMEOUT_SECONDS = 30.0
_READ_CHUNK_SIZE = 1024 * 1024
_DURATION_RE = re.compile(
    r"Duration:\s*(?P<hours>\d+):(?P<minutes>\d+):(?P<seconds>\d+(?:\.\d+)?)"
)


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


def _configured_local_source_root() -> Path | None:
    raw = os.environ.get("MEDIA_LOCAL_SOURCE_ROOT")
    if raw:
        root = Path(raw).expanduser().resolve(strict=False)
        return root if root.is_dir() else None
    if (
        str(settings.mcp_mode).strip().lower() == "local"
        and _DEFAULT_LOCAL_SOURCE_ROOT.is_dir()
    ):
        return _DEFAULT_LOCAL_SOURCE_ROOT
    return None


def _hash_file(path: Path) -> tuple[int, str]:
    hasher = hashlib.sha256()
    size = 0
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(_READ_CHUNK_SIZE)
            if not chunk:
                break
            size += len(chunk)
            hasher.update(chunk)
    return size, hasher.hexdigest()


def _resolve_local_projection_source_file(asset: dict) -> Path | None:
    root = _configured_local_source_root()
    if root is None:
        return None

    media_id = str(asset.get("id") or "").strip()
    ingest_format = str(asset.get("ingest_format") or "").strip().lower().lstrip(".")
    if not media_id or not ingest_format:
        return None

    candidate = (root / f"{media_id}.{ingest_format}").resolve(strict=False)
    try:
        common = os.path.commonpath(
            [
                os.path.normcase(str(root)),
                os.path.normcase(str(candidate)),
            ]
        )
    except ValueError:
        return None
    if common != os.path.normcase(str(root)) or not candidate.is_file():
        return None

    expected_size = asset.get("file_size")
    expected_hash = str(asset.get("content_hash") or "").strip().lower()
    expected_algorithm = str(asset.get("content_hash_algorithm") or "").strip().lower()
    if expected_size is None and not expected_hash:
        logger.warning(
            "Local projection source found without DB identity fields media_id=%s path=%s",
            media_id,
            candidate,
        )
        return candidate

    actual_size, actual_hash = _hash_file(candidate)
    if expected_size is not None and actual_size != int(expected_size):
        raise storage_service.StorageServiceError(
            f"Local projection source size mismatch for media {media_id}"
        )
    if expected_hash:
        if expected_algorithm != "sha256":
            raise storage_service.StorageServiceError(
                f"Local projection source hash algorithm is not sha256 for media {media_id}"
            )
        if actual_hash != expected_hash:
            raise storage_service.StorageServiceError(
                f"Local projection source hash mismatch for media {media_id}"
            )
    return candidate


async def _copy_local_source_to_file(source: Path, destination: Path) -> None:
    logger.info(
        "Local source copy started source=%s destination=%s", source, destination
    )
    bytes_written = 0
    with source.open("rb") as source_handle, destination.open(
        "wb"
    ) as destination_handle:
        while True:
            chunk = await asyncio.to_thread(source_handle.read, _READ_CHUNK_SIZE)
            if not chunk:
                break
            bytes_written += len(chunk)
            await asyncio.to_thread(destination_handle.write, chunk)
            logger.info(
                "Local source copy chunk source=%s destination=%s bytes_received=%s total_bytes=%s",
                source,
                destination,
                len(chunk),
                bytes_written,
            )

    if not destination.exists() or destination.stat().st_size <= 0:
        raise storage_service.StorageServiceError(
            f"Local source copy produced no readable bytes: {destination}"
        )
    logger.info(
        "Local source copy completed source=%s destination=%s bytes=%s",
        source,
        destination,
        destination.stat().st_size,
    )


def _local_storage_enabled() -> bool:
    return str(settings.mcp_mode).strip().lower() == "local"


def _local_storage_object_path(bucket: str | None, object_path: str) -> Path:
    normalized_path = str(object_path or "").strip().lstrip("/\\")
    if not normalized_path:
        raise storage_service.StorageServiceError("Local storage object path is empty")

    normalized_bucket = str(bucket or "").strip().strip("/\\")
    root = Path(settings.media_root).expanduser().resolve(strict=False)
    candidate = (
        root / normalized_bucket / Path(normalized_path)
        if normalized_bucket
        else root / Path(normalized_path)
    ).resolve(strict=False)
    try:
        common = os.path.commonpath(
            [
                os.path.normcase(str(root)),
                os.path.normcase(str(candidate)),
            ]
        )
    except ValueError as exc:
        raise storage_service.StorageServiceError(
            "Local storage object path escapes media root"
        ) from exc
    if common != os.path.normcase(str(root)):
        raise storage_service.StorageServiceError(
            "Local storage object path escapes media root"
        )
    return candidate


def _local_storage_object_exists(bucket: str | None, object_path: str) -> bool:
    if not _local_storage_enabled():
        return False
    try:
        candidate = _local_storage_object_path(bucket, object_path)
    except storage_service.StorageServiceError:
        return False
    return candidate.is_file() and candidate.stat().st_size > 0


async def _write_local_storage_object(
    *,
    bucket: str | None,
    object_path: str,
    source: Path,
    upsert: bool,
) -> None:
    if not _local_storage_enabled():
        raise storage_service.StorageServiceError(
            "Local derived storage fallback is unavailable outside local mode"
        )
    if not source.is_file() or source.stat().st_size <= 0:
        raise storage_service.StorageServiceError(
            f"Local derived storage source is missing or empty: {source}"
        )

    target = _local_storage_object_path(bucket, object_path)
    source_size, source_hash = await asyncio.to_thread(_hash_file, source)
    if target.exists():
        target_size, target_hash = await asyncio.to_thread(_hash_file, target)
        if target_size == source_size and target_hash == source_hash:
            logger.info(
                "Local derived object already present bucket=%s path=%s file=%s bytes=%s",
                bucket,
                object_path,
                target,
                target_size,
            )
            return
        if not upsert:
            raise storage_service.StorageServiceError(
                f"Local derived object already exists with different bytes: {target}"
            )

    target.parent.mkdir(parents=True, exist_ok=True)
    temp_file: Path | None = None
    bytes_written = 0
    try:
        with tempfile.NamedTemporaryFile(
            "wb",
            dir=target.parent,
            prefix=f".{target.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            temp_file = Path(handle.name)
            with source.open("rb") as source_handle:
                while True:
                    chunk = await asyncio.to_thread(
                        source_handle.read, _READ_CHUNK_SIZE
                    )
                    if not chunk:
                        break
                    bytes_written += len(chunk)
                    await asyncio.to_thread(handle.write, chunk)
                    logger.info(
                        "Local derived object write chunk bucket=%s path=%s bytes_received=%s total_bytes=%s",
                        bucket,
                        object_path,
                        len(chunk),
                        bytes_written,
                    )
            await asyncio.to_thread(handle.flush)

        os.replace(temp_file, target)
        temp_file = None
    finally:
        if temp_file is not None and temp_file.exists():
            temp_file.unlink(missing_ok=True)

    if not target.is_file() or target.stat().st_size != source_size:
        raise storage_service.StorageServiceError(
            f"Local derived object write verification failed: {target}"
        )
    _, target_hash = await asyncio.to_thread(_hash_file, target)
    if target_hash != source_hash:
        raise storage_service.StorageServiceError(
            f"Local derived object hash verification failed: {target}"
        )
    logger.info(
        "Local derived object write completed bucket=%s path=%s file=%s bytes=%s",
        bucket,
        object_path,
        target,
        target.stat().st_size,
    )


async def _upload_derived_file(
    *,
    storage: storage_service.StorageService,
    object_path: str,
    source: Path,
    content_type: str,
    upsert: bool,
    cache_seconds: int | None,
) -> None:
    try:
        upload = await storage.create_upload_url(
            object_path,
            content_type=content_type,
            upsert=upsert,
            cache_seconds=cache_seconds,
        )
        await _upload_file(upload.url, source, upload.headers)
        return
    except storage_service.StorageServiceError as exc:
        if not _local_storage_enabled():
            raise
        logger.warning(
            "Supabase derived upload failed; writing local derived object bucket=%s path=%s source=%s error=%s",
            storage.bucket,
            object_path,
            source,
            exc,
        )
        await _write_local_storage_object(
            bucket=storage.bucket,
            object_path=object_path,
            source=source,
            upsert=upsert,
        )


async def _materialize_source_file(
    *,
    asset: dict,
    source_storage: storage_service.StorageService,
    source_path: str,
    destination: Path,
) -> None:
    local_source = _resolve_local_projection_source_file(asset)
    try:
        signed = await source_storage.get_presigned_url(
            source_path,
            ttl=settings.media_playback_url_ttl_seconds,
            download=False,
        )
    except storage_service.StorageObjectNotFoundError as exc:
        if local_source is None:
            raise SourceNotReadyError(str(exc)) from exc
        logger.warning(
            "Supabase source object missing; using verified local projection source media_id=%s path=%s",
            asset.get("id"),
            local_source,
        )
        await _copy_local_source_to_file(local_source, destination)
        return
    except storage_service.StorageServiceError as exc:
        if local_source is None:
            raise
        logger.warning(
            "Supabase source signing failed; using verified local projection source media_id=%s path=%s error=%s",
            asset.get("id"),
            local_source,
            exc,
        )
        await _copy_local_source_to_file(local_source, destination)
        return

    await _download_to_file(signed.url, destination)


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


def _derive_lesson_media_output_path(
    source_path: str, media_type: str, ext: str
) -> str:
    normalized = source_path.lstrip("/")
    normalized_media_type = str(media_type or "").strip().lower() or "media"
    derived = f"media/derived/lesson-media/{normalized_media_type}/{normalized}"
    return Path(derived).with_suffix(f".{ext}").as_posix()


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


def _normalized_content_type(value: str | None) -> str | None:
    content_type = str(value or "").strip().lower()
    if not content_type:
        return None
    return content_type.split(";", 1)[0].strip() or None


def _local_storage_object_metadata(
    bucket: str | None,
    object_path: str,
) -> storage_service.StorageObjectMetadata | None:
    if not _local_storage_enabled():
        return None
    try:
        candidate = _local_storage_object_path(bucket, object_path)
    except storage_service.StorageServiceError:
        return None
    if not candidate.is_file() or candidate.stat().st_size <= 0:
        return None
    suffix = candidate.suffix.lower()
    content_type = {
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".svg": "image/svg+xml",
        ".mp3": "audio/mpeg",
        ".mp4": "video/mp4",
        ".pdf": "application/pdf",
    }.get(suffix)
    return storage_service.StorageObjectMetadata(
        path=object_path,
        content_type=content_type,
        size_bytes=candidate.stat().st_size,
    )


async def _inspect_storage_object(
    *,
    storage: storage_service.StorageService,
    object_path: str,
) -> storage_service.StorageObjectMetadata | None:
    normalized_path = str(object_path or "").strip().lstrip("/")
    if not normalized_path:
        return None
    local_metadata = _local_storage_object_metadata(storage.bucket, normalized_path)
    if local_metadata is not None:
        return local_metadata
    inspect_object = getattr(storage, "inspect_object", None)
    if not callable(inspect_object):
        raise storage_service.StorageServiceError(
            "Storage object inspection is unavailable"
        )
    try:
        return await inspect_object(
            normalized_path,
            ttl=settings.media_playback_url_ttl_seconds,
        )
    except storage_service.StorageObjectNotFoundError:
        return None


async def _storage_object_exists(
    *,
    storage: storage_service.StorageService,
    object_path: str,
) -> bool:
    return (
        await _inspect_storage_object(storage=storage, object_path=object_path)
    ) is not None


async def _verify_storage_ready_object(
    *,
    storage: storage_service.StorageService,
    object_path: str,
    expected_content_type: str | None,
) -> None:
    metadata = await _inspect_storage_object(storage=storage, object_path=object_path)
    if metadata is None:
        raise RuntimeError("Ready verification failed: playback object is missing")
    if metadata.size_bytes is not None and metadata.size_bytes <= 0:
        raise RuntimeError("Ready verification failed: playback object is empty")
    expected = _normalized_content_type(expected_content_type)
    actual = _normalized_content_type(metadata.content_type)
    if expected is not None and actual != expected:
        raise RuntimeError("Ready verification failed: playback content_type mismatch")


async def _verify_ready_contract(
    *,
    asset: dict,
    playback_storage: storage_service.StorageService,
    playback_object_path: str,
    playback_format: str,
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

    if not str(playback_format or "").strip():
        raise RuntimeError("Ready verification failed: playback_format is missing")

    if kind in {"audio", "video"} and duration_seconds is None:
        raise RuntimeError("Ready verification failed: duration metadata is missing")

    await _verify_storage_ready_object(
        storage=playback_storage,
        object_path=playback_object_path,
        expected_content_type=playback_content_type,
    )

    resolved_preview_storage = preview_storage or playback_storage
    resolved_preview_path = preview_object_path or playback_object_path
    if _media_kind_requires_preview(kind):
        if (
            resolved_preview_storage.bucket != playback_storage.bucket
            or resolved_preview_path != playback_object_path
        ):
            await _verify_storage_ready_object(
                storage=resolved_preview_storage,
                object_path=resolved_preview_path,
                expected_content_type=playback_content_type,
            )
        elif not await _storage_object_exists(
            storage=resolved_preview_storage,
            object_path=resolved_preview_path,
        ):
            raise RuntimeError("Ready verification failed: preview object is missing")


def _lesson_passthrough_ready_contract(
    *,
    asset: dict,
    source_metadata: storage_service.StorageObjectMetadata,
) -> tuple[str, str, str]:
    media_type = str(asset.get("media_type") or "").strip().lower()
    content_type = _normalized_content_type(source_metadata.content_type)
    if content_type is None:
        raise RuntimeError("Source verification failed: content_type is missing")
    if source_metadata.size_bytes is not None and source_metadata.size_bytes <= 0:
        raise RuntimeError("Source verification failed: source object is empty")

    if media_type == "image":
        if content_type == "image/jpeg":
            return "jpg", "image/jpeg", "jpeg"
        if content_type == "image/png":
            return "png", "image/png", "png"
        raise RuntimeError("Unsupported lesson image passthrough format")

    if media_type == "video":
        if content_type != "video/mp4":
            raise RuntimeError("Unsupported lesson video passthrough format")
        return "mp4", "video/mp4", "mp4"

    if media_type == "document":
        if content_type != "application/pdf":
            raise RuntimeError("Unsupported lesson document passthrough format")
        return "pdf", "application/pdf", "pdf"

    raise RuntimeError(f"Unsupported lesson media passthrough type: {media_type}")


async def _copy_passthrough_source_to_output(source: Path, destination: Path) -> None:
    await asyncio.to_thread(shutil.copyfile, source, destination)
    if not destination.exists() or destination.stat().st_size <= 0:
        raise RuntimeError("Lesson media passthrough produced an empty output")


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
    if purpose == "lesson_media" and media_type in {"image", "video", "document"}:
        await _transcode_lesson_passthrough_asset(asset, consume_attempt)
        return
    raise RuntimeError(f"Unsupported media asset type: {media_type}/{purpose}")


async def _transcode_lesson_passthrough_asset(
    asset: dict, consume_attempt: ConsumeAttemptFn
) -> None:
    source_path = asset.get("original_object_path")
    if not source_path:
        raise RuntimeError("Missing source object path")

    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    if purpose != "lesson_media" or media_type not in {"image", "video", "document"}:
        raise RuntimeError(
            f"Unsupported lesson passthrough asset: {media_type}/{purpose}"
        )

    source_bucket = asset.get(
        "storage_bucket"
    ) or storage_service.canonical_upload_bucket_for_media_asset(asset)
    playback_bucket = storage_service.canonical_source_bucket_for_media_asset(asset)
    source_storage = storage_service.get_storage_service(source_bucket)
    playback_storage = storage_service.get_storage_service(playback_bucket)

    source_metadata = await _inspect_storage_object(
        storage=source_storage,
        object_path=str(source_path),
    )
    if source_metadata is None:
        raise SourceNotReadyError("Source object is missing")
    playback_format, playback_content_type, codec = _lesson_passthrough_ready_contract(
        asset=asset,
        source_metadata=source_metadata,
    )
    output_path = _derive_lesson_media_output_path(
        str(source_path),
        media_type,
        playback_format,
    )
    duration: int | None = None

    with tempfile.TemporaryDirectory(prefix="aveli_lesson_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / f"source.{playback_format}"
        output_file = temp_root / f"output.{playback_format}"

        await _materialize_source_file(
            asset=asset,
            source_storage=source_storage,
            source_path=str(source_path),
            destination=input_file,
        )
        await consume_attempt()
        await _copy_passthrough_source_to_output(input_file, output_file)
        if media_type == "video":
            duration = await _probe_duration(output_file)

        await _upload_derived_file(
            storage=playback_storage,
            object_path=output_path,
            source=output_file,
            content_type=playback_content_type,
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )

    await _verify_ready_contract(
        asset=asset,
        playback_storage=playback_storage,
        playback_object_path=output_path,
        playback_format=playback_format,
        playback_content_type=playback_content_type,
        duration_seconds=duration,
    )

    updated = await media_assets_repo.mark_media_asset_ready_from_worker(
        media_id=str(asset["id"]),
        playback_object_path=output_path,
        playback_format=playback_format,
        duration_seconds=duration,
        codec=codec,
        playback_storage_bucket=playback_storage.bucket,
    )
    if not updated:
        try:
            await playback_storage.delete_object(output_path)
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Failed to cleanup derived lesson media after missing media asset %s (%s): %s",
                asset.get("id"),
                output_path,
                exc,
            )
        logger.info(
            "Media asset missing after lesson media processing; cleaned up derived output media_id=%s output=%s",
            asset.get("id"),
            output_path,
        )
        return
    logger.info(
        "Lesson media ready media_id=%s media_type=%s output=%s",
        asset["id"],
        media_type,
        output_path,
    )


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
    output_path = _derive_audio_output_path(source_path, "mp3")

    with tempfile.TemporaryDirectory(prefix="aveli_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / f"source{_audio_source_suffix(asset)}"
        output_file = temp_root / "output.mp3"

        logger.info(
            "Audio source materialization starting media_id=%s", asset.get("id")
        )
        await _materialize_source_file(
            asset=asset,
            source_storage=source_storage,
            source_path=source_path,
            destination=input_file,
        )
        logger.info(
            "Audio source materialized media_id=%s path=%s bytes=%s",
            asset.get("id"),
            input_file,
            input_file.stat().st_size,
        )
        await consume_attempt()
        if _audio_source_suffix(asset) == ".mp3":
            logger.info(
                "Audio source already mp3; skipping transcode media_id=%s input=%s",
                asset.get("id"),
                input_file,
            )
            output_file = input_file
        else:
            logger.info(
                "Audio ffmpeg transcode starting media_id=%s input=%s output=%s",
                asset.get("id"),
                input_file,
                output_file,
            )
            await _run_ffmpeg_audio(input_file, output_file)
            logger.info(
                "Audio ffmpeg transcode completed media_id=%s output=%s bytes=%s",
                asset.get("id"),
                output_file,
                output_file.stat().st_size if output_file.exists() else 0,
            )
        duration = await _probe_duration(output_file)

        await _upload_derived_file(
            storage=source_storage,
            object_path=output_path,
            source=output_file,
            content_type="audio/mpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )

    await _verify_ready_contract(
        asset=asset,
        playback_storage=source_storage,
        playback_object_path=output_path,
        playback_format="mp3",
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
    output_path = _derive_cover_output_path(source_path, "jpg")

    with tempfile.TemporaryDirectory(prefix="aveli_cover_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "cover_source"
        output_file = temp_root / "cover.jpg"

        await _materialize_source_file(
            asset=asset,
            source_storage=source_storage,
            source_path=source_path,
            destination=input_file,
        )
        await consume_attempt()
        await _run_ffmpeg_cover(input_file, output_file)

        public_storage = storage_service.get_storage_service(
            settings.media_public_bucket
        )
        await _upload_derived_file(
            storage=public_storage,
            object_path=output_path,
            source=output_file,
            content_type="image/jpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )
    await _verify_ready_contract(
        asset=asset,
        playback_storage=public_storage,
        playback_object_path=output_path,
        playback_format="jpg",
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
    output_path = _derive_profile_media_output_path(source_path, "jpg")

    with tempfile.TemporaryDirectory(prefix="aveli_profile_media_") as temp_dir:
        temp_root = Path(temp_dir)
        input_file = temp_root / "profile_media_source"
        output_file = temp_root / "profile_media.jpg"

        await _materialize_source_file(
            asset=asset,
            source_storage=source_storage,
            source_path=source_path,
            destination=input_file,
        )
        await consume_attempt()
        await _run_ffmpeg_cover(input_file, output_file)

        public_storage = storage_service.get_storage_service(
            settings.media_public_bucket
        )
        await _upload_derived_file(
            storage=public_storage,
            object_path=output_path,
            source=output_file,
            content_type="image/jpeg",
            upsert=True,
            cache_seconds=settings.media_public_cache_seconds,
        )

    await _verify_ready_contract(
        asset=asset,
        playback_storage=public_storage,
        playback_object_path=output_path,
        playback_format="jpg",
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
    timeout = httpx.Timeout(connect=5.0, read=5.0, write=5.0, pool=5.0)
    logger.info(
        "Storage download request started url=%s destination=%s",
        storage_service.redact_http_url(url),
        destination,
    )
    bytes_written = 0
    try:
        async with httpx.AsyncClient(
            timeout=timeout,
            limits=storage_service.storage_http_limits(),
        ) as client:
            async with client.stream("GET", url) as response:
                logger.info(
                    "Storage download response received url=%s status=%s",
                    storage_service.redact_http_url(url),
                    response.status_code,
                )
                if response.status_code == 404:
                    raise SourceNotReadyError("Source object not yet available")
                response.raise_for_status()
                with destination.open("wb") as handle:
                    chunks = response.aiter_bytes(chunk_size=1024 * 1024).__aiter__()
                    while True:
                        try:
                            chunk = await asyncio.wait_for(
                                chunks.__anext__(),
                                timeout=_DOWNLOAD_CHUNK_TIMEOUT_SECONDS,
                            )
                        except StopAsyncIteration:
                            break
                        except TimeoutError as exc:
                            logger.warning(
                                "Storage download stalled url=%s destination=%s timeout_seconds=%s bytes_received=%s",
                                storage_service.redact_http_url(url),
                                destination,
                                _DOWNLOAD_CHUNK_TIMEOUT_SECONDS,
                                bytes_written,
                            )
                            raise storage_service.StorageServiceError(
                                "Timed out waiting for storage download bytes"
                            ) from exc
                        if not chunk:
                            continue
                        bytes_written += len(chunk)
                        logger.info(
                            "Storage download chunk received url=%s destination=%s bytes_received=%s total_bytes=%s",
                            storage_service.redact_http_url(url),
                            destination,
                            len(chunk),
                            bytes_written,
                        )
                        handle.write(chunk)
    except httpx.HTTPError as exc:
        logger.warning(
            "Storage download request failed url=%s destination=%s error=%s",
            storage_service.redact_http_url(url),
            destination,
            exc,
        )
        raise storage_service.StorageServiceError(
            "Failed to download storage object"
        ) from exc

    if not destination.exists():
        raise storage_service.StorageServiceError(
            f"Storage download did not create file: {destination}"
        )
    final_size = destination.stat().st_size
    if final_size <= 0:
        raise storage_service.StorageServiceError(
            f"Storage download produced empty file: {destination}"
        )
    logger.info(
        "Storage download completed destination=%s bytes=%s streamed_bytes=%s",
        destination,
        final_size,
        bytes_written,
    )


async def _upload_file(url: str, source: Path, headers: dict[str, str] | None) -> None:
    upload_headers = dict(headers or {})
    if not source.exists():
        raise storage_service.StorageServiceError(
            f"Upload source file missing: {source}"
        )
    source_size = source.stat().st_size
    if source_size <= 0:
        raise storage_service.StorageServiceError(f"Upload source file empty: {source}")

    async def _file_stream(path: Path, chunk_size: int = 1024 * 1024):
        with path.open("rb") as handle:
            while True:
                chunk = await asyncio.to_thread(handle.read, chunk_size)
                if not chunk:
                    break
                yield chunk

    logger.info(
        "Storage upload request started url=%s source=%s bytes=%s",
        storage_service.redact_http_url(url),
        source,
        source_size,
    )
    try:
        async with httpx.AsyncClient(
            timeout=storage_service.storage_http_timeout(),
            limits=storage_service.storage_http_limits(),
        ) as client:
            response = await client.put(
                url, headers=upload_headers, content=_file_stream(source)
            )
    except httpx.HTTPError as exc:
        logger.warning(
            "Storage upload request failed url=%s source=%s error=%s",
            storage_service.redact_http_url(url),
            source,
            exc,
        )
        raise storage_service.StorageServiceError(
            "Failed to upload storage object"
        ) from exc
    logger.info(
        "Storage upload request completed url=%s source=%s status=%s",
        storage_service.redact_http_url(url),
        source,
        response.status_code,
    )
    if response.status_code >= 400:
        raise storage_service.StorageServiceError(
            f"Upload failed with status {response.status_code}",
            status_code=response.status_code,
        )


def _ffmpeg_executable() -> str:
    configured = os.environ.get("FFMPEG_BINARY")
    if configured:
        return configured
    discovered = shutil.which("ffmpeg")
    if discovered:
        return discovered
    try:
        import imageio_ffmpeg

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return "ffmpeg"


def _ffprobe_executable() -> str | None:
    configured = os.environ.get("FFPROBE_BINARY")
    if configured:
        return configured
    return shutil.which("ffprobe")


async def _run_subprocess(
    command: list[str],
    *,
    label: str,
    timeout_seconds: float,
    allow_nonzero: bool = False,
) -> tuple[int, str, str]:
    logger.info("%s subprocess starting command=%s", label, command)

    def _run() -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout_seconds,
        )

    try:
        result = await asyncio.to_thread(_run)
    except FileNotFoundError as exc:
        raise RuntimeError(f"{label} binary not found: {command[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(f"{label} timed out after {timeout_seconds:g}s") from exc

    stdout = result.stdout.decode("utf-8", errors="ignore")
    stderr = result.stderr.decode("utf-8", errors="ignore")
    logger.info(
        "%s subprocess completed returncode=%s stdout=%s stderr=%s",
        label,
        result.returncode,
        _truncate(stdout or "<empty>"),
        _truncate(stderr or "<empty>"),
    )
    if result.returncode != 0 and not allow_nonzero:
        raise RuntimeError(_truncate(stderr or stdout or f"{label} failed"))
    return int(result.returncode or 0), stdout, stderr


async def _run_ffmpeg_audio(input_path: Path, output_path: Path) -> None:
    if not input_path.exists() or input_path.stat().st_size <= 0:
        raise RuntimeError(f"ffmpeg audio input missing or empty: {input_path}")
    logger.info(
        "Running ffmpeg audio input=%s input_bytes=%s output=%s",
        input_path,
        input_path.stat().st_size,
        output_path,
    )
    command = [
        _ffmpeg_executable(),
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
    await _run_subprocess(
        command,
        label="ffmpeg audio",
        timeout_seconds=_FFMPEG_TIMEOUT_SECONDS,
    )
    if not output_path.exists() or output_path.stat().st_size <= 0:
        raise RuntimeError(f"ffmpeg audio output missing or empty: {output_path}")


async def _run_ffmpeg_cover(input_path: Path, output_path: Path) -> None:
    if not input_path.exists() or input_path.stat().st_size <= 0:
        raise RuntimeError(f"ffmpeg cover input missing or empty: {input_path}")
    logger.info(
        "Running ffmpeg cover input=%s input_bytes=%s output=%s",
        input_path,
        input_path.stat().st_size,
        output_path,
    )
    command = [
        _ffmpeg_executable(),
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
    await _run_subprocess(
        command,
        label="ffmpeg cover",
        timeout_seconds=_FFMPEG_TIMEOUT_SECONDS,
    )
    if not output_path.exists() or output_path.stat().st_size <= 0:
        raise RuntimeError(f"ffmpeg cover output missing or empty: {output_path}")


def _parse_duration_seconds(output: str) -> int | None:
    match = _DURATION_RE.search(output)
    if not match:
        return None
    hours = int(match.group("hours"))
    minutes = int(match.group("minutes"))
    seconds = float(match.group("seconds"))
    return int((hours * 3600) + (minutes * 60) + seconds)


async def _probe_duration(path: Path) -> int | None:
    if not path.exists() or path.stat().st_size <= 0:
        raise RuntimeError(f"duration probe input missing or empty: {path}")

    ffprobe = _ffprobe_executable()
    if ffprobe is not None:
        command = [
            ffprobe,
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            str(path),
        ]
        try:
            _, stdout, _ = await _run_subprocess(
                command,
                label="ffprobe duration",
                timeout_seconds=_FFPROBE_TIMEOUT_SECONDS,
            )
        except RuntimeError as exc:
            logger.warning("ffprobe duration failed path=%s error=%s", path, exc)
        else:
            raw = stdout.strip()
            if raw:
                try:
                    return int(float(raw))
                except ValueError:
                    logger.warning(
                        "ffprobe duration was not numeric path=%s raw=%s", path, raw
                    )

    command = [
        _ffmpeg_executable(),
        "-hide_banner",
        "-i",
        str(path),
    ]
    _, stdout, stderr = await _run_subprocess(
        command,
        label="ffmpeg duration",
        timeout_seconds=_FFPROBE_TIMEOUT_SECONDS,
        allow_nonzero=True,
    )
    return _parse_duration_seconds(stderr or stdout)


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
