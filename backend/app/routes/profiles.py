from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from .. import models, schemas
from ..utils.profile_media import profile_projection_with_avatar

router = APIRouter(prefix="/profiles", tags=["profiles"])


@router.get("/me", response_model=schemas.Profile)
async def get_me(current_user: CurrentUser):
    profile = await models.get_profile(current_user["id"])
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="profile_not_found",
        )
    profile = await profile_projection_with_avatar(profile)
    return schemas.Profile(**profile)


@router.patch("/me", response_model=schemas.Profile)
async def patch_me(payload: schemas.ProfileUpdate, current_user: CurrentUser):
    if not any(
        [
            payload.display_name is not None,
            payload.bio is not None,
        ]
    ):
        profile = await models.get_profile(current_user["id"])
        if not profile:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="profile_not_found",
            )
        profile = await profile_projection_with_avatar(profile)
        return schemas.Profile(**profile)

    updated = await models.update_profile(
        current_user["id"],
        display_name=payload.display_name,
        bio=payload.bio,
    )
    if not updated:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="profile_not_found",
        )
    updated = await profile_projection_with_avatar(updated)
    return schemas.Profile(**updated)
