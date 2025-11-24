from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request, status

from ..services import subscription_service

router = APIRouter(prefix="/api/billing", tags=["billing"])


@router.post("/webhook", status_code=status.HTTP_200_OK)
async def stripe_subscription_webhook(request: Request):
    # /api/billing/webhook expects STRIPE_BILLING_WEBHOOK_SECRET (falls back to STRIPE_WEBHOOK_SECRET).
    payload = await request.body()
    signature = request.headers.get("stripe-signature")
    try:
        await subscription_service.handle_webhook(payload, signature)
    except subscription_service.SubscriptionConfigError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    except subscription_service.SubscriptionError as exc:
        raise HTTPException(status_code=exc.status_code, detail=exc.detail)
    return {"status": "ok"}
