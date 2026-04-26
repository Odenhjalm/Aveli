from __future__ import annotations

import asyncio
import hashlib
import itertools
import os
import shutil
import time
from collections.abc import AsyncIterable, Iterable
from pathlib import Path
from typing import Any
from uuid import uuid4

from ..config import settings
from . import storage_service


_SPOOL_ROOT = Path(__file__).resolve().parents[2] / ".media_upload_spool"
_READ_SIZE = 1024 * 1024
_LOCK_TIMEOUT_SECONDS = 10.0
_TEMP_COUNTER = itertools.count()


class SpoolChecksumMismatchError(RuntimeError):
    """Raised when a chunk digest does not match the client-declared digest."""


class SpoolSizeMismatchError(RuntimeError):
    """Raised when received chunk bytes do not match the declared size."""


class SpoolChunkConflictError(RuntimeError):
    """Raised when a published chunk path already has different bytes."""


def _clean_component(value: str) -> str:
    normalized = str(value or "").strip()
    if not normalized or "/" in normalized or "\\" in normalized or normalized in {".", ".."}:
        raise ValueError("invalid upload spool path component")
    return normalized


def _chunk_logical_path(
    *,
    media_asset_id: str,
    upload_session_id: str,
    chunk_index: int,
) -> str:
    asset = _clean_component(media_asset_id)
    session = _clean_component(upload_session_id)
    index = int(chunk_index)
    if index < 0:
        raise ValueError("chunk_index must be non-negative")
    return f"media-upload-sessions/{asset}/{session}/chunks/{index:08d}.part"


def _path_for_logical_path(logical_path: str) -> Path:
    normalized = str(logical_path or "").strip().replace("\\", "/").lstrip("/")
    if not normalized.startswith("media-upload-sessions/"):
        raise ValueError("invalid upload spool logical path")
    path = (_SPOOL_ROOT / normalized).resolve()
    root = _SPOOL_ROOT.resolve()
    path.relative_to(root)
    return path


def _unique_temp_path(final_path: Path) -> Path:
    suffix = f".{os.getpid()}.{next(_TEMP_COUNTER)}.{uuid4().hex}.tmp"
    return final_path.with_name(final_path.name + suffix)


def _sha256_file_sync(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(_READ_SIZE), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def _write_bytes_sync(path: Path, data: bytes, *, append: bool) -> None:
    mode = "ab" if append else "wb"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open(mode) as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


async def _write_bytes(path: Path, data: bytes, *, append: bool) -> None:
    await asyncio.to_thread(_write_bytes_sync, path, data, append=append)


def _publish_temp_file_sync(
    *,
    temp_path: Path,
    final_path: Path,
    digest: str,
) -> str:
    final_path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = final_path.with_name(final_path.name + ".lock")
    deadline = time.monotonic() + _LOCK_TIMEOUT_SECONDS
    fd: int | None = None
    while fd is None:
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            if time.monotonic() >= deadline:
                raise SpoolChunkConflictError("chunk publish lock timed out")
            time.sleep(0.01)

    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(f"{os.getpid()}\n")
        fd = None
        if final_path.exists():
            existing_digest = _sha256_file_sync(final_path)
            if existing_digest != digest:
                raise SpoolChunkConflictError(
                    "chunk already exists with different bytes"
                )
            return existing_digest
        os.replace(temp_path, final_path)
        published_digest = _sha256_file_sync(final_path)
        if published_digest != digest:
            raise SpoolChecksumMismatchError(
                "published chunk checksum changed during write"
            )
        return published_digest
    finally:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
        temp_path.unlink(missing_ok=True)
        lock_path.unlink(missing_ok=True)


async def _publish_temp_file(
    *,
    temp_path: Path,
    final_path: Path,
    digest: str,
) -> str:
    return await asyncio.to_thread(
        _publish_temp_file_sync,
        temp_path=temp_path,
        final_path=final_path,
        digest=digest,
    )


async def _iter_content(content: bytes | AsyncIterable[bytes]) -> AsyncIterable[bytes]:
    if isinstance(content, bytes):
        yield content
        return
    async for part in content:
        yield bytes(part)


async def write_chunk(
    *,
    media_asset_id: str,
    upload_session_id: str,
    chunk_index: int,
    content: bytes | AsyncIterable[bytes],
    expected_sha256: str | None = None,
    expected_size_bytes: int | None = None,
) -> dict[str, Any]:
    logical_path = _chunk_logical_path(
        media_asset_id=media_asset_id,
        upload_session_id=upload_session_id,
        chunk_index=chunk_index,
    )
    final_path = _path_for_logical_path(logical_path)
    temp_path = _unique_temp_path(final_path)
    hasher = hashlib.sha256()
    size = 0
    first = True

    async for part in _iter_content(content):
        if not part:
            continue
        hasher.update(part)
        size += len(part)
        await _write_bytes(temp_path, part, append=not first)
        first = False

    if first:
        raise SpoolSizeMismatchError("chunk payload is empty")

    if expected_size_bytes is not None and size != int(expected_size_bytes):
        temp_path.unlink(missing_ok=True)
        raise SpoolSizeMismatchError("chunk payload size does not match declared size")

    digest = hasher.hexdigest()
    if expected_sha256 is not None and digest != str(expected_sha256).strip().lower():
        temp_path.unlink(missing_ok=True)
        raise SpoolChecksumMismatchError("chunk checksum does not match declared digest")

    persisted_digest = await asyncio.to_thread(_sha256_file_sync, temp_path)
    if persisted_digest != digest:
        temp_path.unlink(missing_ok=True)
        raise SpoolChecksumMismatchError("chunk checksum changed during write")

    final_digest = await _publish_temp_file(
        temp_path=temp_path,
        final_path=final_path,
        digest=digest,
    )
    if (
        expected_sha256 is not None
        and final_digest != str(expected_sha256).strip().lower()
    ):
        raise SpoolChecksumMismatchError("published chunk checksum does not match digest")
    return {
        "spool_object_path": logical_path,
        "size_bytes": size,
        "sha256": final_digest,
    }


async def _read_file_chunks(path: Path) -> AsyncIterable[bytes]:
    with path.open("rb") as handle:
        while True:
            chunk = await asyncio.to_thread(handle.read, _READ_SIZE)
            if not chunk:
                break
            yield chunk


async def reconstruct_source_object(
    *,
    media_asset_id: str,
    upload_session_id: str,
    chunks: Iterable[dict[str, Any]],
    destination_object_path: str,
    content_type: str,
    total_bytes: int,
    bucket: str | None = None,
) -> str:
    chunk_rows = list(chunks)
    if not chunk_rows:
        raise ValueError("upload session has no chunks to reconstruct")

    async def _source_stream() -> AsyncIterable[bytes]:
        for row in chunk_rows:
            path = _path_for_logical_path(str(row.get("spool_object_path") or ""))
            async for part in _read_file_chunks(path):
                yield part

    resolved_bucket = bucket or settings.media_source_bucket
    storage = storage_service.get_storage_service(resolved_bucket)
    await storage.upload_object(
        destination_object_path,
        content=_source_stream(),
        content_type=content_type,
        content_length=total_bytes,
        media_asset_id=media_asset_id,
        upsert=False,
        cache_seconds=settings.media_public_cache_seconds,
    )
    return destination_object_path


async def delete_session_spool(
    *,
    media_asset_id: str,
    upload_session_id: str,
) -> None:
    asset = _clean_component(media_asset_id)
    session = _clean_component(upload_session_id)
    root = _SPOOL_ROOT.resolve()
    session_path = (root / "media-upload-sessions" / asset / session).resolve()
    session_path.relative_to(root)
    if session_path.exists():
        await asyncio.to_thread(shutil.rmtree, session_path)
