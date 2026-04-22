from __future__ import annotations

import logging
from collections.abc import AsyncIterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import quote, urlsplit, urlunsplit

import httpx

from ..config import settings
from ..utils.http_headers import build_content_disposition

logger = logging.getLogger(__name__)


def storage_http_timeout() -> httpx.Timeout:
    return httpx.Timeout(10.0, connect=5.0, read=10.0)


def storage_http_limits() -> httpx.Limits:
    return httpx.Limits(max_keepalive_connections=0)


def redact_http_url(url: str) -> str:
    try:
        parsed = urlsplit(str(url))
    except ValueError:
        return "<invalid-url>"
    if not parsed.query:
        return str(url)
    return urlunsplit(
        (parsed.scheme, parsed.netloc, parsed.path, "<redacted>", parsed.fragment)
    )


class StorageServiceError(RuntimeError):
    """Raised when Supabase Storage returns an error."""

    def __init__(
        self,
        message: str,
        *,
        status_code: int | None = None,
        error: str | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.error = error


class StorageObjectNotFoundError(StorageServiceError):
    """Raised when Supabase Storage reports an object is missing."""


@dataclass(slots=True)
class PresignedUrl:
    url: str
    expires_in: int
    headers: Mapping[str, str]


@dataclass(slots=True)
class PresignedUpload:
    url: str
    headers: Mapping[str, str]
    path: str
    expires_in: int


@dataclass(slots=True)
class StorageObjectMetadata:
    path: str
    content_type: str | None
    size_bytes: int | None


def _normalize_content_type(value: str | None) -> str | None:
    normalized = str(value or "").strip().lower()
    if not normalized:
        return None
    return normalized.split(";", 1)[0].strip() or None


def _normalize_storage_path(path: str) -> str:
    normalized = str(path or "").strip().lstrip("/")
    if not normalized:
        raise StorageServiceError("storage path is required")
    return normalized


def _quoted_storage_path(path: str) -> str:
    return quote(_normalize_storage_path(path), safe="/")


def _response_size_bytes(response: httpx.Response) -> int | None:
    content_range = str(response.headers.get("content-range") or "").strip()
    if "/" in content_range:
        total = content_range.rsplit("/", 1)[-1].strip()
        if total and total != "*":
            try:
                return int(total)
            except ValueError:
                pass
    content_length = str(response.headers.get("content-length") or "").strip()
    if content_length:
        try:
            return int(content_length)
        except ValueError:
            return None
    return None


class StorageService:
    def __init__(
        self,
        *,
        bucket: str = "course-media",
        supabase_url: str | None = None,
        service_role_key: str | None = None,
    ) -> None:
        self._bucket = bucket.strip() or "course-media"
        self._supabase_url = supabase_url or (
            settings.supabase_url.unicode_string()
            if settings.supabase_url is not None
            else None
        )
        self._service_role_key = service_role_key or settings.supabase_service_role_key

    @property
    def bucket(self) -> str:
        return self._bucket

    @property
    def enabled(self) -> bool:
        return bool(self._supabase_url and self._service_role_key)

    def public_url(self, path: str) -> str:
        supabase_url = self._supabase_url
        if not supabase_url:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = _normalize_storage_path(path)
        base_url = supabase_url.rstrip("/")
        return (
            f"{base_url}/storage/v1/object/public/{self._bucket}/"
            f"{_quoted_storage_path(normalized_path)}"
        )

    async def get_presigned_url(
        self,
        path: str,
        ttl: int,
        filename: str | None = None,
        *,
        download: bool = True,
    ) -> PresignedUrl:
        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = _normalize_storage_path(path)
        expires_in = max(60, min(int(ttl), 60 * 60 * 24))
        download_name = filename or Path(normalized_path).name or "media"

        base_url = supabase_url.rstrip("/")
        request_url = (
            f"{base_url}/storage/v1/object/sign/{self._bucket}/"
            f"{_quoted_storage_path(normalized_path)}"
        )
        payload: dict[str, Any] = {"expiresIn": expires_in}

        logger.info(
            "Supabase Storage presigned URL request started bucket=%s path=%s",
            self._bucket,
            normalized_path,
        )
        async with httpx.AsyncClient(
            timeout=storage_http_timeout(),
            limits=storage_http_limits(),
        ) as client:
            try:
                response = await client.post(
                    request_url,
                    json=payload,
                    headers={
                        "apikey": service_role_key,
                        "Authorization": f"Bearer {service_role_key}",
                        "Content-Type": "application/json",
                    },
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                logger.warning(
                    "Supabase Storage presigned URL request failed bucket=%s path=%s error=%s",
                    self._bucket,
                    normalized_path,
                    exc,
                )
                raise StorageServiceError("Failed to call Supabase Storage") from exc
        logger.info(
            "Supabase Storage presigned URL request completed bucket=%s path=%s status=%s",
            self._bucket,
            normalized_path,
            response.status_code,
        )

        if response.status_code >= 400:
            error = None
            message = None
            try:
                payload = response.json()
            except ValueError:
                payload = None
            if isinstance(payload, dict):
                error = payload.get("error")
                message = payload.get("message")
            if (
                response.status_code == 400
                and str(error or "") == "not_found"
                and str(message or "") == "Object not found"
            ):
                raise StorageObjectNotFoundError(
                    "Supabase Storage object not found",
                    status_code=response.status_code,
                    error=str(error),
                )
            raise StorageServiceError(
                f"Supabase Storage signing failed with status {response.status_code}",
                status_code=response.status_code,
                error=str(error) if error is not None else None,
            )

        data = response.json()
        signed_path = data.get("signedURL")
        if not signed_path:
            raise StorageServiceError("signedURL missing in Supabase response")

        if download:
            connector = "&" if "?" in signed_path else "?"
            quoted_download = quote(download_name, safe="")
            signed_path = f"{signed_path}{connector}download={quoted_download}"
            headers = {"Content-Disposition": build_content_disposition(download_name)}
        else:
            headers = {}
        if signed_path.startswith("/object/"):
            absolute_url = f"{base_url}/storage/v1{signed_path}"
        elif signed_path.startswith("/"):
            absolute_url = f"{base_url}{signed_path}"
        else:
            absolute_url = signed_path
        return PresignedUrl(url=absolute_url, expires_in=expires_in, headers=headers)

    async def inspect_object(self, path: str, *, ttl: int = 60) -> StorageObjectMetadata:
        if not path:
            raise StorageServiceError("storage path is required")

        normalized_path = path.lstrip("/")
        signed = await self.get_presigned_url(
            normalized_path,
            ttl=ttl,
            download=False,
        )

        async with httpx.AsyncClient(
            timeout=storage_http_timeout(),
            limits=storage_http_limits(),
        ) as client:
            try:
                response = await client.head(signed.url)
                if response.status_code in {405, 501}:
                    response = await client.get(
                        signed.url,
                        headers={"Range": "bytes=0-0"},
                    )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                logger.warning(
                    "Supabase Storage inspection failed bucket=%s path=%s error=%s",
                    self._bucket,
                    normalized_path,
                    exc,
                )
                raise StorageServiceError("Failed to inspect storage object") from exc

        logger.info(
            "Supabase Storage inspection completed bucket=%s path=%s status=%s",
            self._bucket,
            normalized_path,
            response.status_code,
        )
        if response.status_code == 404:
            raise StorageObjectNotFoundError("Supabase Storage object not found")
        if response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage inspection failed with status {response.status_code}",
                status_code=response.status_code,
            )

        return StorageObjectMetadata(
            path=normalized_path,
            content_type=_normalize_content_type(response.headers.get("content-type")),
            size_bytes=_response_size_bytes(response),
        )

    async def create_upload_url(
        self,
        path: str,
        *,
        content_type: str | None = None,
        upsert: bool = False,
        cache_seconds: int | None = None,
    ) -> PresignedUpload:
        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = _normalize_storage_path(path)
        base_url = supabase_url.rstrip("/")
        request_url = (
            f"{base_url}/storage/v1/object/upload/sign/"
            f"{self._bucket}/{_quoted_storage_path(normalized_path)}"
        )
        headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        if upsert:
            headers["x-upsert"] = "true"

        logger.info(
            "Supabase Storage upload signing request started bucket=%s path=%s",
            self._bucket,
            normalized_path,
        )
        async with httpx.AsyncClient(
            timeout=storage_http_timeout(),
            limits=storage_http_limits(),
        ) as client:
            try:
                response = await client.post(
                    request_url,
                    json={},
                    headers=headers,
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                logger.warning(
                    "Supabase Storage upload signing request failed bucket=%s path=%s error=%s",
                    self._bucket,
                    normalized_path,
                    exc,
                )
                raise StorageServiceError("Failed to call Supabase Storage") from exc
        logger.info(
            "Supabase Storage upload signing request completed bucket=%s path=%s status=%s",
            self._bucket,
            normalized_path,
            response.status_code,
        )

        if response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage upload signing failed with status {response.status_code}"
            )

        data = response.json()
        relative_url = data.get("url") or data.get("signedUrl")
        if not relative_url:
            raise StorageServiceError("signed upload URL missing in Supabase response")
        if relative_url.startswith("/object/"):
            absolute_url = f"{base_url}/storage/v1{relative_url}"
        elif relative_url.startswith("/"):
            absolute_url = f"{base_url}{relative_url}"
        else:
            absolute_url = relative_url
        resolved_cache = cache_seconds or settings.media_public_cache_seconds or 3600
        resolved_cache = max(60, int(resolved_cache))
        normalized_type = content_type or "application/octet-stream"
        upload_headers = {
            "x-upsert": "true" if upsert else "false",
            "cache-control": f"max-age={resolved_cache}",
            "content-type": normalized_type,
        }
        # Supabase signed upload URLs currently expire after 2 hours.
        return PresignedUpload(
            url=absolute_url,
            headers=upload_headers,
            path=normalized_path,
            expires_in=7200,
        )

    async def upload_object(
        self,
        path: str,
        *,
        content: bytes | AsyncIterable[bytes],
        content_type: str | None = None,
        upsert: bool = False,
        cache_seconds: int | None = None,
    ) -> PresignedUpload:
        """Upload bytes to storage through a server-owned signed upload."""

        upload = await self.create_upload_url(
            path,
            content_type=content_type,
            upsert=upsert,
            cache_seconds=cache_seconds,
        )
        logger.info(
            "Supabase Storage upload request started bucket=%s path=%s url=%s",
            self._bucket,
            upload.path,
            redact_http_url(upload.url),
        )
        async with httpx.AsyncClient(
            timeout=storage_http_timeout(),
            limits=storage_http_limits(),
        ) as client:
            try:
                response = await client.put(
                    upload.url,
                    headers=dict(upload.headers),
                    content=content,
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                logger.warning(
                    "Supabase Storage upload request failed bucket=%s path=%s url=%s error=%s",
                    self._bucket,
                    upload.path,
                    redact_http_url(upload.url),
                    exc,
                )
                raise StorageServiceError("Failed to upload storage object") from exc
        logger.info(
            "Supabase Storage upload request completed bucket=%s path=%s status=%s",
            self._bucket,
            upload.path,
            response.status_code,
        )

        if response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage upload failed with status {response.status_code}",
                status_code=response.status_code,
            )
        return upload

    async def delete_object(self, path: str) -> bool:
        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = _normalize_storage_path(path)
        base_url = supabase_url.rstrip("/")
        quoted_path = _quoted_storage_path(normalized_path)
        request_url = f"{base_url}/storage/v1/object/{self._bucket}/{quoted_path}"

        logger.info(
            "Supabase Storage delete request started bucket=%s path=%s",
            self._bucket,
            normalized_path,
        )
        async with httpx.AsyncClient(
            timeout=storage_http_timeout(),
            limits=storage_http_limits(),
        ) as client:
            try:
                response = await client.delete(
                    request_url,
                    headers={
                        "apikey": service_role_key,
                        "Authorization": f"Bearer {service_role_key}",
                    },
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                logger.warning(
                    "Supabase Storage delete request failed bucket=%s path=%s error=%s",
                    self._bucket,
                    normalized_path,
                    exc,
                )
                raise StorageServiceError("Failed to call Supabase Storage") from exc
        logger.info(
            "Supabase Storage delete request completed bucket=%s path=%s status=%s",
            self._bucket,
            normalized_path,
            response.status_code,
        )

        if response.status_code in {200, 204}:
            return True
        if response.status_code == 404:
            return False
        if response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage delete failed with status {response.status_code}"
            )
        return True


_storage_services: dict[str, StorageService] = {}


def canonical_source_bucket_for_media_asset(media_asset: Mapping[str, Any]) -> str:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    if purpose == "profile_media":
        return settings.media_profile_bucket
    return settings.media_source_bucket


def canonical_upload_bucket_for_media_asset(media_asset: Mapping[str, Any]) -> str:
    purpose = str(media_asset.get("purpose") or "").strip().lower()
    media_type = str(media_asset.get("media_type") or "").strip().lower()
    if purpose == "profile_media":
        return settings.media_profile_bucket
    if purpose == "lesson_media" and media_type == "image":
        return settings.media_public_bucket
    return settings.media_source_bucket


def get_storage_service(bucket: str | None) -> StorageService:
    normalized = (bucket or "").strip() or settings.media_source_bucket
    service = _storage_services.get(normalized)
    if service is None:
        service = StorageService(bucket=normalized)
        _storage_services[normalized] = service
    return service


storage_service = get_storage_service(settings.media_source_bucket)
public_storage_service = get_storage_service(settings.media_public_bucket)


async def copy_object(
    *,
    source_bucket: str,
    source_path: str,
    destination_bucket: str,
    destination_path: str,
    content_type: str | None = None,
    cache_seconds: int | None = None,
) -> None:
    normalized_source_bucket = str(source_bucket or "").strip()
    normalized_source_path = str(source_path or "").strip().lstrip("/")
    normalized_destination_bucket = str(destination_bucket or "").strip()
    normalized_destination_path = str(destination_path or "").strip().lstrip("/")
    if not normalized_source_bucket or not normalized_source_path:
        raise StorageServiceError("source storage reference is required")
    if not normalized_destination_bucket or not normalized_destination_path:
        raise StorageServiceError("destination storage reference is required")

    source_storage = get_storage_service(normalized_source_bucket)
    destination_storage = get_storage_service(normalized_destination_bucket)
    signed_source = await source_storage.get_presigned_url(
        normalized_source_path,
        ttl=max(60, int(settings.media_playback_url_ttl_seconds)),
        download=False,
    )
    signed_destination = await destination_storage.create_upload_url(
        normalized_destination_path,
        content_type=content_type,
        upsert=False,
        cache_seconds=cache_seconds,
    )

    async with httpx.AsyncClient(
        timeout=storage_http_timeout(),
        limits=storage_http_limits(),
    ) as client:
        logger.info(
            "Supabase Storage copy download request started source_bucket=%s source_path=%s url=%s",
            normalized_source_bucket,
            normalized_source_path,
            redact_http_url(signed_source.url),
        )
        try:
            source_response = await client.get(signed_source.url)
        except httpx.HTTPError as exc:  # pragma: no cover - network failure path
            logger.warning(
                "Supabase Storage copy download request failed source_bucket=%s source_path=%s url=%s error=%s",
                normalized_source_bucket,
                normalized_source_path,
                redact_http_url(signed_source.url),
                exc,
            )
            raise StorageServiceError("Failed to download source object") from exc
        logger.info(
            "Supabase Storage copy download request completed source_bucket=%s source_path=%s status=%s bytes=%s",
            normalized_source_bucket,
            normalized_source_path,
            source_response.status_code,
            len(source_response.content or b""),
        )

        if source_response.status_code == 404:
            raise StorageObjectNotFoundError("Supabase Storage object not found")
        if source_response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage download failed with status {source_response.status_code}"
            )

        logger.info(
            "Supabase Storage copy upload request started destination_bucket=%s destination_path=%s url=%s",
            normalized_destination_bucket,
            normalized_destination_path,
            redact_http_url(signed_destination.url),
        )
        try:
            destination_response = await client.put(
                signed_destination.url,
                headers=dict(signed_destination.headers),
                content=source_response.content,
            )
        except httpx.HTTPError as exc:  # pragma: no cover - network failure path
            logger.warning(
                "Supabase Storage copy upload request failed destination_bucket=%s destination_path=%s url=%s error=%s",
                normalized_destination_bucket,
                normalized_destination_path,
                redact_http_url(signed_destination.url),
                exc,
            )
            raise StorageServiceError("Failed to upload destination object") from exc
        logger.info(
            "Supabase Storage copy upload request completed destination_bucket=%s destination_path=%s status=%s",
            normalized_destination_bucket,
            normalized_destination_path,
            destination_response.status_code,
        )

    if destination_response.status_code >= 400:
        raise StorageServiceError(
            f"Supabase Storage copy upload failed with status {destination_response.status_code}"
        )
