from fastapi import APIRouter, HTTPException, Query, status

from .. import repositories, schemas
from ..auth import CurrentUser

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post(
    "", response_model=schemas.OrderResponse, status_code=status.HTTP_201_CREATED
)
async def create_order(payload: schemas.OrderCreateRequest, current: CurrentUser):
    if not payload.service_id and not payload.course_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Specify service_id or course_id",
        )

    amount_cents = payload.amount_cents
    currency = (payload.currency or "sek").lower()

    service_id = payload.service_id
    course_id = payload.course_id
    metadata = payload.metadata or {}

    if service_id:
        service = await repositories.get_service(service_id)
        if not service:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Service not found"
            )
        if service.get("status") != "active":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="Service is not active"
            )
        if amount_cents is None:
            amount_cents = service.get("price_cents") or 0
        currency = (service.get("currency") or currency or "sek").lower()
        metadata = {
            **metadata,
            "service_title": service.get("title"),
            "provider_id": str(service.get("provider_id")),
        }

    if amount_cents is None or amount_cents <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="amount_cents must be greater than zero",
        )

    order = await repositories.create_order(
        user_id=current["id"],
        service_id=service_id,
        course_id=course_id,
        amount_cents=amount_cents,
        currency=currency,
        metadata=metadata,
    )
    return schemas.OrderResponse(order=schemas.OrderRecord(**order))


@router.get("/{order_id}", response_model=schemas.OrderResponse)
async def get_order(order_id: str, current: CurrentUser):
    order = await repositories.get_user_order(order_id, current["id"])
    if not order:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Order not found"
        )
    return schemas.OrderResponse(order=schemas.OrderRecord(**order))


@router.get("", response_model=schemas.OrderListResponse)
async def list_orders(
    current: CurrentUser,
    status_filter: str | None = Query(
        None,
        alias="status",
        description="Filter by order status (pending|paid|failed|refunded)",
    ),
    limit: int = Query(50, ge=1, le=200),
):
    normalized_status: str | None = None
    if status_filter:
        normalized_status = status_filter.lower()
    rows = await repositories.list_user_orders(
        current["id"],
        status=normalized_status,
        limit=limit,
    )
    return schemas.OrderListResponse(items=rows)
