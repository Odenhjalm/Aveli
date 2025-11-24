from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, status

from .. import schemas
from ..permissions import TeacherUser
from ..services import booking_service

router = APIRouter(prefix="/studio/sessions", tags=["studio-sessions"])


@router.get("", response_model=schemas.SessionListResponse)
async def list_teacher_sessions(
    current: TeacherUser,
    visibility: schemas.SessionVisibility | None = None,
):
    visibility_value = visibility.value if visibility else None
    rows = await booking_service.list_sessions_for_teacher(
        current["id"],
        visibility=visibility_value,
    )
    items = [schemas.SessionResponse(**row) for row in rows]
    return schemas.SessionListResponse(items=items)


@router.post("", response_model=schemas.SessionResponse, status_code=status.HTTP_201_CREATED)
async def create_session(
    payload: schemas.SessionCreateRequest,
    current: TeacherUser,
):
    session = await booking_service.create_teacher_session(current["id"], payload)
    return schemas.SessionResponse(**session)


@router.put("/{session_id}", response_model=schemas.SessionResponse)
async def update_session(
    session_id: UUID,
    payload: schemas.SessionUpdateRequest,
    current: TeacherUser,
):
    session = await booking_service.update_teacher_session(
        session_id,
        teacher_id=current["id"],
        payload=payload,
    )
    return schemas.SessionResponse(**session)


@router.delete("/{session_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_session(session_id: UUID, current: TeacherUser):
    await booking_service.delete_session(session_id, teacher_id=current["id"])
    return None


@router.get("/{session_id}/slots", response_model=schemas.SessionSlotListResponse)
async def list_session_slots(session_id: UUID, current: TeacherUser):
    rows = await booking_service.list_slots_for_session(
        session_id,
        teacher_id=current["id"],
    )
    items = [schemas.SessionSlotResponse(**row) for row in rows]
    return schemas.SessionSlotListResponse(items=items)


@router.post(
    "/{session_id}/slots",
    response_model=schemas.SessionSlotResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_session_slot(
    session_id: UUID,
    payload: schemas.SessionSlotCreateRequest,
    current: TeacherUser,
):
    slot = await booking_service.create_session_slot(
        session_id=session_id,
        teacher_id=current["id"],
        payload=payload,
    )
    return schemas.SessionSlotResponse(**slot)


@router.patch(
    "/{session_id}/slots/{slot_id}",
    response_model=schemas.SessionSlotResponse,
)
async def update_session_slot(
    session_id: UUID,
    slot_id: UUID,
    payload: schemas.SessionSlotUpdateRequest,
    current: TeacherUser,
):
    slot = await booking_service.update_session_slot(
        slot_id=slot_id,
        session_id=session_id,
        teacher_id=current["id"],
        payload=payload,
    )
    return schemas.SessionSlotResponse(**slot)
