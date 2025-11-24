from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query, status

from .. import schemas
from ..services import booking_service

router = APIRouter(prefix="/sessions", tags=["sessions"])


@router.get("", response_model=schemas.SessionListResponse)
async def list_public_sessions(
    from_time: datetime | None = Query(
        None,
        description="Return sessions starting at/after this timestamp",
    ),
    limit: int = Query(50, ge=1, le=200),
):
    rows = await booking_service.list_public_sessions(
        from_time=from_time,
        limit=limit,
    )
    items = [schemas.SessionResponse(**row) for row in rows]
    return schemas.SessionListResponse(items=items)


@router.get("/{session_id}", response_model=schemas.SessionResponse)
async def get_session(session_id: UUID):
    session = await booking_service.get_session(session_id)
    if not session or session.get("visibility") != "published":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )
    return schemas.SessionResponse(**session)


@router.get("/{session_id}/slots", response_model=schemas.SessionSlotListResponse)
async def list_public_slots(session_id: UUID):
    session = await booking_service.get_session(session_id)
    if not session or session.get("visibility") != "published":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )
    rows = await booking_service.list_slots_for_session(session_id)
    items = [schemas.SessionSlotResponse(**row) for row in rows]
    return schemas.SessionSlotListResponse(items=items)
