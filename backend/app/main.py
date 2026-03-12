from contextlib import asynccontextmanager
import json
import logging
import os
from pathlib import Path
from typing import List

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

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
logger = logging.getLogger(__name__)


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


def _normalize_origin(origin: str) -> str:
    origin = origin.strip().strip('"').strip("'")
    return origin.rstrip("/")


def get_allowed_origins() -> List[str]:
    raw = os.getenv("CORS_ALLOW_ORIGINS")
    if not raw:
        logger.warning(
            "CORS_ALLOW_ORIGINS not set, defaulting to production frontend origin."
        )
        return ["https://app.aveli.app"]

    raw = raw.strip()
    origins: List[str] = []

    if raw.startswith("["):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                origins = [
                    _normalize_origin(origin)
                    for origin in parsed
                    if isinstance(origin, str)
                ]
            else:
                raise ValueError("CORS_ALLOW_ORIGINS JSON must be a list.")
        except Exception as exc:
            logger.error("Failed to parse CORS_ALLOW_ORIGINS as JSON: %s", exc)
            raise RuntimeError("Invalid CORS_ALLOW_ORIGINS format")
    else:
        origins = [
            _normalize_origin(origin) for origin in raw.split(",") if origin.strip()
        ]

    origins = [origin for origin in origins if origin and origin != "*"]
    if not origins:
        raise RuntimeError("CORS_ALLOW_ORIGINS resolved to empty list.")

    logger.info("CORS allowed origins loaded: %s", origins)
    return origins


app = FastAPI(title="Aveli Local Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_allowed_origins(),
    allow_credentials=True,
    allow_methods=["*"],
    # Allow all headers so browser preflights don't fail when uploads include
    # additional metadata headers (e.g. resumable/tus uploads).
    allow_headers=["*"],
)

app.add_middleware(RequestContextMiddleware)


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error"},
    )


app.mount("/assets", StaticFiles(directory=ASSETS_ROOT), name="assets")

app.include_router(api_auth.router)
app.include_router(api_ai.router)
app.include_router(api_context7.router)
app.include_router(api_services.router)
app.include_router(api_orders.router)
app.include_router(api_events.router)
app.include_router(api_notifications.router)
app.include_router(api_feed.router)
app.include_router(api_sfu.router)
app.include_router(api_profiles.router)
app.include_router(api_me.router)
app.include_router(api_media.router)
app.include_router(admin.router)
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
    return {"ok": True, "database": "ready"}


@app.get("/metrics")
def metrics_endpoint():
    payload = generate_latest()
    return Response(content=payload, media_type=CONTENT_TYPE_LATEST)
