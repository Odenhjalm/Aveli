from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from ..schemas import CheckoutCreateRequest, CheckoutCreateResponse, CheckoutType
from ..services import checkout_service, universal_checkout_service

router = APIRouter(prefix="/api/checkout", tags=["checkout"])


@router.post(
    "/create",
    response_model=CheckoutCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_checkout_handler(
    payload: CheckoutCreateRequest,
    current: CurrentUser,
) -> CheckoutCreateResponse:
    if payload.type is CheckoutType.course:
        if not payload.slug:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="slug is required for course checkout",
            )
        return await checkout_service.create_course_checkout(current, payload.slug)
    try:
        return await universal_checkout_service.create_checkout_session(current, payload)
    except universal_checkout_service.CheckoutConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except universal_checkout_service.CheckoutError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
