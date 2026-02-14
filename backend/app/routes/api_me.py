from __future__ import annotations

import logging

from fastapi import APIRouter

from .. import models, repositories, schemas
from ..auth import CurrentUser
from ..schemas.memberships import MembershipRecord, MembershipResponse

router = APIRouter(prefix="/api/me", tags=["me"])
logger = logging.getLogger(__name__)


@router.get("/membership", response_model=MembershipResponse)
async def get_my_membership(current: CurrentUser) -> MembershipResponse:
    membership = await repositories.get_membership(str(current["id"]))
    if not membership:
        return MembershipResponse(membership=None)
    return MembershipResponse(
        membership=MembershipRecord(
            status=membership.get("status"),
            plan_interval=membership.get("plan_interval"),
            price_id=membership.get("price_id"),
            stripe_customer_id=membership.get("stripe_customer_id"),
            stripe_subscription_id=membership.get("stripe_subscription_id"),
            start_date=membership.get("start_date"),
            end_date=membership.get("end_date"),
            updated_at=membership.get("updated_at"),
        )
    )


@router.get("/entitlements", response_model=schemas.EntitlementsResponse)
async def get_my_entitlements(current: CurrentUser) -> schemas.EntitlementsResponse:
    membership = await repositories.get_membership(str(current["id"]))
    membership_payload = None
    if membership:
        status_value = membership.get("status")
        if status_value == "incomplete":
            logger.warning("Incomplete membership encountered for user %s", str(current["id"]))
        is_active = status_value == "active"
        membership_payload = schemas.EntitlementsMembership(
            is_active=bool(is_active),
            status=status_value,
        )

    course_slugs = await repositories.list_entitlements_for_user(str(current["id"]))

    return schemas.EntitlementsResponse(
        membership=membership_payload,
        courses=course_slugs,
    )


@router.post("/claim-purchase", response_model=schemas.PurchaseClaimResponse)
async def claim_purchase(
    payload: schemas.PurchaseClaimRequest, current: CurrentUser
) -> schemas.PurchaseClaimResponse:
    ok = await models.claim_purchase_with_token(
        str(current["id"]), str(payload.token)
    )
    return schemas.PurchaseClaimResponse(ok=ok)
