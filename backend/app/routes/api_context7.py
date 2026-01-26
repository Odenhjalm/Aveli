from __future__ import annotations

import logging
from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict

from ..auth import CurrentUser
from ..services import context7_builder

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/context7", tags=["context7"])


class ContextBuildRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_id: UUID | None = None
    classroom_id: UUID | None = None
    seminar_id: UUID | None = None


class ContextBuildResponse(BaseModel):
    context: dict[str, Any]
    context_hash: str
    context_version: str
    schema_version: str


@router.post("/build", response_model=ContextBuildResponse)
async def build_context(payload: ContextBuildRequest, request: Request, current: CurrentUser):
    request_id = getattr(request.state, "request_id", None)
    try:
        ctx, context_hash = await context7_builder.build_context(
            course_id=str(payload.course_id) if payload.course_id else None,
            classroom_id=str(payload.classroom_id) if payload.classroom_id else None,
            seminar_id=str(payload.seminar_id) if payload.seminar_id else None,
            user=current,
        )
    except HTTPException:
        raise
    except Exception as exc:  # pragma: no cover - unexpected
        logger.exception(
            "Context7 build failed",
            extra={"request_id": request_id, "user_id": str(current.get("id"))},
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build context",
        ) from exc

    context_dict = ctx.model_dump(mode="json", exclude_none=True)
    return ContextBuildResponse(
        context=context_dict,
        context_hash=context_hash,
        context_version=ctx.context_version,
        schema_version=ctx.schema_version,
    )
