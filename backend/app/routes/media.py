from __future__ import annotations

import logging
from pathlib import Path
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse
from starlette.background import BackgroundTask

from .. import models, schemas
from ..auth import CurrentUser
from ..config import settings
from ..repositories import media_resolution_failures
from ..repositories import storage_objects
from ..services import lesson_playback_service, storage_service
from ..utils.http_headers import build_content_disposition
from ..utils import media_robustness
from ..utils.media_signer import (
    MediaTokenError,
    is_signing_enabled,
    verify_media_token,
)
from . import upload as upload_routes

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["media"])


_KNOWN_BUCKET_PREFIXES = {
    "course-media",
    "public-media",
    "lesson-media",
    settings.media_source_bucket,
    settings.media_public_bucket,
}


def _normalize_storage_path(storage_path: str) -> str:
    raw = str(storage_path or "").strip()
    parsed = urlparse(raw)
    if parsed.scheme in {"http", "https"} and parsed.path:
        raw = parsed.path
    normalized = raw.replace("\\", "/").lstrip("/")
    for prefix in ("api/files/", "storage/v1/object/public/", "storage/v1/object/sign/"):
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix) :].lstrip("/")
            break
    return normalized


def _storage_candidates(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> list[tuple[str, str]]:
    normalized_bucket = (storage_bucket or "").strip() or settings.media_source_bucket
    normalized_path = _normalize_storage_path(storage_path)
    if not normalized_path:
        return []

    candidates: list[tuple[str, str]] = []

    def _add(bucket: str, key: str) -> None:
        if not bucket or not key:
            return
        pair = (bucket, key)
        if pair not in candidates:
            candidates.append(pair)

    def _add_for_bucket(bucket: str) -> None:
        prefix = f"{bucket}/"
        if normalized_path.startswith(prefix):
            stripped = normalized_path[len(prefix) :].lstrip("/")
            if stripped:
                _add(bucket, stripped)
            _add(bucket, normalized_path)
        else:
            _add(bucket, normalized_path)

    _add_for_bucket(normalized_bucket)

    prefix_bucket = normalized_path.split("/", 1)[0]
    if prefix_bucket in _KNOWN_BUCKET_PREFIXES and prefix_bucket != normalized_bucket:
        _add_for_bucket(prefix_bucket)

    return candidates


def _failure_reason(
    *,
    storage_bucket: str | None,
    storage_path: str,
) -> str:
    bucket = (storage_bucket or "").strip() or None
    normalized_path = _normalize_storage_path(storage_path)
    if not normalized_path:
        return "unsupported"
    prefix_bucket = normalized_path.split("/", 1)[0]
    if bucket and prefix_bucket in _KNOWN_BUCKET_PREFIXES and prefix_bucket != bucket:
        return "bucket_mismatch"
    if bucket and normalized_path.startswith(f"{bucket}/"):
        return "key_format_drift"
    return "missing_object"


def _recommended_action_for_reason(reason: str | None) -> str:
    normalized = (reason or "").strip().lower()
    if normalized in {"bucket_mismatch", "key_format_drift"}:
        return "auto_migrate"
    if normalized == "missing_object":
        return "reupload_required"
    return "manual_review"


async def _augment_failure_details_with_invariant(
    *,
    row: dict,
    mode: str | None,
    storage_bucket: str | None,
    storage_path: str,
    details: dict,
) -> dict:
    """Attach invariant diagnostics when a resolvable media ref yields no bytes.

    This is best-effort: failures must never affect the HTTP response.
    """

    try:
        kind = row.get("kind")
        supported_kind = (
            media_robustness.normalize_media_kind(kind)
            in media_robustness.SUPPORTED_MEDIA_KINDS
        )
        if not supported_kind:
            return details

        candidates = _storage_candidates(
            storage_bucket=storage_bucket,
            storage_path=str(storage_path),
        )
        if not candidates:
            return details

        existence, storage_table_available = (
            await storage_objects.fetch_storage_object_existence(candidates)
        )
        if not storage_table_available:
            return details

        exists_pairs = [
            {"bucket": b, "key": k}
            for b, k in candidates
            if existence.get((b, k), False)
        ]
        if not exists_pairs:
            return details

        details = dict(details or {})
        details.setdefault("candidates", [{"bucket": b, "key": k} for b, k in candidates])
        details["invariant_resolvable_expected"] = True
        details["invariant_supported_kind"] = True
        details["invariant_mode"] = media_resolution_failures.normalize_mode(mode)
        details["invariant_existing_pairs"] = exists_pairs

        logger.error(
            "Media invariant violated: bytes expected but not retrievable "
            "media_id=%s kind=%s storage_bucket=%s storage_path=%s mode=%s existing_pairs=%s",
            row.get("id"),
            kind,
            storage_bucket,
            storage_path,
            details.get("invariant_mode"),
            exists_pairs,
        )
        return details
    except Exception:  # pragma: no cover - defensive logging
        logger.exception(
            "Failed to attach invariant diagnostics for media_id=%s storage_bucket=%s storage_path=%s",
            row.get("id"),
            storage_bucket,
            storage_path,
        )
        return details


async def _build_streaming_response(
    row: dict,
    request: Request,
    *,
    lesson_media_id: str | None = None,
    mode: str | None = None,
) -> StreamingResponse:
    kind = str(row.get("kind") or "").strip().lower()
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
        bucket = (row.get("storage_bucket") or "").strip() or None
        normalized_mode = media_resolution_failures.normalize_mode(mode)
        storage_client = storage_service.get_storage_service(bucket)
        if not storage_client.enabled:
            logger.warning(
                "Media file missing and storage disabled: media_id=%s storage_bucket=%s storage_path=%s",
                row.get("id"),
                bucket,
                storage_path,
            )
            failure_reason = _failure_reason(
                storage_bucket=bucket,
                storage_path=str(storage_path),
            )
            details = {
                "storage_bucket": bucket,
                "storage_path": storage_path,
                "storage_enabled": False,
                "recommended_action": "manual_review",
            }
            details = await _augment_failure_details_with_invariant(
                row=row,
                mode=normalized_mode,
                storage_bucket=bucket,
                storage_path=str(storage_path),
                details=details,
            )
            await media_resolution_failures.record_media_resolution_failure(
                lesson_media_id=lesson_media_id,
                mode=normalized_mode,
                reason=failure_reason,
                details=details,
            )
            raise HTTPException(status_code=404, detail="File missing")

        filename = row.get("original_name") or Path(storage_path).name or "media"
        ttl_seconds = settings.media_signing_ttl_seconds
        if ttl_seconds <= 0:
            ttl_seconds = settings.media_playback_url_ttl_seconds
        ttl_seconds = max(60, int(ttl_seconds))

        try:
            presigned: storage_service.PresignedUrl | None = None
            used_bucket = bucket
            used_key = str(storage_path)
            storage_candidates = _storage_candidates(
                storage_bucket=bucket,
                storage_path=str(storage_path),
            )
            for candidate_bucket, candidate_key in storage_candidates:
                candidate_client = storage_service.get_storage_service(candidate_bucket)
                if not candidate_client.enabled:
                    continue
                try:
                    presigned = await candidate_client.get_presigned_url(
                        candidate_key,
                        ttl=ttl_seconds,
                        filename=filename,
                        download=False,
                    )
                except storage_service.StorageObjectNotFoundError:
                    continue
                used_bucket = candidate_bucket
                used_key = candidate_key
                break
            if presigned is None:
                raise storage_service.StorageObjectNotFoundError(
                    "Supabase Storage object not found"
                )
            bucket = used_bucket
            storage_path = used_key
        except storage_service.StorageObjectNotFoundError:
            logger.warning(
                "Media missing in storage: media_id=%s storage_bucket=%s storage_path=%s",
                row.get("id"),
                bucket,
                storage_path,
            )
            failure_reason = _failure_reason(
                storage_bucket=bucket,
                storage_path=str(storage_path),
            )
            details = {
                "storage_bucket": bucket,
                "storage_path": storage_path,
                "candidates": [
                    {"bucket": b, "key": k}
                    for b, k in _storage_candidates(
                        storage_bucket=bucket,
                        storage_path=str(storage_path),
                    )
                ],
                "recommended_action": _recommended_action_for_reason(failure_reason),
            }
            details = await _augment_failure_details_with_invariant(
                row=row,
                mode=normalized_mode,
                storage_bucket=bucket,
                storage_path=str(storage_path),
                details=details,
            )
            await media_resolution_failures.record_media_resolution_failure(
                lesson_media_id=lesson_media_id,
                mode=normalized_mode,
                reason=failure_reason,
                details=details,
            )
            raise HTTPException(status_code=404, detail="File missing") from None
        except storage_service.StorageServiceError as exc:
            logger.warning(
                "Storage proxy signing failed: media_id=%s storage_bucket=%s storage_path=%s error=%s",
                row.get("id"),
                bucket,
                storage_path,
                exc,
            )
            await media_resolution_failures.record_media_resolution_failure(
                lesson_media_id=lesson_media_id,
                mode=normalized_mode,
                reason="cannot_sign",
                details={
                    "storage_bucket": bucket,
                    "storage_path": storage_path,
                    "error": str(exc),
                    "recommended_action": _recommended_action_for_reason("cannot_sign"),
                },
            )
            raise HTTPException(status_code=503, detail="Storage unavailable") from exc

        range_header = request.headers.get("range")
        request_headers: dict[str, str] = {}
        if range_header:
            request_headers["Range"] = range_header

        client = httpx.AsyncClient(follow_redirects=True, timeout=None)
        upstream_ctx = client.stream("GET", presigned.url, headers=request_headers)
        try:
            upstream = await upstream_ctx.__aenter__()
        except httpx.HTTPError as exc:
            await client.aclose()
            logger.warning(
                "Storage proxy request failed: media_id=%s storage_bucket=%s storage_path=%s error=%s",
                row.get("id"),
                bucket,
                storage_path,
                exc,
            )
            await media_resolution_failures.record_media_resolution_failure(
                lesson_media_id=lesson_media_id,
                mode=normalized_mode,
                reason="cannot_sign",
                details={
                    "storage_bucket": bucket,
                    "storage_path": storage_path,
                    "error": str(exc),
                    "recommended_action": _recommended_action_for_reason("cannot_sign"),
                },
            )
            raise HTTPException(status_code=503, detail="Storage unavailable") from exc

        if upstream.status_code >= 400:
            status_code = upstream.status_code
            await upstream_ctx.__aexit__(None, None, None)
            await client.aclose()
            logger.warning(
                "Storage proxy returned error: media_id=%s status=%s storage_bucket=%s storage_path=%s",
                row.get("id"),
                status_code,
                bucket,
                storage_path,
            )
            if status_code == 404:
                failure_reason = _failure_reason(
                    storage_bucket=bucket,
                    storage_path=str(storage_path),
                )
                details = {
                    "storage_bucket": bucket,
                    "storage_path": storage_path,
                    "status_code": status_code,
                    "recommended_action": _recommended_action_for_reason(
                        failure_reason
                    ),
                }
                details = await _augment_failure_details_with_invariant(
                    row=row,
                    mode=normalized_mode,
                    storage_bucket=bucket,
                    storage_path=str(storage_path),
                    details=details,
                )
                await media_resolution_failures.record_media_resolution_failure(
                    lesson_media_id=lesson_media_id,
                    mode=normalized_mode,
                    reason=failure_reason,
                    details=details,
                )
                raise HTTPException(status_code=404, detail="File missing") from None
            await media_resolution_failures.record_media_resolution_failure(
                lesson_media_id=lesson_media_id,
                mode=normalized_mode,
                reason="cannot_sign",
                details={
                    "storage_bucket": bucket,
                    "storage_path": storage_path,
                    "status_code": status_code,
                    "recommended_action": _recommended_action_for_reason("cannot_sign"),
                },
            )
            raise HTTPException(status_code=503, detail="Storage unavailable") from None

        content_type = (
            upstream.headers.get("content-type")
            or row.get("content_type")
            or "application/octet-stream"
        )
        lower_content_type = str(content_type).strip().lower()
        document_response = kind in {"document", "pdf"} or lower_content_type.startswith(
            "application/pdf"
        )
        response_headers = {
            "Accept-Ranges": upstream.headers.get("accept-ranges", "bytes"),
            "Access-Control-Allow-Origin": "*",
        }
        cache_seconds = max(0, ttl_seconds)
        if cache_seconds > 0:
            response_headers["Cache-Control"] = f"private, max-age={cache_seconds}"
        else:
            response_headers["Cache-Control"] = "no-store"
        response_headers["Content-Disposition"] = build_content_disposition(
            filename,
            disposition="attachment" if document_response else "inline",
        )
        for header_name in ("content-range", "content-length"):
            if header_name in upstream.headers:
                response_headers[header_name.title()] = upstream.headers[header_name]

        async def _cleanup() -> None:
            await upstream_ctx.__aexit__(None, None, None)
            await client.aclose()

        return StreamingResponse(
            upstream.aiter_bytes(),
            status_code=upstream.status_code,
            media_type=content_type,
            headers=response_headers,
            background=BackgroundTask(_cleanup),
        )

    file_size = file_path.stat().st_size
    content_type = row.get("content_type") or "application/octet-stream"
    lower_content_type = str(content_type).strip().lower()
    document_response = kind in {"document", "pdf"} or lower_content_type.startswith(
        "application/pdf"
    )
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
    headers["Content-Disposition"] = build_content_disposition(
        filename,
        disposition="attachment" if document_response else "inline",
    )

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
    resolved = await lesson_playback_service.resolve_legacy_playback(
        lesson_media_id=payload.media_id,
        user_id=str(current["id"]),
        mode=payload.mode,
    )
    return schemas.MediaSignResponse(
        media_id=resolved["media_id"],
        signed_url=resolved["url"],
        expires_at=resolved["expires_at"],
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

    normalized_mode = media_resolution_failures.normalize_mode(payload.get("purpose"))

    row = await models.get_media(media_id)
    lesson_media_id: str | None = None
    if not row:
        # Attempt fallback to direct media object references (e.g. avatars)
        media_object = await models.get_media_object(media_id)
        if not media_object:
            raise HTTPException(status_code=404, detail="Media not found")
        row = {
            "id": media_object["id"],
            "storage_path": media_object.get("storage_path"),
            "storage_bucket": media_object.get("storage_bucket"),
            "content_type": media_object.get("content_type"),
        }
    else:
        lesson_media_id = str(row.get("id") or "")

    return await _build_streaming_response(
        row,
        request,
        lesson_media_id=lesson_media_id,
        mode=normalized_mode,
    )
