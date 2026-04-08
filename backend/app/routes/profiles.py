from fastapi import APIRouter, HTTPException, status

from ..auth import CurrentUser
from .. import models, schemas

router = APIRouter(prefix="/profiles", tags=["profiles"])


@router.get("/me", response_model=schemas.Profile)
async def get_me(current_user: CurrentUser):
    profile = await models.get_profile(current_user["id"])
    if not profile:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="profile_not_found",
        )
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
    return schemas.Profile(**updated)


@router.get("/{user_id}/certificates")
async def certificates(
    user_id: str, current_user: CurrentUser, verified_only: bool = False
):
    viewer_id = str(current_user["id"])
    if user_id != viewer_id and not bool(current_user.get("is_admin")):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Du far inte komma at certifikat",
        )
    rows = await models.certificates_of(user_id, verified_only)
    return {"items": rows}
