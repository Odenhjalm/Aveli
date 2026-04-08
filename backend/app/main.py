from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path
import re
from typing import Awaitable, Callable

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.exception_handlers import (
    http_exception_handler,
    request_validation_exception_handler,
)
from fastapi.exceptions import RequestValidationError
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
from .auth_onboarding_failures import (
    canonical_error_response,
    canonical_http_error_response,
    is_auth_onboarding_request,
    validation_error_response,
)
from .db import pool
from .logging_utils import setup_logging
from .middleware.request_context import RequestContextMiddleware
from .routes import (
    admin,
    auth,
    playback,
    courses,
    domain_observability_mcp,
    email_verification,
    home,
    logs_mcp,
    media_control_plane_mcp,
    profiles,
    referrals,
    studio,
    verification_mcp,
)
from .db import get_conn
from .services import (
    livekit_events,
    media_transcode_worker,
    membership_expiry_warnings,
)

ASSETS_ROOT = Path(__file__).resolve().parents[1] / "assets"
UPLOADS_ROOT = ASSETS_ROOT / "uploads"

setup_logging()

logger = logging.getLogger(__name__)

_CORS_ALLOW_METHODS = "DELETE, GET, HEAD, OPTIONS, PATCH, POST, PUT"
_WorkerStop = Callable[[], Awaitable[None]]
_WorkerStart = Callable[..., Awaitable[None]]


def _local_background_workers() -> tuple[tuple[str, _WorkerStart, _WorkerStop], ...]:
    return (
        ("livekit_webhooks", livekit_events.start_worker, livekit_events.stop_worker),
        ("media_transcode", media_transcode_worker.start_worker, media_transcode_worker.stop_worker),
        (
            "membership_expiry_warnings",
            membership_expiry_warnings.start_worker,
            membership_expiry_warnings.stop_worker,
        ),
    )


async def _start_local_background_workers() -> list[tuple[str, _WorkerStop]]:
    if not settings.mcp_workers_enabled:
        logger.info("Skipping local background workers because MCP mode disables them")
        return []

    verification_mode = bool(settings.runtime_verify_no_write)
    started_workers: list[tuple[str, _WorkerStop]] = []
    for name, start_worker, stop_worker in _local_background_workers():
        await start_worker(verification_mode=verification_mode)
        started_workers.append((name, stop_worker))
    return started_workers


async def _stop_local_background_workers(
    started_workers: list[tuple[str, _WorkerStop]],
) -> None:
    for _, stop_worker in reversed(started_workers):
        await stop_worker()


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
    started_workers: list[tuple[str, _WorkerStop]] = []

    Path(settings.media_root).mkdir(parents=True, exist_ok=True)
    UPLOADS_ROOT.mkdir(parents=True, exist_ok=True)
    for sub in ("users", "courses", "lessons"):
        (UPLOADS_ROOT / sub).mkdir(parents=True, exist_ok=True)
    await pool.open(wait=True)
    try:
        started_workers = await _start_local_background_workers()
        yield
    finally:
        await _stop_local_background_workers(started_workers)
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
    app.include_router(auth.router)
    app.include_router(email_verification.router)
    app.include_router(profiles.router)
    app.include_router(referrals.router)
    app.include_router(admin.router)
    app.include_router(home.router)
    app.include_router(playback.router)
    app.include_router(courses.router)
    app.include_router(courses.api_router)
    app.include_router(studio.router)
    app.include_router(studio.course_lesson_router)
    app.include_router(studio.lesson_media_router)
    app.include_router(logs_mcp.router)
    app.include_router(media_control_plane_mcp.router)
    app.include_router(domain_observability_mcp.router)
    app.include_router(verification_mcp.router)


app = FastAPI(title="Aveli Local Backend", version="0.1.0", lifespan=lifespan)

_configure_middleware(app)


@app.exception_handler(StarletteHTTPException)
async def cors_http_exception_handler(request: Request, exc: StarletteHTTPException):
    if is_auth_onboarding_request(request):
        response = canonical_http_error_response(
            status_code=exc.status_code,
            detail=exc.detail,
            headers=exc.headers,
        )
        for key, value in _cors_error_headers(request).items():
            response.headers.setdefault(key, value)
        return response
    response = await http_exception_handler(request, exc)
    for key, value in _cors_error_headers(request).items():
        response.headers.setdefault(key, value)
    return response


@app.exception_handler(RequestValidationError)
async def auth_onboarding_validation_exception_handler(
    request: Request,
    exc: RequestValidationError,
):
    if is_auth_onboarding_request(request):
        response = validation_error_response(exc, headers=_cors_error_headers(request))
        for key, value in _cors_error_headers(request).items():
            response.headers.setdefault(key, value)
        return response
    response = await request_validation_exception_handler(request, exc)
    for key, value in _cors_error_headers(request).items():
        response.headers.setdefault(key, value)
    return response


@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    if is_auth_onboarding_request(request):
        return canonical_error_response(
            status_code=500,
            error_code="internal_error",
            headers=_cors_error_headers(request),
        )
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
        "surface": "canonical-runtime",
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


fastapi_app = app
