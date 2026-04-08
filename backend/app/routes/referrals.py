from fastapi import APIRouter, HTTPException, status

from .. import schemas
from ..auth import CurrentUser
from ..repositories.referrals import InvalidReferralCodeError
from ..services import referral_service

router = APIRouter(prefix="/referrals", tags=["referrals"])


@router.post("/redeem", response_model=schemas.ReferralRedeemResponse)
async def redeem_referral(
    payload: schemas.ReferralRedeemRequest,
    current_user: CurrentUser,
):
    try:
        await referral_service.redeem_referral(
            code=payload.code,
            user_id=str(current_user["id"]),
            email=str(current_user.get("email") or ""),
        )
    except InvalidReferralCodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="invalid_referral_code",
        ) from exc

    return schemas.ReferralRedeemResponse(status="redeemed")
