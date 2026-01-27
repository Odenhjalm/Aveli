from contextlib import asynccontextmanager
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

try:  # pragma: no cover - optional dependency for metrics
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
except ImportError:  # pragma: no cover - graceful fallback in dev/test without prometheus_client
    CONTENT_TYPE_LATEST = "text/plain"

    def generate_latest() -> bytes:
        return b""

from .config import settings
from .db import pool
from .logging_utils import setup_logging
from .middleware.request_context import RequestContextMiddleware
from .services import livekit_events, media_transcode_worker
from .routes import (
    admin,
    api_ai,
    api_context7,
    api_auth,
    api_feed,
    api_media,
    api_me,
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
    media,
    profiles,
    seminars,
    session_slots,
    studio,
    studio_sessions,
    stripe_webhook,
    stripe_webhooks,
    upload,
)
from .db import get_conn

ASSETS_ROOT = Path(__file__).resolve().parents[1] / "assets"
UPLOADS_ROOT = ASSETS_ROOT / "uploads"

setup_logging()


def setup_sentry() -> None:
    if not settings.sentry_dsn:
        return
    environment = os.environ.get("APP_ENV") or os.environ.get("ENVIRONMENT") or os.environ.get("ENV")
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
    try:
        yield
    finally:
        await media_transcode_worker.stop_worker()
        await livekit_events.stop_worker()
        await pool.close()


app = FastAPI(title="Aveli Local Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(RequestContextMiddleware)

app_env_value = os.environ.get("APP_ENV") or os.environ.get("ENVIRONMENT") or os.environ.get("ENV") or ""
app_env_lower = app_env_value.strip().lower()
is_production_env = app_env_lower in {"production", "prod", "live"}

cors_allow_origin_regex = None
if not is_production_env:
    # Dev-only CORS allowance for local Flutter Web (localhost:* / 127.0.0.1:*).
    local_origin_regex = r"http://(localhost|127\.0\.0\.1)(:\d+)?"
    configured_regex = (settings.cors_allow_origin_regex or "").strip()
    if configured_regex:
        cors_allow_origin_regex = f"(?:{configured_regex})|(?:{local_origin_regex})"
    else:
        cors_allow_origin_regex = local_origin_regex

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=cors_allow_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    # Allow all headers so browser preflights don't fail when uploads include
    # additional metadata headers (e.g. resumable/tus uploads).
    allow_headers=["*"],
)

app.mount("/assets", StaticFiles(directory=ASSETS_ROOT), name="assets")

app.include_router(api_auth.router)
app.include_router(api_ai.router)
app.include_router(api_context7.router)
app.include_router(api_services.router)
app.include_router(api_orders.router)
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
app.include_router(courses.config_router)
app.include_router(courses.router)
app.include_router(courses.api_router)
app.include_router(course_bundles.router)
app.include_router(landing.router)
app.include_router(media.router)
app.include_router(profiles.router)
app.include_router(seminars.router)
app.include_router(session_slots.router)
app.include_router(studio.router)
app.include_router(studio_sessions.router)
app.include_router(stripe_webhook.router)
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
