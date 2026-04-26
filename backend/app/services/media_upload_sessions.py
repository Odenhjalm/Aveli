from __future__ import annotations

import math
import re
from collections.abc import AsyncIterable
from datetime import datetime, timedelta, timezone
from typing import Any

from ..config import settings
from ..repositories import media_assets as media_assets_repo
from ..repositories import media_upload_sessions as upload_sessions_repo
from ..repositories import storage_objects
from . import media_upload_spool, storage_service


DEFAULT_HOME_PLAYER_CHUNK_SIZE = 8 * 1024 * 1024
DEFAULT_UPLOAD_SESSION_TTL_SECONDS = 60 * 60 * 24
_CONTENT_RANGE_RE = re.compile(r"^bytes\s+(\d+)-(\d+)/(\d+)$", re.IGNORECASE)


class UploadSessionNotFoundError(RuntimeError):
    pass


class UploadSessionConflictError(RuntimeError):
    pass


class UploadChunkConflictError(RuntimeError):
    pass


class UploadChunkRangeError(RuntimeError):
    pass


class UploadChunkChecksumError(RuntimeError):
    pass


class UploadSessionIncompleteError(RuntimeError):
    pass


class UploadSourceVerificationError(RuntimeError):
    pass


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _aware(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value


def _text(value: Any) -> str:
    return str(value or "").strip()


def _normalized_content_type(value: str) -> str:
    normalized = _text(value).lower().split(";", 1)[0].strip()
    if not normalized:
        raise UploadSessionConflictError("content_type is required")
    return normalized


def _validate_home_player_asset(
    media_asset: dict[str, Any],
    *,
    owner_user_id: str,
    require_pending_upload: bool = True,
) -> None:
    if _text(media_asset.get("purpose")).lower() != "home_player_audio":
        raise UploadSessionConflictError("media asset is not a Home Player audio asset")
    if _text(media_asset.get("media_type")).lower() != "audio":
        raise UploadSessionConflictError("media asset is not an audio asset")
    if require_pending_upload and _text(media_asset.get("state")).lower() != "pending_upload":
        raise UploadSessionConflictError("media asset cannot receive upload bytes")
    asset_owner = _text(media_asset.get("owner_user_id"))
    if asset_owner and asset_owner != str(owner_user_id):
        raise UploadSessionConflictError("media asset owner does not match upload owner")


def _session_id(row: dict[str, Any]) -> str:
    return str(row["id"])


def _chunk_response(row: dict[str, Any]) -> dict[str, Any]:
    return {
        "upload_session_id": row["upload_session_id"],
        "media_asset_id": row["media_asset_id"],
        "chunk_index": int(row["chunk_index"]),
        "byte_start": int(row["byte_start"]),
        "byte_end": int(row["byte_end"]),
        "size_bytes": int(row["size_bytes"]),
        "sha256": str(row["sha256"]),
        "received_bytes": int(row.get("received_bytes") or 0),
    }


def _status_response(
    *,
    session: dict[str, Any],
    media_asset: dict[str, Any],
    chunks: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "upload_session_id": session["id"],
        "media_asset_id": session["media_asset_id"],
        "owner_user_id": session["owner_user_id"],
        "state": session["state"],
        "asset_state": media_asset.get("state"),
        "total_bytes": int(session["total_bytes"]),
        "content_type": session["content_type"],
        "chunk_size": int(session["chunk_size"]),
        "expected_chunks": int(session["expected_chunks"]),
        "received_bytes": int(session["received_bytes"]),
        "expires_at": session["expires_at"],
        "chunks": [
            {
                "chunk_index": int(row["chunk_index"]),
                "byte_start": int(row["byte_start"]),
                "byte_end": int(row["byte_end"]),
                "size_bytes": int(row["size_bytes"]),
                "sha256": str(row["sha256"]),
            }
            for row in chunks
        ],
    }


async def create_home_player_upload_session(
    *,
    media_asset: dict[str, Any],
    owner_user_id: str,
    total_bytes: int,
    content_type: str,
    chunk_size: int = DEFAULT_HOME_PLAYER_CHUNK_SIZE,
    expires_at: datetime | None = None,
) -> dict[str, Any]:
    _validate_home_player_asset(
        media_asset,
        owner_user_id=owner_user_id,
        require_pending_upload=True,
    )
    normalized_total = int(total_bytes)
    if normalized_total <= 0:
        raise UploadSessionConflictError("total_bytes must be positive")
    max_bytes = max(1, int(settings.media_upload_max_audio_bytes))
    if normalized_total > max_bytes:
        raise UploadSessionConflictError("file is too large")

    normalized_chunk_size = max(1, int(chunk_size))
    expected_chunks = max(1, math.ceil(normalized_total / normalized_chunk_size))
    resolved_expires_at = expires_at or (
        _utc_now() + timedelta(seconds=DEFAULT_UPLOAD_SESSION_TTL_SECONDS)
    )
    return await upload_sessions_repo.create_upload_session(
        media_asset_id=str(media_asset["id"]),
        owner_user_id=str(owner_user_id),
        total_bytes=normalized_total,
        content_type=_normalized_content_type(content_type),
        chunk_size=normalized_chunk_size,
        expected_chunks=expected_chunks,
        expires_at=resolved_expires_at,
    )


async def _load_open_session(
    *,
    media_asset_id: str,
    upload_session_id: str,
    owner_user_id: str,
) -> dict[str, Any]:
    session = await upload_sessions_repo.get_upload_session_for_owner_media_asset(
        upload_session_id=upload_session_id,
        media_asset_id=media_asset_id,
        owner_user_id=owner_user_id,
    )
    if not session:
        raise UploadSessionNotFoundError("upload session was not found")
    if _text(session.get("state")).lower() != "open":
        raise UploadSessionConflictError("upload session is not open")
    if _aware(session["expires_at"]) <= _utc_now():
        raise UploadSessionConflictError("upload session has expired")
    return session


def _parse_content_range(
    value: str | None,
    *,
    chunk_index: int,
    content_length: int | None,
    session: dict[str, Any],
) -> tuple[int, int, int]:
    total_bytes = int(session["total_bytes"])
    chunk_size = int(session["chunk_size"])
    expected_chunks = int(session["expected_chunks"])
    normalized_chunk_index = int(chunk_index)
    if normalized_chunk_index < 0:
        raise UploadChunkRangeError("chunk index must be non-negative")
    if normalized_chunk_index >= expected_chunks:
        raise UploadChunkRangeError("chunk index exceeds expected chunk count")

    raw = _text(value)
    if raw:
        match = _CONTENT_RANGE_RE.match(raw)
        if not match:
            raise UploadChunkRangeError("invalid content range")
        byte_start = int(match.group(1))
        byte_end = int(match.group(2))
        declared_total = int(match.group(3))
    else:
        if content_length is None:
            raise UploadChunkRangeError("content length is required")
        byte_start = normalized_chunk_index * chunk_size
        byte_end = byte_start + int(content_length) - 1
        declared_total = total_bytes

    size_bytes = byte_end - byte_start + 1
    expected_start = normalized_chunk_index * chunk_size
    is_final_chunk = normalized_chunk_index == expected_chunks - 1
    expected_end = (
        total_bytes - 1 if is_final_chunk else expected_start + chunk_size - 1
    )
    if declared_total != total_bytes:
        raise UploadChunkRangeError("content range total does not match session total")
    if byte_start < 0 or byte_end < byte_start or size_bytes <= 0:
        raise UploadChunkRangeError("content range is invalid")
    if content_length is not None and size_bytes != int(content_length):
        raise UploadChunkRangeError("content range does not match content length")
    if byte_start != expected_start:
        raise UploadChunkRangeError("content range does not match chunk index")
    if byte_end != expected_end:
        raise UploadChunkRangeError("content range does not match expected chunk end")
    return byte_start, byte_end, size_bytes


def _same_chunk(existing: dict[str, Any], expected: dict[str, Any]) -> bool:
    return (
        int(existing["byte_start"]) == int(expected["byte_start"])
        and int(existing["byte_end"]) == int(expected["byte_end"])
        and int(existing["size_bytes"]) == int(expected["size_bytes"])
        and str(existing["sha256"]).lower() == str(expected["sha256"]).lower()
    )


async def _idempotent_chunk_response_or_raise(
    *,
    upload_session_id: str,
    media_asset_id: str,
    owner_user_id: str,
    chunk_index: int,
    expected: dict[str, Any],
) -> dict[str, Any]:
    existing = await upload_sessions_repo.get_upload_chunk(
        upload_session_id=upload_session_id,
        chunk_index=chunk_index,
    )
    if existing is None or not _same_chunk(existing, expected):
        raise UploadChunkConflictError("chunk already exists with different metadata")
    session = await _load_open_session(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
        owner_user_id=owner_user_id,
    )
    row = dict(existing)
    row["received_bytes"] = session["received_bytes"]
    return _chunk_response(row)


async def receive_home_player_upload_chunk(
    *,
    media_asset_id: str,
    upload_session_id: str,
    owner_user_id: str,
    chunk_index: int,
    content: bytes | AsyncIterable[bytes],
    content_range: str | None = None,
    content_length: int | None = None,
    content_type: str | None = None,
    chunk_sha256: str | None = None,
) -> dict[str, Any]:
    session = await _load_open_session(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
        owner_user_id=owner_user_id,
    )
    if content_type and _normalized_content_type(content_type) != session["content_type"]:
        raise UploadSessionConflictError("chunk content type does not match session")

    normalized_chunk_index = int(chunk_index)
    byte_start, byte_end, size_bytes = _parse_content_range(
        content_range,
        chunk_index=normalized_chunk_index,
        content_length=content_length,
        session=session,
    )
    expected_digest = _text(chunk_sha256).lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
        raise UploadChunkChecksumError("chunk checksum is invalid")
    expected = {
        "byte_start": byte_start,
        "byte_end": byte_end,
        "size_bytes": size_bytes,
        "sha256": expected_digest,
    }

    existing = await upload_sessions_repo.get_upload_chunk(
        upload_session_id=upload_session_id,
        chunk_index=normalized_chunk_index,
    )
    if existing is not None:
        if _same_chunk(existing, expected):
            row = dict(existing)
            row["received_bytes"] = session["received_bytes"]
            return _chunk_response(row)
        raise UploadChunkConflictError("chunk already exists with different metadata")

    try:
        spool = await media_upload_spool.write_chunk(
            media_asset_id=media_asset_id,
            upload_session_id=upload_session_id,
            chunk_index=normalized_chunk_index,
            content=content,
            expected_sha256=expected_digest,
            expected_size_bytes=size_bytes,
        )
    except media_upload_spool.SpoolChecksumMismatchError as exc:
        raise UploadChunkChecksumError(str(exc)) from exc
    except media_upload_spool.SpoolSizeMismatchError as exc:
        raise UploadChunkRangeError(str(exc)) from exc
    except media_upload_spool.SpoolChunkConflictError as exc:
        raise UploadChunkConflictError(str(exc)) from exc

    try:
        created = await upload_sessions_repo.create_upload_chunk(
            upload_session_id=upload_session_id,
            media_asset_id=media_asset_id,
            chunk_index=normalized_chunk_index,
            byte_start=byte_start,
            byte_end=byte_end,
            size_bytes=size_bytes,
            sha256=str(spool["sha256"]),
            spool_object_path=str(spool["spool_object_path"]),
        )
    except upload_sessions_repo.UploadChunkAlreadyExistsError as exc:
        return await _idempotent_chunk_response_or_raise(
            upload_session_id=upload_session_id,
            media_asset_id=media_asset_id,
            owner_user_id=owner_user_id,
            chunk_index=normalized_chunk_index,
            expected={
                "byte_start": byte_start,
                "byte_end": byte_end,
                "size_bytes": size_bytes,
                "sha256": str(spool["sha256"]),
            },
        )
    return _chunk_response(created)


async def get_home_player_upload_session_status(
    *,
    media_asset: dict[str, Any],
    media_asset_id: str,
    upload_session_id: str,
    owner_user_id: str,
) -> dict[str, Any]:
    _validate_home_player_asset(
        media_asset,
        owner_user_id=owner_user_id,
        require_pending_upload=False,
    )
    session = await upload_sessions_repo.get_upload_session_for_owner_media_asset(
        upload_session_id=upload_session_id,
        media_asset_id=media_asset_id,
        owner_user_id=owner_user_id,
    )
    if not session:
        raise UploadSessionNotFoundError("upload session was not found")
    chunks = await upload_sessions_repo.list_upload_chunks(
        upload_session_id=upload_session_id,
    )
    return _status_response(session=session, media_asset=media_asset, chunks=chunks)


def _validate_complete_chunks(
    *,
    session: dict[str, Any],
    chunks: list[dict[str, Any]],
) -> None:
    expected_chunks = int(session["expected_chunks"])
    total_bytes = int(session["total_bytes"])
    if len(chunks) != expected_chunks:
        raise UploadSessionIncompleteError("upload session is missing chunks")
    expected_start = 0
    for expected_index, row in enumerate(chunks):
        if int(row["chunk_index"]) != expected_index:
            raise UploadSessionIncompleteError("upload chunks are not contiguous")
        if int(row["byte_start"]) != expected_start:
            raise UploadSessionIncompleteError("upload chunk byte ranges are not contiguous")
        byte_end = int(row["byte_end"])
        if byte_end < expected_start:
            raise UploadSessionIncompleteError("upload chunk byte range is invalid")
        expected_start = byte_end + 1
    if expected_start != total_bytes:
        raise UploadSessionIncompleteError("upload chunks do not match total bytes")


async def _verify_source_object(*, bucket: str, object_path: str) -> None:
    existence, table_available = await storage_objects.fetch_storage_object_existence(
        [(bucket, object_path)]
    )
    if table_available:
        if not existence.get((bucket, object_path), False):
            raise UploadSourceVerificationError("uploaded source object is missing")
        return
    try:
        service = storage_service.get_storage_service(bucket)
        await service.get_presigned_url(object_path, ttl=60, download=False)
    except storage_service.StorageObjectNotFoundError as exc:
        raise UploadSourceVerificationError("uploaded source object is missing") from exc
    except storage_service.StorageServiceError as exc:
        raise UploadSourceVerificationError("uploaded source object cannot be verified") from exc


async def finalize_home_player_upload_session(
    *,
    media_asset: dict[str, Any],
    media_asset_id: str,
    upload_session_id: str,
    owner_user_id: str,
) -> dict[str, Any]:
    _validate_home_player_asset(
        media_asset,
        owner_user_id=owner_user_id,
        require_pending_upload=True,
    )
    session = await _load_open_session(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
        owner_user_id=owner_user_id,
    )
    chunks = await upload_sessions_repo.list_upload_chunks(
        upload_session_id=upload_session_id,
    )
    _validate_complete_chunks(session=session, chunks=chunks)

    object_path = _text(media_asset.get("original_object_path")).lstrip("/")
    if not object_path:
        raise UploadSourceVerificationError("media asset source path is missing")
    bucket = settings.media_source_bucket
    await media_upload_spool.reconstruct_source_object(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
        chunks=chunks,
        destination_object_path=object_path,
        content_type=str(session["content_type"]),
        total_bytes=int(session["total_bytes"]),
        bucket=bucket,
    )
    await _verify_source_object(bucket=bucket, object_path=object_path)

    updated = await media_assets_repo.mark_lesson_media_pipeline_asset_uploaded(
        media_id=media_asset_id,
    )
    if not updated:
        raise UploadSessionConflictError("media asset cannot be marked uploaded")
    finalized = await upload_sessions_repo.mark_upload_session_finalized(
        upload_session_id=upload_session_id,
        media_asset_id=media_asset_id,
        owner_user_id=owner_user_id,
    )
    if not finalized:
        raise UploadSessionConflictError("upload session cannot be finalized")
    await media_upload_spool.delete_session_spool(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
    )
    return {
        "upload_session_id": finalized["id"],
        "media_asset_id": media_asset_id,
        "asset_state": updated["state"],
    }


async def finalize_active_home_player_upload_session(
    *,
    media_asset: dict[str, Any],
    media_asset_id: str,
    owner_user_id: str,
) -> dict[str, Any]:
    _validate_home_player_asset(
        media_asset,
        owner_user_id=owner_user_id,
        require_pending_upload=True,
    )
    session = await upload_sessions_repo.get_active_upload_session_for_owner_media_asset(
        media_asset_id=media_asset_id,
        owner_user_id=owner_user_id,
    )
    if not session:
        raise UploadSessionNotFoundError("active upload session was not found")
    return await finalize_home_player_upload_session(
        media_asset=media_asset,
        media_asset_id=media_asset_id,
        upload_session_id=str(session["id"]),
        owner_user_id=owner_user_id,
    )


async def cleanup_abandoned_upload_sessions() -> int:
    return await upload_sessions_repo.expire_abandoned_upload_sessions(now_at=_utc_now())
