from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping

from pydantic import BaseModel, ConfigDict, ValidationError, field_validator

_ALLOWED_ROLES = {"teacher", "admin"}
_REQUIRED_SCOPE = "ai:execute"


class ContextValidationError(Exception):
    """Raised when a Context7Object is structurally invalid."""


class ContextPermissionError(ContextValidationError):
    """Raised when a Context7Object fails permission checks."""


class Actor(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    role: str
    scopes: list[str]

    @field_validator("role")
    @classmethod
    def normalize_role(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized:
            raise ValueError("role cannot be empty")
        return normalized

    @field_validator("scopes")
    @classmethod
    def ensure_scopes(cls, value: list[str]) -> list[str]:
        cleaned = [str(item).strip() for item in value if str(item).strip()]
        if not cleaned:
            raise ValueError("at least one scope is required")
        return cleaned


class Context7Object(BaseModel):
    model_config = ConfigDict(extra="forbid")

    context_version: str
    schema_version: str
    actor: Actor

    def compute_hash(self) -> str:
        payload = self.model_dump(mode="json")
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode(
            "utf-8"
        )
        return hashlib.sha256(raw).hexdigest()

    def actor_summary(self) -> str:
        scopes = ",".join(sorted(set(self.actor.scopes)))
        return f"{self.actor.role}:{self.actor.id};scopes={scopes}"


def _format_validation_error(exc: ValidationError) -> str:
    parts: list[str] = []
    for error in exc.errors():
        loc = ".".join(str(segment) for segment in error.get("loc", ()))
        message = error.get("msg", "Invalid input")
        parts.append(f"{loc or 'context'}: {message}")
    return "; ".join(parts) or "Invalid Context7 payload"


def _normalize_role(role: str) -> str:
    return (role or "").strip().lower()


def validate_context(
    payload: Mapping[str, Any],
    *,
    user_id: str,
    user_role: str,
    required_scope: str = _REQUIRED_SCOPE,
) -> tuple[Context7Object, str]:
    try:
        ctx = Context7Object.model_validate(payload)
    except ValidationError as exc:  # pragma: no cover - rewrapped below
        raise ContextValidationError(_format_validation_error(exc)) from exc

    expected_role = "admin" if _normalize_role(user_role) == "admin" else "teacher"
    actor_role = _normalize_role(ctx.actor.role)
    if actor_role not in _ALLOWED_ROLES:
        raise ContextPermissionError(
            "Context actor.role is not permitted for AI execution"
        )
    if _normalize_role(user_role) not in _ALLOWED_ROLES:
        raise ContextPermissionError("Authenticated user is not permitted for AI execution")
    if ctx.actor.id != user_id:
        raise ContextPermissionError("Context actor.id does not match authenticated user")
    if actor_role != expected_role:
        raise ContextPermissionError("Context actor.role does not match authenticated user")
    if required_scope not in ctx.actor.scopes:
        raise ContextPermissionError(f"Required scope '{required_scope}' is missing")

    context_hash = ctx.compute_hash()
    return ctx, context_hash


__all__ = [
    "Context7Object",
    "ContextPermissionError",
    "ContextValidationError",
    "validate_context",
]
