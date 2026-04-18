from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, HTTPException, Request, status


router = APIRouter(prefix="/seminars", tags=["seminars"])


def _raise_v2_feature_disabled() -> None:
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Seminars have no Baseline V2 authority",
    )


@router.get("")
async def list_public_seminars() -> None:
    _raise_v2_feature_disabled()


@router.get("/{seminar_id}")
async def get_public_seminar(seminar_id: UUID) -> None:
    del seminar_id
    _raise_v2_feature_disabled()


@router.post("/{seminar_id}/register", status_code=status.HTTP_201_CREATED)
async def register_for_seminar(seminar_id: UUID) -> None:
    del seminar_id
    _raise_v2_feature_disabled()


@router.delete("/{seminar_id}/register", status_code=status.HTTP_204_NO_CONTENT)
async def unregister_from_seminar(seminar_id: UUID) -> None:
    del seminar_id
    _raise_v2_feature_disabled()


@router.api_route("/{path:path}", methods=["GET", "POST", "PATCH", "PUT", "DELETE"])
async def disabled_seminar_surface(path: str, request: Request) -> None:
    del path, request
    _raise_v2_feature_disabled()
