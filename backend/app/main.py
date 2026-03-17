from contextlib import asynccontextmanager
import os
from pathlib import Path
import re

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exception_handlers import http_exception_handler
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration
from starlette.exceptions import HTTPException as StarletteHTTPException

try:  # pragma: no cover - optional dependency for metrics
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
except (
    ImportError
):  # pragma: no cover - graceful fallback in dev/test without prometheus_client
    CONTENT_TYPE_LATEST = "text/plain"

    def generate_latest() -> bytes:
        return b""


from .config import settings
from .db import pool
from .logging_utils import setup_logging
from .media_control_plane.routes import media_admin_router
from .middleware.request_context import RequestContextMiddleware
from .services import livekit_events, media_transcode_worker, membership_expiry_warnings
from .routes import (
    admin,
    api_ai,
    api_context7,
    api_auth,
    api_events,
    api_feed,
    api_media,
    api_me,
    api_notifications,
    api_onboarding,
    api_checkout,
    api_orders,
    api_profiles,
    api_services,
    api_sfu,
    billing,
    community,
    connect,
    courses,
    home,
    landing,
    livekit_webhooks,
    course_bundles,
    email_verification,
    media,
    profiles,
    seminars,
    session_slots,
    studio,
    studio_sessions,
    stripe_webhooks,
    upload,
)
from .db import get_conn

ASSETS_ROOT = Path(__file__).resolve().parents[1] / "assets"
UPLOADS_ROOT = ASSETS_ROOT / "uploads"

setup_logging()

_CORS_ALLOW_METHODS = "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT"


def setup_sentry() -> None:
    if not settings.sentry_dsn:
        return
    environment = (
        os.environ.get("APP_ENV")
        or os.environ.get("ENVIRONMENT")
        or os.environ.get("ENV")
    )
    sentry_sdk.init(
        dsn=settings.sentry_dsn,
        environment=environment,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        integrations=[FastApiIntegration(), StarletteIntegration()],
    )


setup_sentry()


@asynccontextmanager
async def lifespan(app: FastAPI):
    Path(settings.media_root).mkdir(parents=True, exist_ok=True)
    UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)
    for sub in ("users", "courses", "lessons"):
        (UPLOADS_ROOT / sub).mkdir(parents=True, exist_ok=True)
    await pool.open(wait=True)
    await livekit_events.start_worker()
    await media_transcode_worker.start_worker()
    await membership_expiry_warnings.start_worker()
    try:
        yield
    finally:
        await membership_expiry_warnings.stop_worker()
        await media_transcode_worker.stop_worker()
        await livekit_events.stop_worker()
        await pool.close()


def _origin_is_allowed(origin: str | None) -> bool:
    if not origin:
        return False
    if origin in settings.cors_allow_origins:
        return True
    pattern = settings.cors_allow_origin_regex
    return bool(pattern and re.fullmatch(pattern, origin))


def _cors_error_headers(request: Request) -> dict[str, str]:
    origin = request.headers.get("origin")
    if not _origin_is_allowed(origin):
        return {}

    requested_headers = request.headers.get("access-control-request-headers") or "*"
    return {
        "Access-Control-Allow-Origin": origin,
        "Access-Control-Allow-Credentials": "true",
        "Access-Control-Allow-Methods": _CORS_ALLOW_METHODS,
        "Access-Control-Allow-Headers": requested_headers,
        "Vary": "Origin",
    }


def _configure_middleware(app: FastAPI) -> None:
    # Starlette applies middleware in reverse registration order, so CORS is
    # added last here to keep it outermost and let it answer browser preflights
    # before other middleware or route matching runs.
    app.add_middleware(RequestContextMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_allow_origins,
        allow_origin_regex=settings.cors_allow_origin_regex,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )


def _include_routers(app: FastAPI) -> None:
    app.include_router(api_auth.router)
    app.include_router(api_ai.router)
    app.include_router(api_context7.router)
    app.include_router(api_services.router)
    app.include_router(api_orders.router)
    app.include_router(api_events.router)
    app.include_router(api_notifications.router)
    app.include_router(api_onboarding.router)
    app.include_router(api_feed.router)
    app.include_router(api_sfu.router)
    app.include_router(api_profiles.router)
    app.include_router(api_me.router)
    app.include_router(api_media.router)
    app.include_router(api_media.debug_router)
    app.include_router(admin.router)
    app.include_router(media_admin_router.router)
    app.include_router(api_checkout.router)
    app.include_router(billing.router)
    app.include_router(connect.router)
    app.include_router(community.router)
    app.include_router(home.router)
    app.include_router(courses.router)
    app.include_router(courses.api_router)
    app.include_router(course_bundles.router)
    app.include_router(email_verification.router)
    app.include_router(landing.router)
    app.include_router(media.router)
    app.include_router(profiles.router)
    app.include_router(seminars.router)
    app.include_router(session_slots.router)
    app.include_router(studio.router)
    app.include_router(studio_sessions.router)
    app.include_router(stripe_webhooks.router)
    app.include_router(livekit_webhooks.router)
    app.include_router(upload.router)
    app.include_router(upload.files_router)
    app.include_router(upload.legacy_router)


app = FastAPI(title="Aveli Local Backend", version="0.1.0", lifespan=lifespan)

_configure_middleware(app)


@app.exception_handler(StarletteHTTPException)
async def cors_http_exception_handler(request: Request, exc: StarletteHTTPException):
    response = await http_exception_handler(request, exc)
    for key, value in _cors_error_headers(request).items():
        response.headers.setdefault(key, value)
    return response


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error"},
        headers=_cors_error_headers(request),
    )


app.mount("/assets", StaticFiles(directory=ASSETS_ROOT), name="assets")

_include_routers(app)


@app.get("/healthz")
async def healthz():
    return {
        "ok": True,
        "message": "Backend responding",
        "livekit": livekit_events.get_metrics(),
    }


@app.get("/readyz")
async def readyz():
    try:
        async with get_conn() as cur:  # type: ignore[attr-defined]
            await cur.execute("select 1")  # type: ignore[attr-defined]
            await cur.fetchone()
    except Exception as exc:  # pragma: no cover - surfaced in tests
        raise HTTPException(status_code=503, detail="database unavailable") from exc
    email_mode = (
        "configured"
        if settings.resend_api_key and settings.email_from
        else "log_only"
    )
    return {"ok": True, "database": "ready", "email_delivery_mode": email_mode}


@app.get("/metrics")
def metrics_endpoint():
    payload = generate_latest()
    return Response(content=payload, media_type=CONTENT_TYPE_LATEST)


fastapi_app = app
