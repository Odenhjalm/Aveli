from __future__ import annotations

import logging
from typing import Any, Mapping, TypedDict

from fastapi import HTTPException, status

from context7.runtime import Context7Object, ContextPermissionError, ContextValidationError, validate_context

logger = logging.getLogger(__name__)


class ContextGateResult(TypedDict):
    context: Context7Object
    context_hash: str


def validate_context_payload(
    context_payload: Mapping[str, Any],
    *,
    user: Mapping[str, Any],
    request_id: str | None = None,
) -> ContextGateResult:
    user_id = str(user.get("id"))
    user_role = "admin" if user.get("is_admin") else (user.get("role_v2") or "user")

    try:
        context_obj, context_hash = validate_context(
            context_payload, user_id=user_id, user_role=user_role
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
