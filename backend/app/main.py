from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, HTTPException, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

try:  # pragma: no cover - optional dependency for metrics
    from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
except ImportError:  # pragma: no cover - graceful fallback in dev/test without prometheus_client
    CONTENT_TYPE_LATEST = "text/plain"

    def generate_latest() -> bytes:
        return b""

from .config import settings
from .db import pool
from .logging_utils import setup_logging
from .services import livekit_events
from .routes import (
    admin,
    api_auth,
    api_feed,
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
    landing,
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


@asynccontextmanager
async def lifespan(app: FastAPI):
    Path(settings.media_root).mkdir(parents=True, exist_ok=True)
    UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)
    for sub in ("users", "courses", "lessons"):
        (UPLOADS_ROOT / sub).mkdir(parents=True, exist_ok=True)
    await pool.open(wait=True)
    await livekit_events.start_worker()
    try:
        yield
    finally:
        await livekit_events.stop_worker()
        await pool.close()


app = FastAPI(title="Aveli Local Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allow_origins,
    allow_origin_regex=settings.cors_allow_origin_regex,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "Accept",
        "X-Requested-With",
    ],
)

app.mount("/assets", StaticFiles(directory=ASSETS_ROOT), name="assets")

app.include_router(api_auth.router)
app.include_router(api_services.router)
app.include_router(api_orders.router)
app.include_router(api_feed.router)
app.include_router(api_sfu.router)
app.include_router(api_profiles.router)
app.include_router(api_me.router)
app.include_router(admin.router)
app.include_router(api_checkout.router)
app.include_router(billing.router)
app.include_router(connect.router)
app.include_router(community.router)
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
app.include_router(upload.router)
app.include_router(upload.files_router)


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
