from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Protocol

import httpx
from jose import jwt

from ..config import Settings, settings

_FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_JWT_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:jwt-bearer"


class PushProviderError(RuntimeError):
    """Raised when a push provider rejects or cannot send a message."""


class PushProviderConfigurationError(PushProviderError):
    """Raised when push delivery is requested without provider credentials."""


@dataclass(frozen=True)
class PushMessage:
    title: str
    body: str
    data: Mapping[str, str]


class PushProvider(Protocol):
    async def send(self, *, token: str, message: PushMessage) -> str | None:
        """Send a push message and return the provider message id when present."""


class FirebasePushProvider:
    def __init__(
        self,
        *,
        project_id: str,
        client_email: str,
        private_key: str,
        token_url: str,
        api_base_url: str,
        timeout_seconds: float,
    ) -> None:
        self._project_id = project_id
        self._client_email = client_email
        self._private_key = private_key
        self._token_url = token_url
        self._api_base_url = api_base_url.rstrip("/")
        self._timeout = httpx.Timeout(timeout_seconds)
        self._access_token: str | None = None
        self._access_token_expires_at = 0.0

    @classmethod
    def from_settings(cls, active_settings: Settings) -> "FirebasePushProvider":
        service_account = _load_service_account(active_settings)
        project_id = (
            active_settings.firebase_project_id
            or service_account.get("project_id")
            or ""
        ).strip()
        client_email = str(service_account.get("client_email") or "").strip()
        private_key = str(service_account.get("private_key") or "").strip()
        if not project_id or not client_email or not private_key:
            raise PushProviderConfigurationError(
                "Firebase push delivery requires project_id, client_email, and private_key"
            )
        return cls(
            project_id=project_id,
            client_email=client_email,
            private_key=private_key,
            token_url=active_settings.fcm_oauth_token_url,
            api_base_url=active_settings.fcm_api_base_url,
            timeout_seconds=active_settings.fcm_request_timeout_seconds,
        )

    async def _bearer_token(self) -> str:
        now = int(time.time())
        if self._access_token and time.time() < self._access_token_expires_at:
            return self._access_token

        claims = {
            "iss": self._client_email,
            "scope": _FCM_SCOPE,
            "aud": self._token_url,
            "iat": now,
            "exp": now + 3600,
        }
        assertion = jwt.encode(claims, self._private_key, algorithm="RS256")
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                self._token_url,
                data={"grant_type": _JWT_GRANT_TYPE, "assertion": assertion},
            )
        if response.status_code >= 400:
            raise PushProviderError(
                f"Firebase OAuth token request failed with status {response.status_code}"
            )
        payload = response.json()
        token = str(payload.get("access_token") or "").strip()
        if not token:
            raise PushProviderError("Firebase OAuth token response missing access_token")
        expires_in = int(payload.get("expires_in") or 3600)
        self._access_token = token
        self._access_token_expires_at = time.time() + max(60, expires_in - 60)
        return token

    async def send(self, *, token: str, message: PushMessage) -> str | None:
        normalized_token = str(token or "").strip()
        if not normalized_token:
            raise PushProviderError("push token is required")

        bearer_token = await self._bearer_token()
        data = {key: str(value) for key, value in message.data.items()}
        payload = {
            "message": {
                "token": normalized_token,
                "notification": {
                    "title": message.title,
                    "body": message.body,
                },
                "data": data,
            }
        }
        url = f"{self._api_base_url}/v1/projects/{self._project_id}/messages:send"
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                url,
                headers={"Authorization": f"Bearer {bearer_token}"},
                json=payload,
            )
        if response.status_code >= 400:
            raise PushProviderError(
                f"Firebase push send failed with status {response.status_code}"
            )
        provider_payload = response.json()
        name = provider_payload.get("name")
        return str(name) if name else None


def _load_service_account(active_settings: Settings) -> dict[str, Any]:
    raw_json = active_settings.firebase_service_account_json
    if raw_json:
        try:
            payload = json.loads(raw_json)
        except json.JSONDecodeError as exc:
            raise PushProviderConfigurationError(
                "Firebase service account JSON is invalid"
            ) from exc
        if isinstance(payload, dict):
            return payload
        raise PushProviderConfigurationError(
            "Firebase service account JSON must be an object"
        )

    raw_path = active_settings.firebase_service_account_file
    if raw_path:
        path = Path(raw_path).expanduser()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise PushProviderConfigurationError(
                f"Firebase service account file cannot be read: {path}"
            ) from exc
        except json.JSONDecodeError as exc:
            raise PushProviderConfigurationError(
                f"Firebase service account file is invalid JSON: {path}"
            ) from exc
        if isinstance(payload, dict):
            return payload
        raise PushProviderConfigurationError(
            f"Firebase service account file must contain a JSON object: {path}"
        )

    raise PushProviderConfigurationError(
        "Firebase push delivery requires FIREBASE_SERVICE_ACCOUNT_JSON or "
        "FIREBASE_SERVICE_ACCOUNT_FILE"
    )


_provider: PushProvider | None = None


def get_push_provider() -> PushProvider:
    global _provider
    if _provider is None:
        _provider = FirebasePushProvider.from_settings(settings)
    return _provider


def set_push_provider_for_tests(provider: PushProvider | None) -> None:
    global _provider
    _provider = provider


__all__ = [
    "FirebasePushProvider",
    "PushMessage",
    "PushProvider",
    "PushProviderConfigurationError",
    "PushProviderError",
    "get_push_provider",
    "set_push_provider_for_tests",
]
