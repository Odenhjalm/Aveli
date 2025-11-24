from __future__ import annotations

import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
import sentry_sdk

from ..logging_context import pop_request_context, push_request_context


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Populate ContextVars with request metadata for structured logging."""

    async def dispatch(self, request: Request, call_next):
        request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        token = push_request_context(request_id)
        request.state.request_id = request_id
        with sentry_sdk.configure_scope() as scope:  # pragma: no cover - tracing glue
            scope.set_tag("request_id", request_id)
        try:
            response: Response = await call_next(request)
        finally:
            pop_request_context(token)
        response.headers.setdefault("X-Request-ID", request_id)
        return response
