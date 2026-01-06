from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from ..schemas.billing import (
    BillingPortalResponse,
    CheckoutSessionRequest,
    CheckoutSessionResponse,
    SessionStatusResponse,
    SubscriptionCancelRequest,
    SubscriptionCancelResponse,
    SubscriptionCheckoutResponse,
    SubscriptionSessionRequest,
)
from ..services import billing_portal_service, subscription_service

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
    "/customer-portal",
    response_model=BillingPortalResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_billing_portal(current: CurrentUser) -> BillingPortalResponse:
    try:
        url = await billing_portal_service.create_billing_portal_session(current)
        return BillingPortalResponse(url=url)
    except billing_portal_service.BillingPortalConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except billing_portal_service.BillingPortalError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/create-checkout-session",
    response_model=CheckoutSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_checkout_session(
    payload: CheckoutSessionRequest, current: CurrentUser
) -> CheckoutSessionResponse:
    try:
        url = await subscription_service.create_checkout_session(current, payload.plan)
        return CheckoutSessionResponse(url=url)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)

@router.get("/session-status", response_model=SessionStatusResponse)
async def get_session_status(session_id: str) -> SessionStatusResponse:
    try:
        return await subscription_service.fetch_session_status(session_id)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)


@router.post(
    "/cancel-subscription",
    response_model=SubscriptionCancelResponse,
)
async def cancel_subscription(
    payload: SubscriptionCancelRequest, current: CurrentUser
) -> SubscriptionCancelResponse:
    try:
        result = await subscription_service.cancel_subscription(
            current, subscription_id=payload.subscription_id
        )
        return SubscriptionCancelResponse(**result)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
