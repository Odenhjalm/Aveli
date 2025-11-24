from fastapi import APIRouter

from .. import repositories, schemas
from ..auth import CurrentUser

router = APIRouter(prefix="/feed", tags=["feed"])


@router.get("", response_model=schemas.FeedResponse)
async def get_feed(current: CurrentUser, limit: int = 50):
    items = [
        schemas.FeedItem(
            id=row["id"],
            activity_type=row.get("activity_type"),
            actor_id=row.get("actor_id"),
            subject_table=row.get("subject_table"),
            subject_id=row.get("subject_id"),
            summary=row.get("summary"),
            metadata=row.get("metadata") or {},
            occurred_at=row.get("occurred_at"),
        )
        async for row in repositories.list_feed(limit=limit)
    ]
    return schemas.FeedResponse(items=items)
