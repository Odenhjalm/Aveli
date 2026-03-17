from __future__ import annotations

from urllib.parse import urlencode

from .. import models, repositories
from ..config import settings
from .email_service import EmailDeliveryResult
from .email_service import send_email
from .email_templates import render_template
from .email_tokens import EmailTokenError, create_email_token, verify_email_token

_VERIFY_TOKEN_EXPIRY_MINUTES = 15
_RESET_TOKEN_EXPIRY_MINUTES = 10
_INVITE_TOKEN_EXPIRY_MINUTES = 24 * 60
_VERIFY_EMAIL_SUBJECT = "Bekräfta din e-post för Aveli"
_RESET_PASSWORD_SUBJECT = "Återställ ditt Aveli-lösenord"
_INVITE_EMAIL_SUBJECT = "You're invited to Aveli"
_DEFAULT_FRONTEND_BASE_URL = "https://app.aveli.app"
_SUPPORT_EMAIL = "support@aveli.dev"


class InvalidEmailVerificationTokenError(ValueError):
    pass


class InvalidPasswordResetTokenError(ValueError):
    pass


class InvalidInviteTokenError(ValueError):
    pass


async def send_verification_email(email: str) -> EmailDeliveryResult:
    normalized_email = email.strip().lower()
    token = create_email_token(
        normalized_email,
        token_type="verify",
        expires_minutes=_VERIFY_TOKEN_EXPIRY_MINUTES,
    )
    verify_url = _build_verify_url(token)
    html_body = render_template(
        "verify_email.html",
        verify_url=verify_url,
        expiry_minutes=_VERIFY_TOKEN_EXPIRY_MINUTES,
    )
    text_body = (
        "Bekräfta din e-postadress för Aveli.\n\n"
        f"Verifiera din e-post inom {_VERIFY_TOKEN_EXPIRY_MINUTES} minuter: {verify_url}\n\n"
        "Efter verifieringen fortsätter du till medlemskap, profil och val av introduktionskurs.\n"
        "Du startar med 30 dagars trial, får en ny lektion per vecka, och varje introduktionskurs innehåller fyra lektioner.\n"
        f"Om länken inte fungerar kan du begära en ny från inloggningen eller kontakta {_SUPPORT_EMAIL}."
    )

    return await send_email(
        to_email=normalized_email,
        subject=_VERIFY_EMAIL_SUBJECT,
        text_body=text_body,
        html_body=html_body,
    )


async def verify_email_token_and_mark_user(token: str) -> dict[str, str]:
    email = _verify_token(token, expected_type="verify", error_type=InvalidEmailVerificationTokenError)

    user = await repositories.get_user_by_email(email)
    if not user:
        raise InvalidEmailVerificationTokenError("invalid_or_expired_token")

    if _is_user_verified(user):
        return {"status": "already_verified", "email": email}

    updated = await repositories.mark_user_email_verified(email)
    if not updated:
        raise InvalidEmailVerificationTokenError("invalid_or_expired_token")

    return {"status": "verified", "email": email}


async def send_password_reset_email(email: str) -> None:
    normalized_email = email.strip().lower()
    token = create_email_token(
        normalized_email,
        token_type="reset",
        expires_minutes=_RESET_TOKEN_EXPIRY_MINUTES,
    )
    reset_url = _build_frontend_url("/reset-password", token)
    html_body = render_template(
        "reset_password.html",
        reset_url=reset_url,
        expiry_minutes=_RESET_TOKEN_EXPIRY_MINUTES,
    )
    text_body = (
        "Använd den säkra länken för att återställa ditt lösenord.\n\n"
        f"Länken gäller i {_RESET_TOKEN_EXPIRY_MINUTES} minuter: {reset_url}\n\n"
        f"Om länken inte fungerar kan du begära en ny från inloggningssidan eller kontakta {_SUPPORT_EMAIL}."
    )

    await send_email(
        to_email=normalized_email,
        subject=_RESET_PASSWORD_SUBJECT,
        text_body=text_body,
        html_body=html_body,
    )


async def reset_password_with_token(token: str, new_password: str) -> dict[str, str]:
    email = _verify_token(
        token,
        expected_type="reset",
        error_type=InvalidPasswordResetTokenError,
    )

    user = await repositories.get_user_by_email(email)
    if not user:
        raise InvalidPasswordResetTokenError("invalid_or_expired_token")

    await models.update_user_password(user["id"], new_password)
    await repositories.revoke_refresh_tokens_for_user(user["id"])
    return {"status": "password_reset", "email": email}


async def send_invite_email(email: str, *, inviter_email: str | None = None) -> None:
    normalized_email = email.strip().lower()
    token = create_email_token(
        normalized_email,
        token_type="invite",
        expires_minutes=_INVITE_TOKEN_EXPIRY_MINUTES,
    )
    invite_url = _build_frontend_url("/invite", token)
    html_body = render_template(
        "invite_email.html",
        invite_url=invite_url,
        inviter_email=(inviter_email or "").strip().lower(),
    )
    inviter_line = (
        f"You've been invited by {inviter_email.strip().lower()} to join Aveli."
        if inviter_email and inviter_email.strip()
        else "You've been invited to join Aveli."
    )
    text_body = f"{inviter_line} Accept your invite: {invite_url}"

    await send_email(
        to_email=normalized_email,
        subject=_INVITE_EMAIL_SUBJECT,
        text_body=text_body,
        html_body=html_body,
    )


def validate_invite_token(token: str) -> str:
    return _verify_token(
        token,
        expected_type="invite",
        error_type=InvalidInviteTokenError,
    )


def _verify_token(
    token: str,
    *,
    expected_type: str,
    error_type: type[ValueError],
) -> str:
    try:
        return verify_email_token(token, expected_type=expected_type)
    except EmailTokenError as exc:
        raise error_type("invalid_or_expired_token") from exc


def _is_user_verified(user: dict[str, object]) -> bool:
    return bool(user.get("email_confirmed_at") or user.get("confirmed_at"))


def _build_verify_url(token: str) -> str:
    return _build_frontend_url("/verify", token)


def _build_frontend_url(path: str, token: str) -> str:
    base_url = (settings.frontend_base_url or _DEFAULT_FRONTEND_BASE_URL).rstrip("/")
    return f"{base_url}{path}?{urlencode({'token': token})}"
