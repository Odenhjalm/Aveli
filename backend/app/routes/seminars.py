from typing import Any, Dict
from uuid import UUID

from fastapi import APIRouter, HTTPException, status

from .. import repositories, schemas
from ..auth import CurrentUser

router = APIRouter(prefix="/seminars", tags=["seminars"])


def _normalize_metadata(row: Dict[str, Any], keys: tuple[str, ...]) -> Dict[str, Any]:
    normalized = dict(row)
    for key in keys:
        if normalized.get(key) is None:
            normalized[key] = {}
    return normalized


def _seminar_from_row(row: Dict[str, Any]) -> schemas.SeminarResponse:
    data = _normalize_metadata(row, ("livekit_metadata",))
    return schemas.SeminarResponse(**data)


def _session_from_row(row: Dict[str, Any]) -> schemas.SeminarSessionResponse:
    data = _normalize_metadata(row, ("metadata",))
    return schemas.SeminarSessionResponse(**data)


def _attendee_from_row(row: Dict[str, Any]) -> schemas.SeminarRegistrationResponse:
    data = dict(row)
    if data.get("host_course_titles") is None:
        data["host_course_titles"] = []
    return schemas.SeminarRegistrationResponse(**data)


def _recording_from_row(row: Dict[str, Any]) -> schemas.SeminarRecordingResponse:
    data = _normalize_metadata(row, ("metadata",))
    return schemas.SeminarRecordingResponse(**data)


@router.get("", response_model=schemas.SeminarListResponse)
async def list_public_seminars(limit: int = 20):
    rows = await repositories.list_public_seminars(limit=limit)
    items = [_seminar_from_row(row) for row in rows]
    return schemas.SeminarListResponse(items=items)


@router.get("/{seminar_id}", response_model=schemas.SeminarDetailResponse)
async def get_public_seminar(seminar_id: UUID):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar or seminar["status"] not in ("scheduled", "live", "ended"):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found"
        )
    sessions = await repositories.list_seminar_sessions(str(seminar_id))
    attendees = await repositories.list_seminar_attendees(str(seminar_id))
    recordings = await repositories.list_seminar_recordings(str(seminar_id))
    return schemas.SeminarDetailResponse(
        seminar=_seminar_from_row(seminar),
        sessions=[_session_from_row(row) for row in sessions],
        attendees=[_attendee_from_row(row) for row in attendees],
        recordings=[_recording_from_row(row) for row in recordings],
    )


@router.post(
    "/{seminar_id}/register",
    response_model=schemas.SeminarRegistrationResponse,
    status_code=status.HTTP_201_CREATED,
)
async def register_for_seminar(seminar_id: UUID, current: CurrentUser):
    seminar = await repositories.get_seminar(str(seminar_id))
    if not seminar:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Seminar not found"
        )
    if seminar["status"] == "canceled":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Seminar canceled"
        )
    if seminar["status"] == "draft":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Seminar not published"
        )
    if seminar["status"] == "ended":
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="Seminar already ended"
        )

    current_user_id = str(current["id"])
    if str(seminar["host_id"]) != current_user_id:
        has_access = await repositories.user_has_seminar_access(
            current_user_id, seminar
        )
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Purchase required for this seminar",
            )
    row = await repositories.register_attendee(
        seminar_id=str(seminar_id),
        user_id=current_user_id,
        role="participant",
        invite_status="accepted",
    )
    return _attendee_from_row(row)


@router.delete("/{seminar_id}/register", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_from_seminar(seminar_id: UUID, current: CurrentUser):
    removed = await repositories.unregister_attendee(
        seminar_id=str(seminar_id),
        user_id=str(current["id"]),
    )
    if not removed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Registration not found"
        )
    return
