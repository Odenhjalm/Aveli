from __future__ import annotations

import logging
from typing import Any, Mapping, TypedDict

from fastapi import HTTPException, status

from context7.runtime import Context7Object, ContextPermissionError, ContextValidationError, validate_context

logger = logging.getLogger(__name__)

DEFAULT_REQUIRED_SCOPE = "ai:execute"


class ContextGateResult(TypedDict):
    context: Context7Object
    context_hash: str


def _normalize_role(value: str | None) -> str:
    return (value or "").strip().lower()


def _actor_role_from_payload(context_payload: Mapping[str, Any] | None) -> str | None:
    if not context_payload:
        return None
    actor = context_payload.get("actor") if isinstance(context_payload, Mapping) else None
    if isinstance(actor, Mapping):
        normalized = _normalize_role(actor.get("role"))
        return normalized or None
    return None


def _user_role(user: Mapping[str, Any], context_payload: Mapping[str, Any] | None) -> str:
    actor_role = _actor_role_from_payload(context_payload)
    if user.get("is_admin"):
        return "admin"

    role_v2 = _normalize_role(user.get("role_v2")) or "user"
    if role_v2 == "user" and actor_role:
        return actor_role
    return role_v2


def validate_context_payload(
    context_payload: Mapping[str, Any],
    *,
    user: Mapping[str, Any],
    request_id: str | None = None,
    required_scope: str | None = None,
    allowed_roles: set[str] | None = None,
) -> ContextGateResult:
    user_id = str(user.get("id"))
    user_role = _user_role(user, context_payload)
    scope_requirement = required_scope if required_scope is not None else DEFAULT_REQUIRED_SCOPE

    try:
        context_obj, context_hash = validate_context(
            context_payload,
            user_id=user_id,
            user_role=user_role,
            required_scope=scope_requirement,
            allowed_roles=allowed_roles,
        )
    except ContextPermissionError as exc:
        logger.warning(
            "Context7 permission rejected",
            extra={
                "request_id": request_id,
                "user_id": user_id,
                "reason": str(exc),
            },
        )
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(exc)) from exc
    except ContextValidationError as exc:
        logger.warning(
            "Context7 validation failed",
            extra={
                "request_id": request_id,
                "user_id": user_id,
                "reason": str(exc),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    logger.info(
        "Context7 validated",
        extra={
            "request_id": request_id,
            "user_id": user_id,
            "context_hash": context_hash,
            "actor": context_obj.actor_summary(),
        },
    )
    return {"context": context_obj, "context_hash": context_hash}


__all__ = ["validate_context_payload", "ContextGateResult"]
