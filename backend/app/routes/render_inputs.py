from fastapi import APIRouter, HTTPException, status

from .. import schemas
from ..services import app_render_inputs_service, storage_service, text_catalog_service

router = APIRouter(prefix="/app", tags=["app"])


@router.get(
    "/render-inputs",
    response_model=schemas.AppRenderInputsResponse,
)
def app_render_inputs():
    try:
        payload = app_render_inputs_service.build_app_render_inputs_payload()
    except storage_service.StorageServiceError:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="App render inputs are unavailable.",
        )
    payload = text_catalog_service.attach_text_bundles(
        payload,
        [text_catalog_service.GLOBAL_SYSTEM_NAVIGATION_BUNDLE_ID],
        text_catalog_service.DEFAULT_LOCALE,
    )
    return schemas.AppRenderInputsResponse(**payload)
