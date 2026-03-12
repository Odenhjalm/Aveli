#!/usr/bin/env python3
"""Manual smoke test for the Resend-backed email transport."""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from app.services.email_service import EmailDeliveryError, send_email  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send a manual Resend transport test email.")
    parser.add_argument("recipient_email", help="Recipient email address")
    return parser.parse_args()


async def _main(recipient_email: str) -> int:
    try:
        result = await send_email(
            recipient_email,
            "Aveli Resend test",
            "This is a manual smoke test for the Aveli Resend transport.",
        )
    except EmailDeliveryError as exc:
        print(f"error={exc}", file=sys.stderr)
        return 1

    print(f"mode={result.mode}")
    return 0


def main() -> int:
    args = parse_args()
    return asyncio.run(_main(args.recipient_email))


if __name__ == "__main__":
    raise SystemExit(main())
