from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from ..schemas.billing import (
    SubscriptionCancelRequest,
    SubscriptionCheckoutResponse,
    SubscriptionSessionRequest,
)
from ..services import subscription_service

router = APIRouter(prefix="/api/billing", tags=["billing"])


@router.post(
    "/create-subscription",
    response_model=SubscriptionCheckoutResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_subscription_endpoint(
    payload: SubscriptionSessionRequest, current: CurrentUser
) -> SubscriptionCheckoutResponse:
    try:
        return await subscription_service.create_subscription_checkout(current, payload.interval)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/cancel-subscription-intent",
    status_code=status.HTTP_202_ACCEPTED,
)
async def cancel_subscription_intent(
    payload: SubscriptionCancelRequest, current: CurrentUser
) -> dict[str, object]:
    try:
        return await subscription_service.cancel_subscription_intent(
            current, subscription_id=payload.subscription_id
        )
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
