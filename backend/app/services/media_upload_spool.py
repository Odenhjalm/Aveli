from __future__ import annotations

import asyncio
import hashlib
import shutil
from collections.abc import AsyncIterable, Iterable
from pathlib import Path
from typing import Any

from ..config import settings
from . import storage_service


_SPOOL_ROOT = Path(__file__).resolve().parents[2] / ".media_upload_spool"
_READ_SIZE = 1024 * 1024


class SpoolChecksumMismatchError(RuntimeError):
    """Raised when a chunk digest does not match the client-declared digest."""


class SpoolSizeMismatchError(RuntimeError):
    """Raised when received chunk bytes do not match the declared size."""


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


async def _write_bytes(path: Path, data: bytes, *, append: bool) -> None:
    mode = "ab" if append else "wb"

    def _sync_write() -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open(mode) as handle:
            handle.write(data)

    await asyncio.to_thread(_sync_write)


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
    temp_path = final_path.with_suffix(final_path.suffix + ".tmp")
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

    await asyncio.to_thread(temp_path.replace, final_path)
    return {
        "spool_object_path": logical_path,
        "size_bytes": size,
        "sha256": digest,
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
