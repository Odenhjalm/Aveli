from __future__ import annotations

import logging
import uuid
from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, ValidationError

from ..auth import CurrentUser
from ..permissions import TeacherUser
from ..services import context7_builder, context7_gate

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/ai", tags=["ai"])


class AIExecuteRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    context: dict[str, Any] | None = None
    input: str


class AIExecuteResponse(BaseModel):
    ok: bool
    context_hash: str
    context_version: str
    schema_version: str


class AIExecuteBuiltRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input: str
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None


class BuiltFrom(BaseModel):
    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None


class AIExecuteBuiltResponse(BaseModel):
    ok: bool
    context_hash: str
    context_version: str
    schema_version: str
    built_from: BuiltFrom


def _request_id(request: Request) -> str:
    return (
        getattr(request.state, "request_id", None)
        or request.headers.get("X-Request-ID")
        or uuid.uuid4().hex
    )


@router.post("/execute", response_model=AIExecuteResponse)
async def execute_ai(  # type: ignore[valid-type]
    payload: AIExecuteRequest,
    request: Request,
    current: TeacherUser,
):
    request_id = _request_id(request)

    if not payload.context:
        logger.warning(
            "Context7 payload missing",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="context is required"
        )

    result = context7_gate.validate_context_payload(
        payload.context,
        user=current,
        request_id=request_id,
    )

    context_obj = result["context"]
    return AIExecuteResponse(
        ok=True,
        context_hash=result["context_hash"],
        context_version=context_obj.context_version,
        schema_version=context_obj.schema_version,
    )


@router.post("/execute-built", response_model=AIExecuteBuiltResponse)
async def execute_ai_with_built_context(request: Request, current: CurrentUser):
    request_id = _request_id(request)
    try:
        raw_payload = await request.json()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        logger.warning(
            "Context7 execute-built invalid JSON",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid JSON payload"
        ) from exc

    try:
        payload = AIExecuteBuiltRequest.model_validate(raw_payload)
    except ValidationError as exc:
        logger.warning(
            "Context7 execute-built payload rejected",
            extra={
                "request_id": request_id,
                "user_id": str(current.get("id")),
                "errors": exc.errors(),
            },
        )
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=exc.errors()) from exc

    try:
        built_context, _ = await context7_builder.build_context(
            course_id=str(payload.course_id) if payload.course_id else None,
            classroom_id=str(payload.classroom_id) if payload.classroom_id else None,
            seminar_id=str(payload.seminar_id) if payload.seminar_id else None,
            user=current,
        )
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - unexpected
        logger.exception(
            "Context7 execute-built failed",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail="Failed to build context") from exc

    context_payload = built_context.model_dump(mode="json", exclude_none=True)
    gate_result = context7_gate.validate_context_payload(
        context_payload,
        user=current,
        request_id=request_id,
        required_scope="ai:execute",
        allowed_roles={"admin", "teacher", "student"},
    )

    context_obj = gate_result["context"]
    context_hash = gate_result["context_hash"]
    scope_payload = context_payload.get("scope") if isinstance(context_payload.get("scope"), dict) else {}

    logger.info(
        "Context7 execute-built validated",
        extra={
            "request_id": request_id,
            "user_id": str(current.get("id")),
            "actor_role": getattr(context_obj.actor, "role", None),
            "course_id": scope_payload.get("course_id") if scope_payload else None,
            "classroom_id": scope_payload.get("classroom_id") if scope_payload else None,
            "seminar_id": scope_payload.get("seminar_id") if scope_payload else None,
            "context_hash": context_hash,
        },
    )

    return AIExecuteBuiltResponse(
        ok=True,
        context_hash=context_hash,
        context_version=context_obj.context_version,
        schema_version=context_obj.schema_version,
        built_from=BuiltFrom(
            course_id=payload.course_id,
            classroom_id=payload.classroom_id,
            seminar_id=payload.seminar_id,
        ),
    )
