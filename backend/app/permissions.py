import logging
from typing import Annotated

from fastapi import Depends, HTTPException, status

from . import models
from .auth import CurrentUser


logger = logging.getLogger(__name__)
_CANONICAL_APP_ENTRY_REQUIRED = "canonical_app_entry_required"


def _deny_role_only_entry(*, permission: str, user_id: str | None) -> None:
    logger.warning(
        "Permission denied: canonical_app_entry_required permission=%s user_id=%s",
        permission,
        user_id,
    )
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail=_CANONICAL_APP_ENTRY_REQUIRED,
    )


async def require_teacher(current: CurrentUser):
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
    _deny_role_only_entry(permission="teacher", user_id=current.get("id"))


async def require_admin(current: CurrentUser):
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
    _deny_role_only_entry(permission="admin", user_id=current.get("id"))


TeacherUser = Annotated[dict, Depends(require_teacher)]
AdminUser = Annotated[dict, Depends(require_admin)]
