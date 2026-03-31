from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app import schemas


def _timestamp() -> datetime:
    return datetime.now(timezone.utc)


def test_session_create_requires_explicit_canonical_fields() -> None:
    with pytest.raises(ValidationError):
        schemas.SessionCreateRequest(title="Session")


def test_session_create_accepts_explicit_canonical_fields() -> None:
    payload = schemas.SessionCreateRequest(
        title="Session",
        description="Explicit contract",
        start_at=_timestamp(),
        end_at=_timestamp(),
        capacity=12,
        price_cents=1500,
        currency="sek",
        visibility=schemas.SessionVisibility.published,
        recording_url=None,
        stripe_price_id=None,
    )

    assert payload.price_cents == 1500
    assert payload.currency == "sek"
    assert payload.visibility == schemas.SessionVisibility.published


def test_session_slot_create_requires_explicit_seats_total() -> None:
    with pytest.raises(ValidationError):
        schemas.SessionSlotCreateRequest(
            start_at=_timestamp(),
            end_at=_timestamp(),
        )


def test_session_currency_rejects_non_canonical_values() -> None:
    with pytest.raises(ValidationError):
        schemas.SessionCreateRequest(
            title="Session",
            description="Explicit contract",
            start_at=_timestamp(),
            end_at=_timestamp(),
            capacity=12,
            price_cents=1500,
            currency="SEK",
            visibility=schemas.SessionVisibility.published,
            recording_url=None,
            stripe_price_id=None,
        )


def test_session_update_currency_rejects_non_canonical_values() -> None:
    with pytest.raises(ValidationError):
        schemas.SessionUpdateRequest(currency=" sek ")
