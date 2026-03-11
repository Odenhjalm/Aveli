from __future__ import annotations

import logging
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage

from starlette.concurrency import run_in_threadpool

from ..config import settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EmailDeliveryResult:
    mode: str


class EmailDeliveryError(RuntimeError):
    pass


async def send_email(
    *,
    to_email: str,
    subject: str,
    text_body: str,
    html_body: str | None = None,
) -> EmailDeliveryResult:
    if not settings.smtp_host or not settings.smtp_from_email:
        logger.info(
            "Email delivery disabled; logging message to=%s subject=%s body=%s",
            to_email,
            subject,
            text_body,
        )
        return EmailDeliveryResult(mode="log_only")

    message = EmailMessage()
    message["Subject"] = subject
    if settings.smtp_from_name:
        message["From"] = f"{settings.smtp_from_name} <{settings.smtp_from_email}>"
    else:
        message["From"] = settings.smtp_from_email
    message["To"] = to_email.strip()
    message.set_content(text_body)
    if html_body:
        message.add_alternative(html_body, subtype="html")

    try:
        await run_in_threadpool(_send_smtp_message, message)
    except Exception as exc:  # pragma: no cover - exercised via monkeypatch in tests
        raise EmailDeliveryError("Failed to send email") from exc

    return EmailDeliveryResult(mode="sent")


def _send_smtp_message(message: EmailMessage) -> None:
    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as server:
        if settings.smtp_use_starttls:
            server.starttls()
        if settings.smtp_username or settings.smtp_password:
            server.login(settings.smtp_username or "", settings.smtp_password or "")
        server.send_message(message)


__all__ = ["EmailDeliveryError", "EmailDeliveryResult", "send_email"]
