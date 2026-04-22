from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field

from ..config import settings
from ..db import pool
from ..permissions import TeacherEntryUser
from ..repositories import media_assets as media_assets_repo
from ..repositories import special_offers as special_offers_repo
from ..schemas.special_offers import SpecialOfferCreate
from ..services import (
    special_offer_execution_read_service,
    special_offer_execution_service,
    special_offers_service,
    storage_service,
)
from ..services.special_offer_text_catalog import SPECIAL_OFFER_CONFLICT_EXISTS

router = APIRouter(tags=["special-offers"])


class SpecialOfferExecutionUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    course_ids: list[UUID] | None = None
    price_amount_cents: int | None = Field(default=None, ge=1)


class SpecialOfferRegenerateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    confirm_overwrite: bool = False


def _stringify_uuid(value: Any) -> str:
    try:
        return str(UUID(str(value).strip()))
    except (TypeError, ValueError, AttributeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail={"error_code": "special_offer_domain_unavailable"},
        ) from exc


def _raise_special_offer_error(
    exc: special_offers_service.SpecialOfferDomainError,
) -> None:
    detail: dict[str, Any] = {"error_code": exc.code}
    text_id = str(exc.context.get("text_id") or "").strip()
    if text_id:
        detail["text_id"] = text_id
    raise HTTPException(status_code=exc.status_code, detail=detail) from exc


async def _current_special_offer_id_for_teacher(teacher_id: str) -> str | None:
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        special_offer_ids = await special_offers_repo.list_teacher_special_offer_ids(
            conn,
            teacher_id=teacher_id,
            limit=1,
        )
    if not special_offer_ids:
        return None
    return special_offer_ids[0]


async def _special_offer_image_payload(
    media_asset_id: str | None,
) -> dict[str, Any] | None:
    normalized_media_asset_id = str(media_asset_id or "").strip()
    if not normalized_media_asset_id:
        return None

    asset = await media_assets_repo.get_media_asset(normalized_media_asset_id)
    if asset is None:
        return None

    media_type = str(asset.get("media_type") or "").strip().lower()
    purpose = str(asset.get("purpose") or "").strip().lower()
    state = str(asset.get("state") or "").strip().lower()
    playback_format = str(asset.get("playback_format") or "").strip().lower()
    playback_object_path = str(asset.get("playback_object_path") or "").strip()
    if (
        media_type != "image"
        or purpose != "special_offer_composite_image"
        or state != "ready"
        or playback_format != "jpg"
        or not playback_object_path
    ):
        return None

    resolved_url = storage_service.get_storage_service(
        settings.media_public_bucket
    ).public_url(playback_object_path)
    if not str(resolved_url or "").strip():
        return None

    return {
        "media_id": normalized_media_asset_id,
        "state": "ready",
        "resolved_url": resolved_url,
    }


async def _build_special_offer_execution_payload(
    *,
    special_offer_id: str,
    execution_state: dict[str, Any] | None = None,
) -> dict[str, Any]:
    offer = await special_offers_service.get_offer(pool, special_offer_id)
    state = execution_state or await special_offer_execution_read_service.get_special_offer_execution_state(
        pool,
        special_offer_id=special_offer_id,
    )
    active_media_asset_id = str(state.get("active_media_asset_id") or "").strip() or None
    image = await _special_offer_image_payload(active_media_asset_id)

    return {
        "special_offer_id": _stringify_uuid(state.get("special_offer_id") or offer.id),
        "active_output_id": (
            _stringify_uuid(state["active_output_id"])
            if state.get("active_output_id") is not None
            else None
        ),
        "active_media_asset_id": (
            _stringify_uuid(state["active_media_asset_id"])
            if state.get("active_media_asset_id") is not None
            else None
        ),
        "state_hash": str(state.get("state_hash") or offer.state_hash),
        "attempt_id": (
            _stringify_uuid(state["attempt_id"])
            if state.get("attempt_id") is not None
            else None
        ),
        "status": state.get("status"),
        "text_id": state.get("text_id"),
        "source_count": int(state.get("source_count") or len(offer.courses)),
        "overwrite_applied": bool(state.get("overwrite_applied")),
        "image_current": bool(state.get("image_current")),
        "image_required": bool(state.get("image_required")),
        "price_amount_cents": int(offer.price_amount_cents),
        "course_ids": [str(course.course_id) for course in offer.courses],
        "image": image,
    }


@router.get("/api/teachers/special-offers/execution/current")
async def get_current_special_offer_execution_state(
    current: TeacherEntryUser,
) -> dict[str, Any]:
    special_offer_id = await _current_special_offer_id_for_teacher(str(current["id"]))
    if special_offer_id is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"error_code": "special_offer_not_found"},
        )
    try:
        return await _build_special_offer_execution_payload(
            special_offer_id=special_offer_id,
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)


@router.post(
    "/api/teachers/special-offers/execution",
    status_code=status.HTTP_201_CREATED,
)
async def create_special_offer_execution(
    payload: SpecialOfferCreate,
    current: TeacherEntryUser,
) -> dict[str, Any]:
    current_special_offer_id = await _current_special_offer_id_for_teacher(
        str(current["id"])
    )
    if current_special_offer_id is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "error_code": "special_offer_output_conflict",
                "text_id": SPECIAL_OFFER_CONFLICT_EXISTS,
            },
        )
    try:
        execution_state = await special_offer_execution_service.create_special_offer_execution(
            pool,
            teacher_id=str(current["id"]),
            course_ids=[str(course_id) for course_id in payload.course_ids],
            price_amount_cents=int(payload.price_amount_cents),
        )
        return await _build_special_offer_execution_payload(
            special_offer_id=_stringify_uuid(execution_state["special_offer_id"]),
            execution_state=execution_state,
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)


@router.patch("/api/teachers/special-offers/{special_offer_id}/execution")
async def update_special_offer_execution(
    special_offer_id: UUID,
    payload: SpecialOfferExecutionUpdateRequest,
    current: TeacherEntryUser,
) -> dict[str, Any]:
    try:
        execution_state = await special_offer_execution_service.update_special_offer_execution(
            pool,
            special_offer_id=str(special_offer_id),
            teacher_id=str(current["id"]),
            course_ids=(
                [str(course_id) for course_id in payload.course_ids]
                if payload.course_ids is not None
                else None
            ),
            price_amount_cents=payload.price_amount_cents,
        )
        return await _build_special_offer_execution_payload(
            special_offer_id=str(special_offer_id),
            execution_state=execution_state,
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)


@router.post("/api/teachers/special-offers/{special_offer_id}/execution/generate")
async def generate_special_offer_image(
    special_offer_id: UUID,
    current: TeacherEntryUser,
) -> dict[str, Any]:
    try:
        execution_state = await special_offer_execution_service.generate_special_offer_image(
            pool,
            special_offer_id=str(special_offer_id),
            teacher_id=str(current["id"]),
        )
        return await _build_special_offer_execution_payload(
            special_offer_id=str(special_offer_id),
            execution_state=execution_state,
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)


@router.post("/api/teachers/special-offers/{special_offer_id}/execution/regenerate")
async def regenerate_special_offer_image(
    special_offer_id: UUID,
    payload: SpecialOfferRegenerateRequest,
    current: TeacherEntryUser,
) -> dict[str, Any]:
    try:
        execution_state = await special_offer_execution_service.regenerate_special_offer_image(
            pool,
            special_offer_id=str(special_offer_id),
            teacher_id=str(current["id"]),
            confirm_overwrite=bool(payload.confirm_overwrite),
        )
        return await _build_special_offer_execution_payload(
            special_offer_id=str(special_offer_id),
            execution_state=execution_state,
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)


@router.get("/api/teachers/special-offers/{special_offer_id}/execution")
async def get_special_offer_execution_state(
    special_offer_id: UUID,
    current: TeacherEntryUser,
) -> dict[str, Any]:
    try:
        offer = await special_offers_service.get_offer(pool, special_offer_id)
        if str(offer.teacher_id) != str(current["id"]):
            raise special_offers_service.SpecialOfferDomainError(
                "special_offer_output_conflict",
                status_code=409,
            )
        return await _build_special_offer_execution_payload(
            special_offer_id=str(special_offer_id),
        )
    except special_offers_service.SpecialOfferDomainError as exc:
        _raise_special_offer_error(exc)
