from __future__ import annotations

from urllib.parse import urlencode

from ..config import settings
from ..db import pool
from .email_service import send_email
from .email_templates import render_template
from .email_tokens import create_verification_token

_DEFAULT_FRONTEND_BASE_URL = "https://app.aveli.app"
_VERIFY_EMAIL_SUBJECT = "Verify your Aveli account"


def _build_verify_url(token: str) -> str:
    base_url = (settings.frontend_base_url or _DEFAULT_FRONTEND_BASE_URL).rstrip("/")
    return f"{base_url}/verify?{urlencode({'token': token})}"


async def send_verification_email(email: str) -> None:
    recipient = email.strip().lower()
    token = create_verification_token(recipient)
    verify_url = _build_verify_url(token)
    html_body = render_template("verify_email.html", verify_url=verify_url)
    text_body = f"Welcome to Aveli. Verify your account: {verify_url}"

    await send_email(
        to_email=recipient,
        subject=_VERIFY_EMAIL_SUBJECT,
        text_body=text_body,
        html_body=html_body,
    )


async def mark_email_verified(email: str) -> bool:
    normalized_email = email.strip().lower()
    async with pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE auth.users
                   SET email_confirmed_at = COALESCE(email_confirmed_at, now()),
                       confirmed_at = COALESCE(confirmed_at, now()),
                       raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                           || '{"email_verified": true}'::jsonb,
                       raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb)
                           || '{"email_verified": true}'::jsonb,
                       updated_at = now()
                 WHERE lower(email) = lower(%s)
                 RETURNING id
                """,
                (normalized_email,),
            )
            row = await cur.fetchone()
            if row is None:
                await conn.rollback()
                return False
            await conn.commit()
            return True
