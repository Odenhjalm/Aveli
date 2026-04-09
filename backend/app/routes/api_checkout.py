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
            detail="Course checkout requires a JSON body",
        ) from exc

    if not isinstance(payload, dict):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Course checkout requires an object body",
        )

    allowed_keys = {"slug"}
    extra_keys = sorted(str(key) for key in payload.keys() if key not in allowed_keys)
    if extra_keys:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Course checkout accepts only {\"slug\": string}",
        )

    slug = payload.get("slug")
    if not isinstance(slug, str) or not slug.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Course checkout requires a non-empty slug",
        )

    return await checkout_service.create_course_checkout(current, slug.strip())
