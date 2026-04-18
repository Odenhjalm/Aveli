from fastapi import APIRouter, HTTPException, Query, status

from .. import repositories, schemas
from ..auth import CurrentUser

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post(
    "", response_model=schemas.OrderResponse, status_code=status.HTTP_201_CREATED
)
async def create_order(payload: schemas.OrderCreateRequest, current: CurrentUser):
    if not payload.course_id and not payload.bundle_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Ange kurs eller kurspaket.",
        )
    if payload.course_id and payload.bundle_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="En order kan bara ha en måltyp.",
        )

    amount_cents = payload.amount_cents
    currency = (payload.currency or "sek").lower()
    course_id = payload.course_id
    bundle_id = payload.bundle_id
    metadata = payload.metadata or {}

    if amount_cents is None or amount_cents <= 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Beloppet måste vara större än noll.",
        )

    order = await repositories.create_order(
        user_id=current["id"],
        course_id=course_id,
        bundle_id=bundle_id,
        order_type="bundle" if bundle_id else "one_off",
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
