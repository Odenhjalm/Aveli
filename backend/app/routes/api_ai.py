from __future__ import annotations

import logging
import uuid
from typing import Any

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict

from ..permissions import TeacherUser
from ..services import context7_gate

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


@router.post("/execute", response_model=AIExecuteResponse)
async def execute_ai(  # type: ignore[valid-type]
    payload: AIExecuteRequest,
    request: Request,
    current: TeacherUser,
):
    request_id = (
        getattr(request.state, "request_id", None)
        or request.headers.get("X-Request-ID")
        or uuid.uuid4().hex
    )

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
