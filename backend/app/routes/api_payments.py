from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status

from ..auth import CurrentUser
from ..schemas.billing import CheckoutSessionRequest, CheckoutSessionResponse
from ..services import payment_command_shadow, subscription_service

router = APIRouter(prefix="/payments", tags=["payments (legacy/mvp)"])


@router.post(
    "/create-checkout-session",
    response_model=CheckoutSessionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_checkout_session(
    payload: CheckoutSessionRequest,
    current: CurrentUser,
    request: Request,
) -> CheckoutSessionResponse:
    idempotency_key = payment_command_shadow.extract_idempotency_key(request.headers)
    try:
        url = await subscription_service.create_checkout_session(
            current,
            payload.plan,
            idempotency_key=idempotency_key,
            request_metadata={
                "endpoint": str(request.url.path),
                "method": request.method,
            },
        )
        return CheckoutSessionResponse(url=url)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
