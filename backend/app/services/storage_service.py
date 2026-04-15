from __future__ import annotations

from collections.abc import AsyncIterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping
from urllib.parse import quote

import httpx

from ..config import settings
from ..utils.http_headers import build_content_disposition


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
        if not path:
            raise StorageServiceError("storage path is required")

        supabase_url = self._supabase_url
        if not supabase_url:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = path.lstrip("/")
        base_url = supabase_url.rstrip("/")
        return (
            f"{base_url}/storage/v1/object/public/{self._bucket}/{normalized_path}"
        )

    async def get_presigned_url(
        self,
        path: str,
        ttl: int,
        filename: str | None = None,
        *,
        download: bool = True,
    ) -> PresignedUrl:
        if not path:
            raise StorageServiceError("storage path is required")

        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = path.lstrip("/")
        expires_in = max(60, min(int(ttl), 60 * 60 * 24))
        download_name = filename or Path(normalized_path).name or "media"

        base_url = supabase_url.rstrip("/")
        request_url = (
            f"{base_url}/storage/v1/object/sign/{self._bucket}/{normalized_path}"
        )
        payload: dict[str, Any] = {"expiresIn": expires_in}

        async with httpx.AsyncClient(timeout=10.0) as client:
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
                raise StorageServiceError("Failed to call Supabase Storage") from exc

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
            headers = {
                "Content-Disposition": build_content_disposition(download_name)
            }
        else:
            headers = {}
        if signed_path.startswith("/object/"):
            absolute_url = f"{base_url}/storage/v1{signed_path}"
        elif signed_path.startswith("/"):
            absolute_url = f"{base_url}{signed_path}"
        else:
            absolute_url = signed_path
        return PresignedUrl(url=absolute_url, expires_in=expires_in, headers=headers)

    async def create_upload_url(
        self,
        path: str,
        *,
        content_type: str | None = None,
        upsert: bool = False,
        cache_seconds: int | None = None,
    ) -> PresignedUpload:
        if not path:
            raise StorageServiceError("storage path is required")

        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = path.lstrip("/")
        base_url = supabase_url.rstrip("/")
        request_url = (
            f"{base_url}/storage/v1/object/upload/sign/"
            f"{self._bucket}/{normalized_path}"
        )
        headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }
        if upsert:
            headers["x-upsert"] = "true"

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.post(
                    request_url,
                    json={},
                    headers=headers,
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                raise StorageServiceError("Failed to call Supabase Storage") from exc

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
        timeout = httpx.Timeout(15.0, read=None, write=None)
        async with httpx.AsyncClient(timeout=timeout) as client:
            try:
                response = await client.put(
                    upload.url,
                    headers=dict(upload.headers),
                    content=content,
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                raise StorageServiceError("Failed to upload storage object") from exc

        if response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage upload failed with status {response.status_code}",
                status_code=response.status_code,
            )
        return upload

    async def delete_object(self, path: str) -> bool:
        if not path:
            raise StorageServiceError("storage path is required")

        supabase_url = self._supabase_url
        service_role_key = self._service_role_key
        if not supabase_url or not service_role_key:
            raise StorageServiceError("Supabase Storage is not configured")

        normalized_path = path.lstrip("/")
        base_url = supabase_url.rstrip("/")
        quoted_path = quote(normalized_path, safe="/")
        request_url = f"{base_url}/storage/v1/object/{self._bucket}/{quoted_path}"

        async with httpx.AsyncClient(timeout=10.0) as client:
            try:
                response = await client.delete(
                    request_url,
                    headers={
                        "apikey": service_role_key,
                        "Authorization": f"Bearer {service_role_key}",
                    },
                )
            except httpx.HTTPError as exc:  # pragma: no cover - network failure path
                raise StorageServiceError("Failed to call Supabase Storage") from exc

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

    timeout = httpx.Timeout(10.0, read=None)
    async with httpx.AsyncClient(timeout=timeout) as client:
        try:
            source_response = await client.get(signed_source.url)
        except httpx.HTTPError as exc:  # pragma: no cover - network failure path
            raise StorageServiceError("Failed to download source object") from exc

        if source_response.status_code == 404:
            raise StorageObjectNotFoundError("Supabase Storage object not found")
        if source_response.status_code >= 400:
            raise StorageServiceError(
                f"Supabase Storage download failed with status {source_response.status_code}"
            )

        try:
            destination_response = await client.put(
                signed_destination.url,
                headers=dict(signed_destination.headers),
                content=source_response.content,
            )
        except httpx.HTTPError as exc:  # pragma: no cover - network failure path
            raise StorageServiceError("Failed to upload destination object") from exc

    if destination_response.status_code >= 400:
        raise StorageServiceError(
            f"Supabase Storage copy upload failed with status {destination_response.status_code}"
        )
