from __future__ import annotations

import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..utils.http_headers import build_content_disposition
from ..utils.media_signer import (
    MediaTokenError,
    issue_signed_url,
    is_signing_enabled,
    verify_media_token,
)
from . import upload as upload_routes

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["media"])


def _build_streaming_response(row: dict, request: Request) -> StreamingResponse:
    storage_path = row.get("storage_path")
    if not storage_path:
        raise HTTPException(status_code=404, detail="Media not found")

    file_path: Path | None = None
    candidates: list[Path] = []
    try:
        relative = Path(storage_path)
        candidates.append(
            upload_routes._safe_join(upload_routes.UPLOADS_ROOT, *relative.parts)
        )
    except HTTPException:
        pass

    bucket = row.get("storage_bucket")
    base_dir = Path(settings.media_root)
    if bucket:
        candidates.append(base_dir / bucket / storage_path)
    candidates.append(base_dir / storage_path)

    for candidate in candidates:
        if candidate.exists():
            file_path = candidate
            break

    if file_path is None or not file_path.exists():
        logger.warning(
            "Media file missing on disk: media_id=%s expected_path=%s",
            row.get("id"),
            candidates[0].resolve() if candidates else storage_path,
        )
        raise HTTPException(status_code=404, detail="File missing")

    file_size = file_path.stat().st_size
    content_type = row.get("content_type") or "application/octet-stream"
    range_header = request.headers.get("range")

    def file_iterator(
        start: int = 0, end: int | None = None, chunk_size: int = 64 * 1024
    ):
        with file_path.open("rb") as stream:
            stream.seek(start)
            remaining = None if end is None else end - start + 1
            while True:
                read_size = (
                    chunk_size if remaining is None else min(chunk_size, remaining)
                )
                data = stream.read(read_size)
                if not data:
                    break
                yield data
                if remaining is not None:
                    remaining -= len(data)
                    if remaining <= 0:
                        break

    headers = {
        "Accept-Ranges": "bytes",
        "Access-Control-Allow-Origin": "*",
    }
    filename = row.get("original_name") or Path(storage_path).name
    cache_seconds = max(0, settings.media_signing_ttl_seconds)
    if cache_seconds > 0:
        headers["Cache-Control"] = f"private, max-age={cache_seconds}"
    else:
        headers["Cache-Control"] = "no-store"
    headers["Content-Disposition"] = build_content_disposition(filename, disposition="inline")

    if range_header and range_header.startswith("bytes="):
        try:
            range_value = range_header.replace("bytes=", "")
            start_str, end_str = (range_value.split("-", 1) + [""])[:2]
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
        except ValueError:
            raise HTTPException(
                status_code=416, detail="Invalid range header"
            ) from None

        start = max(0, start)
        end = min(file_size - 1, end)
        if start > end:
            raise HTTPException(status_code=416, detail="Invalid range header")

        content_length = end - start + 1
        headers.update(
            {
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Content-Length": str(content_length),
            }
        )
        return StreamingResponse(
            file_iterator(start, end),
            status_code=206,
            media_type=content_type,
            headers=headers,
        )

    headers["Content-Length"] = str(file_size)
    return StreamingResponse(
        file_iterator(),
        media_type=content_type,
        headers=headers,
    )


@router.post("/sign", response_model=schemas.MediaSignResponse)
async def sign_media(payload: schemas.MediaSignRequest, current: CurrentUser):
    if not is_signing_enabled():
        raise HTTPException(status_code=503, detail="Media signing disabled")

    row = await models.get_media(payload.media_id)
    if not row:
        raise HTTPException(status_code=404, detail="Media not found")

    issued = issue_signed_url(row["id"])
    if not issued:
        raise HTTPException(status_code=503, detail="Unable to create signed URL")

    signed_url, expires_at = issued
    return schemas.MediaSignResponse(
        media_id=str(row["id"]), signed_url=signed_url, expires_at=expires_at
    )


@router.get("/stream/{token}")
async def stream_signed_media(token: str, request: Request):
    if not is_signing_enabled():
        raise HTTPException(status_code=503, detail="Media signing disabled")

    try:
        payload = verify_media_token(token)
    except MediaTokenError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc

    media_id = payload.get("sub")
    if not media_id:
        raise HTTPException(status_code=400, detail="Malformed media token")

    row = await models.get_media(media_id)
    if not row:
        # Attempt fallback to direct media object references (e.g. avatars)
        media_object = await models.get_media_object(media_id)
        if not media_object:
            raise HTTPException(status_code=404, detail="Media not found")
        row = {
            "id": media_object["id"],
            "storage_path": media_object.get("storage_path"),
            "content_type": media_object.get("content_type"),
        }

    return _build_streaming_response(row, request)
