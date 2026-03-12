from __future__ import annotations

import logging
from dataclasses import dataclass

import resend
from starlette.concurrency import run_in_threadpool

from ..config import settings

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class EmailDeliveryResult:
    mode: str


class EmailDeliveryError(RuntimeError):
    pass


async def send_email(
    to_email: str,
    subject: str,
    text_body: str | None = None,
    html_body: str | None = None,
) -> EmailDeliveryResult:
    recipient = to_email.strip()
    if text_body is None and html_body is None:
        logger.error(
            "Email delivery failed due to missing body to=%s subject=%s",
            recipient,
            subject,
        )
        raise EmailDeliveryError("Failed to send email")

    if not settings.resend_api_key or not settings.email_from:
        logger.info(
            "Email delivery disabled; logging message to=%s subject=%s text_body=%s html_body=%s",
            recipient,
            subject,
            text_body,
            html_body,
        )
        return EmailDeliveryResult(mode="log_only")

    payload: dict[str, object] = {
        "from": settings.email_from,
        "to": [recipient],
        "subject": subject,
    }
    if text_body is not None:
        payload["text"] = text_body
    if html_body is not None:
        payload["html"] = html_body

    try:
        await run_in_threadpool(_send_resend_message, payload)
    except Exception as exc:  # pragma: no cover - exercised via monkeypatch in tests
        logger.exception(
            "Failed to send email via Resend to=%s subject=%s",
            recipient,
            subject,
        )
        raise EmailDeliveryError("Failed to send email") from exc

    return EmailDeliveryResult(mode="sent")


def _send_resend_message(payload: dict[str, object]) -> None:
    resend.api_key = settings.resend_api_key
    resend.Emails.send(payload)


__all__ = ["EmailDeliveryError", "EmailDeliveryResult", "send_email"]
