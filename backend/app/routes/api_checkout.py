from __future__ import annotations

from json import JSONDecodeError

from fastapi import APIRouter, HTTPException, Request, status

from ..auth import CurrentUser
from ..schemas import CheckoutCreateResponse
from ..services import checkout_service

router = APIRouter(prefix="/api/checkout", tags=["checkout"])


@router.post(
    "/create",
    response_model=CheckoutCreateResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_checkout_handler(
    request: Request,
    current: CurrentUser,
) -> CheckoutCreateResponse:
    try:
        payload = await request.json()
    except JSONDecodeError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursbetalning kräver JSON-innehåll i begäran",
        ) from exc

    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursbetalning kräver ett objekt i begäran",
        )

    allowed_keys = {"slug"}
    extra_keys = sorted(str(key) for key in payload.keys() if key not in allowed_keys)
    if extra_keys:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursbetalning accepterar bara fältet slug som text",
        )

    slug = payload.get("slug")
    if not isinstance(slug, str) or not slug.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Kursbetalning kräver en ifylld slug",
        )

    return await checkout_service.create_course_checkout(current, slug.strip())
