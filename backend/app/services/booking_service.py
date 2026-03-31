from __future__ import annotations

from datetime import datetime
from typing import Any
from uuid import UUID

from fastapi import HTTPException, status

from .. import repositories, schemas


def _validate_time_range(start_at: datetime | None, end_at: datetime | None) -> None:
    if start_at and end_at and end_at <= start_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="end_at must be later than start_at",
        )


async def _ensure_session_owner(
    session_id: str | UUID,
    teacher_id: str | UUID,
) -> dict[str, Any]:
    session = await repositories.get_session(session_id)
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )
    if str(session.get("teacher_id")) != str(teacher_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="Not session owner"
        )
    return session


async def create_teacher_session(
    teacher_id: str | UUID,
    payload: schemas.SessionCreateRequest,
) -> dict[str, Any]:
    _validate_time_range(payload.start_at, payload.end_at)
    return await repositories.create_session(
        teacher_id=teacher_id,
        title=payload.title,
        description=payload.description,
        start_at=payload.start_at,
        end_at=payload.end_at,
        capacity=payload.capacity,
        price_cents=payload.price_cents,
        currency=payload.currency,
        visibility=payload.visibility.value,
        recording_url=payload.recording_url,
        stripe_price_id=payload.stripe_price_id,
    )


async def update_teacher_session(
    session_id: str | UUID,
    *,
    teacher_id: str | UUID,
    payload: schemas.SessionUpdateRequest,
) -> dict[str, Any]:
    fields = payload.model_dump(exclude_unset=True)
    session = await _ensure_session_owner(session_id, teacher_id)
    if not fields:
        return session

    if "start_at" in fields or "end_at" in fields:
        start_at = (
            fields["start_at"] if "start_at" in fields else session.get("start_at")
        )
        end_at = fields["end_at"] if "end_at" in fields else session.get("end_at")
        _validate_time_range(
            start_at,
            end_at,
        )

    visibility_value = fields.get("visibility")
    if visibility_value:
        fields["visibility"] = visibility_value.value

    session = await repositories.update_session(
        session_id,
        teacher_id=teacher_id,
        fields=fields,
    )
    if not session:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )
    return session


async def list_sessions_for_teacher(
    teacher_id: str | UUID,
    *,
    visibility: str | None = None,
) -> list[dict[str, Any]]:
    return await repositories.list_teacher_sessions(
        teacher_id,
        visibility=visibility,
    )


async def list_public_sessions(
    *,
    from_time: datetime | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    if limit <= 0 or limit > 200:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="limit must be between 1 and 200",
        )
    return await repositories.list_published_sessions(
        from_time=from_time,
        limit=limit,
    )


async def delete_session(
    session_id: str | UUID,
    *,
    teacher_id: str | UUID,
) -> None:
    deleted = await repositories.delete_session(session_id, teacher_id=teacher_id)
    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Session not found"
        )


async def create_session_slot(
    *,
    session_id: str | UUID,
    teacher_id: str | UUID,
    payload: schemas.SessionSlotCreateRequest,
) -> dict[str, Any]:
    await _ensure_session_owner(session_id, teacher_id)
    if payload.end_at <= payload.start_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Slot end_at must be later than start_at",
        )
    return await repositories.create_session_slot(
        session_id=session_id,
        start_at=payload.start_at,
        end_at=payload.end_at,
        seats_total=payload.seats_total,
    )


async def update_session_slot(
    *,
    slot_id: str | UUID,
    session_id: str | UUID,
    teacher_id: str | UUID,
    payload: schemas.SessionSlotUpdateRequest,
) -> dict[str, Any]:
    await _ensure_session_owner(session_id, teacher_id)
    fields = payload.model_dump(exclude_unset=True)
    if "start_at" in fields or "end_at" in fields:
        start_at = fields.get("start_at")
        end_at = fields.get("end_at")
        slot = await repositories.get_session_slot(slot_id)
        if not slot:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Slot not found"
            )
        start_at = start_at or slot.get("start_at")
        end_at = end_at or slot.get("end_at")
        if end_at <= start_at:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Slot end_at must be later than start_at",
            )
    slot = await repositories.update_session_slot(
        slot_id,
        session_id=session_id,
        fields=fields,
    )
    if not slot:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Slot not found"
        )
    return slot


async def list_slots_for_session(
    session_id: str | UUID,
    *,
    teacher_id: str | UUID | None = None,
) -> list[dict[str, Any]]:
    if teacher_id:
        await _ensure_session_owner(session_id, teacher_id)
    return await repositories.list_session_slots(session_id)


async def get_session(session_id: str | UUID) -> dict[str, Any] | None:
    return await repositories.get_session(session_id)


async def get_session_slot(slot_id: str | UUID) -> dict[str, Any] | None:
    return await repositories.get_session_slot(slot_id)
