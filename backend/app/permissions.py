import logging
from typing import Annotated

from fastapi import Depends, HTTPException, status

from . import models
from .auth import AppEntryUser


logger = logging.getLogger(__name__)


async def require_teacher(current: AppEntryUser):
    allowed = await models.is_teacher_user(current["id"])
    if not allowed:
        logger.warning(
            "Permission denied: teacher_required user_id=%s",
            current.get("id"),
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="forbidden",
        )
    return current


async def require_admin(current: AppEntryUser):
    allowed = await models.is_admin_user(current["id"])
    if not allowed:
        logger.warning(
            "Permission denied: admin_required user_id=%s",
            current.get("id"),
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="admin_required",
        )
    return current


TeacherEntryUser = Annotated[dict, Depends(require_teacher)]
AdminEntryUser = Annotated[dict, Depends(require_admin)]

TeacherUser = TeacherEntryUser
AdminUser = AdminEntryUser
