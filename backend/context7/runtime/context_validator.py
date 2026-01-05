from __future__ import annotations

import hashlib
import json
from typing import Any, Mapping, MutableSet

from pydantic import BaseModel, ConfigDict, ValidationError, field_validator

ALLOWED_ROLES = {"teacher", "admin", "student"}
ALLOWED_EXECUTION_TOOLS = {"supabase_readonly"}
ALLOWED_EXECUTION_MODES = {"stub"}
REQUIRED_SCOPE = "ai:execute"


class ContextValidationError(Exception):
    """Raised when a Context7Object is structurally invalid."""


class ContextPermissionError(ContextValidationError):
    """Raised when a Context7Object fails permission checks."""


class Environment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    app_env: str | None = None
    backend_base_url: str | None = None


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
        cleaned = sorted({str(item).strip() for item in value if str(item).strip()})
        if not cleaned:
            raise ValueError("at least one scope is required")
        return cleaned


class ContextScope(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: str | None = None
    classroom_id: str | None = None
    seminar_id: str | None = None


class Permissions(BaseModel):
    model_config = ConfigDict(extra="forbid")

    scopes: list[str]

    @field_validator("scopes")
    @classmethod
    def ensure_scopes(cls, value: list[str]) -> list[str]:
        cleaned = sorted({str(item).strip() for item in value if str(item).strip()})
        if not cleaned:
            raise ValueError("permissions.scopes must include at least one scope")
        return cleaned


class Constraints(BaseModel):
    model_config = ConfigDict(extra="forbid")

    readonly: bool = True


class ExecutionPolicy(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: str
    tools_allowed: list[str] = []
    write_allowed: bool = False
    max_steps: int
    max_seconds: int
    redact_logs: bool = True

    @field_validator("mode")
    @classmethod
    def normalize_mode(cls, value: str) -> str:
        normalized = value.strip().lower()
        if not normalized:
            raise ValueError("execution_policy.mode cannot be empty")
        if normalized not in ALLOWED_EXECUTION_MODES:
            raise ValueError(f"execution_policy.mode '{normalized}' is not allowed")
        return normalized

    @field_validator("tools_allowed")
    @classmethod
    def validate_tools(cls, value: list[str]) -> list[str]:
        cleaned = sorted({str(item).strip() for item in value if str(item).strip()})
        for tool in cleaned:
            if tool not in ALLOWED_EXECUTION_TOOLS:
                raise ValueError(
                    f"execution_policy.tools_allowed contains unsupported tool '{tool}'"
                )
        return cleaned

    @field_validator("max_steps")
    @classmethod
    def validate_max_steps(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("execution_policy.max_steps must be positive")
        return value

    @field_validator("max_seconds")
    @classmethod
    def validate_max_seconds(cls, value: int) -> int:
        if value <= 0:
            raise ValueError("execution_policy.max_seconds must be positive")
        return value


class Context7Object(BaseModel):
    model_config = ConfigDict(extra="forbid")

    context_version: str
    schema_version: str
    build_timestamp: str | None = None
    environment: Environment | None = None
    actor: Actor
    scope: ContextScope | None = None
    permissions: Permissions | None = None
    constraints: Constraints | None = None
    execution_policy: ExecutionPolicy

    def compute_hash(self) -> str:
        payload = self.model_dump(mode="json", exclude_none=True)
        raw = json.dumps(payload, sort_keys=True, separators=(',', ':')).encode("utf-8")
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
    required_scope: str | None = REQUIRED_SCOPE,
    allowed_roles: MutableSet[str] | None = None,
) -> tuple[Context7Object, str]:
    allowed = {_normalize_role(role) for role in (allowed_roles or ALLOWED_ROLES)}
    try:
        ctx = Context7Object.model_validate(payload)
    except ValidationError as exc:  # pragma: no cover - rewrapped below
        raise ContextValidationError(_format_validation_error(exc)) from exc

    actor_role = _normalize_role(ctx.actor.role)
    user_role_normalized = _normalize_role(user_role)

    if actor_role not in allowed:
        raise ContextPermissionError(
            "Context actor.role is not permitted for AI execution"
        )
    if user_role_normalized not in allowed:
        raise ContextPermissionError("Authenticated user is not permitted for AI execution")
    if ctx.actor.id != user_id:
        raise ContextPermissionError("Context actor.id does not match authenticated user")
    if actor_role != user_role_normalized:
        raise ContextPermissionError("Context actor.role does not match authenticated user")

    if ctx.execution_policy.write_allowed and actor_role != "admin":
        raise ContextPermissionError("execution_policy.write_allowed requires admin role")

    if required_scope:
        if required_scope not in ctx.actor.scopes:
            raise ContextPermissionError(f"Required scope '{required_scope}' is missing")

    context_hash = ctx.compute_hash()
    return ctx, context_hash


__all__ = [
    "Context7Object",
    "ContextPermissionError",
    "ContextValidationError",
    "ExecutionPolicy",
    "validate_context",
    "ALLOWED_EXECUTION_TOOLS",
    "ALLOWED_EXECUTION_MODES",
]
