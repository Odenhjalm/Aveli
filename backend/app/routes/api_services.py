from datetime import datetime
from typing import Any
from uuid import UUID

from fastapi import APIRouter, HTTPException, Query

from .. import repositories, schemas

router = APIRouter(prefix="/services", tags=["services"])

ALLOWED_STATUSES = {"draft", "active", "paused", "archived"}


def _optional_str(value: Any | None) -> str | None:
    if value is None:
        return None
    return str(value)


def _optional_int(value: Any | None) -> int | None:
    if value is None:
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _ensure_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _require_uuid(value: Any, field: str) -> UUID:
    if isinstance(value, UUID):
        return value
    if value is None:
        raise ValueError(f"Missing UUID for {field}")
    return UUID(str(value))


def _ensure_datetime(value: Any, field: str) -> datetime:
    if isinstance(value, datetime):
        return value
    if value is None:
        raise ValueError(f"Missing datetime for {field}")
    return datetime.fromisoformat(str(value))


@router.get("", response_model=schemas.ServiceListResponse)
async def list_services(
    status: str | None = Query(
        None, description="Filter on service status, e.g. active"
    ),
):
    normalized_status: str | None = None
    if status:
        status_lower = status.lower()
        if status_lower not in ALLOWED_STATUSES:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid status '{status}'. Allowed values: {', '.join(sorted(ALLOWED_STATUSES))}",
            )
        normalized_status = status_lower

    items = []
    for row in await _collect_services(normalized_status):
        item = schemas.ServiceItem(
            id=_require_uuid(row.get("id"), "service.id"),
            title=str(row.get("title") or "Untitled service"),
            description=_optional_str(row.get("description")),
            price_cents=_ensure_int(row.get("price_cents"), default=0),
            currency=str(row.get("currency") or "sek").lower(),
            status=str(row.get("status") or "draft"),
            duration_minutes=_optional_int(row.get("duration_minutes")),
            requires_certification=bool(row.get("requires_certification")),
            certified_area=_optional_str(row.get("certified_area")),
            thumbnail_url=_optional_str(row.get("thumbnail_url")),
            created_at=_ensure_datetime(row.get("created_at"), "service.created_at"),
            updated_at=_ensure_datetime(row.get("updated_at"), "service.updated_at"),
        )
        items.append(item)
    return schemas.ServiceListResponse(items=items)


async def _collect_services(status: str | None) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    async for row in repositories.list_services(status=status):
        rows.append(row)
    return rows
