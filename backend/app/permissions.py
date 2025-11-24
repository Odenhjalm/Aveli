from typing import Annotated

from fastapi import Depends, HTTPException, status

from . import models
from .auth import CurrentUser


async def require_teacher(current: CurrentUser):
    allowed = await models.is_teacher_user(current["id"])
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Teacher permissions required",
        )
    return current


async def require_admin(current: CurrentUser):
    allowed = await models.is_admin_user(current["id"])
    if not allowed:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin permissions required",
        )
    return current


TeacherUser = Annotated[dict, Depends(require_teacher)]
AdminUser = Annotated[dict, Depends(require_admin)]
