from __future__ import annotations

import re
from typing import Any

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

_COVERED_STATIC_SURFACES = {
    ("POST", "/auth/register"),
    ("POST", "/auth/login"),
    ("POST", "/auth/forgot-password"),
    ("POST", "/auth/reset-password"),
    ("POST", "/auth/refresh"),
    ("POST", "/auth/send-verification"),
    ("GET", "/auth/verify-email"),
    ("GET", "/auth/validate-invite"),
    ("POST", "/auth/onboarding/complete"),
    ("GET", "/profiles/me"),
    ("PATCH", "/profiles/me"),
}
_ADMIN_USER_ROUTE_PATTERN = re.compile(
    r"^/admin/users/[^/]+/(grant-teacher-role|revoke-teacher-role)$"
)
_VALID_STATUS_CODES = {400, 401, 403, 404, 409, 422, 429, 500}
_ERROR_MESSAGES = {
    "invalid_or_expired_token": "Lanken ar ogiltig eller har gatt ut.",
    "invalid_current_password": "Det nuvarande losenordet ar fel.",
    "new_password_must_differ": "Det nya losenordet maste skilja sig fran det nuvarande.",
    "invalid_credentials": "Fel e-postadress eller losenord.",
    "unauthenticated": "Du maste logga in for att fortsatta.",
    "refresh_token_invalid": "Ogiltig uppdateringstoken.",
    "forbidden": "Du har inte behorighet att utfora den har atgarden.",
    "admin_required": "Adminbehorighet kravs for den har atgarden.",
    "user_not_found": "Anvandaren kunde inte hittas.",
    "subject_not_found": "Auth-subjektet kunde inte hittas.",
    "profile_not_found": "Profilen kunde inte hittas.",
    "email_already_registered": "E-postadressen ar redan registrerad.",
    "already_teacher": "Anvandaren har redan lararrollen.",
    "already_learner": "Anvandaren har redan elevrollen.",
    "admin_bootstrap_already_consumed": "Admin-bootstrap har redan forbrukats.",
    "validation_error": "Begaran innehaller ogiltiga eller saknade falt.",
    "rate_limited": "For manga forsok. Forsok igen om en liten stund.",
    "internal_error": "Ett internt fel uppstod. Forsok igen senare.",
}
_DEFAULT_ERROR_CODE_BY_STATUS = {
    400: "invalid_or_expired_token",
    401: "unauthenticated",
    403: "forbidden",
    404: "profile_not_found",
    409: "email_already_registered",
    422: "validation_error",
    429: "rate_limited",
    500: "internal_error",
}
_FIELD_ERROR_MESSAGE_BY_TYPE = {
    "missing": "Faltet maste anges.",
    "extra_forbidden": "Faltet ar inte tillatet.",
    "string_too_short": "Vardet ar for kort.",
    "string_too_long": "Vardet ar for langt.",
    "string_pattern_mismatch": "Vardet har fel format.",
}


def is_auth_onboarding_surface(method: str, path: str) -> bool:
    normalized = (method.upper(), path)
    if normalized in _COVERED_STATIC_SURFACES:
        return True
    if method.upper() == "POST" and _ADMIN_USER_ROUTE_PATTERN.match(path):
        return True
    return False


def is_auth_onboarding_request(request: Request) -> bool:
    return is_auth_onboarding_surface(request.method, request.url.path)


def _coerce_error_code(status_code: int, detail: Any) -> str:
    if status_code not in _VALID_STATUS_CODES:
        return "internal_error"
    if isinstance(detail, dict):
        detail = detail.get("error_code")
    if isinstance(detail, str):
        candidate = detail.strip()
        if candidate in _ERROR_MESSAGES:
            return candidate
    return _DEFAULT_ERROR_CODE_BY_STATUS.get(status_code, "internal_error")


def canonical_error_message(error_code: str) -> str:
    return _ERROR_MESSAGES.get(error_code, _ERROR_MESSAGES["internal_error"])


def canonical_error_response(
    *,
    status_code: int,
    error_code: str,
    headers: dict[str, str] | None = None,
    field_errors: list[dict[str, str]] | None = None,
) -> JSONResponse:
    body: dict[str, Any] = {
        "status": "error",
        "error_code": error_code,
        "message": canonical_error_message(error_code),
    }
    if field_errors:
        body["field_errors"] = field_errors
    return JSONResponse(status_code=status_code, content=body, headers=headers)


def canonical_http_error_response(
    *,
    status_code: int,
    detail: Any,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    error_code = _coerce_error_code(status_code, detail)
    return canonical_error_response(
        status_code=status_code if error_code != "internal_error" else 500,
        error_code=error_code,
        headers=headers,
    )


def validation_error_response(
    exc: RequestValidationError,
    *,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    field_errors: list[dict[str, str]] = []
    for raw_error in exc.errors():
        loc = list(raw_error.get("loc") or [])
        if loc and loc[0] in {"body", "query", "path"}:
            loc = loc[1:]
        field = ".".join(str(part) for part in loc) or "request"
        error_type = str(raw_error.get("type") or "validation_error")
        normalized_type = error_type.split(".")[-1]
        field_errors.append(
            {
                "field": field,
                "error_code": normalized_type,
                "message": _FIELD_ERROR_MESSAGE_BY_TYPE.get(
                    normalized_type, "Ogiltigt varde."
                ),
            }
        )
    return canonical_error_response(
        status_code=422,
        error_code="validation_error",
        headers=headers,
        field_errors=field_errors,
    )
