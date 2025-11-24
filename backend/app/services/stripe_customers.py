from __future__ import annotations

from typing import Mapping, Any

import stripe
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..repositories import stripe_customers as stripe_customers_repo


async def ensure_customer_id(user: Mapping[str, Any]) -> str:
    user_id = str(user.get("id")) if user and user.get("id") is not None else None
    if not user_id:
        raise RuntimeError("User id is required to ensure Stripe customer")

    existing = await stripe_customers_repo.get_customer_id_for_user(user_id)
    if existing:
        return existing

    api_key = settings.stripe_secret_key
    if not api_key:
        raise RuntimeError("Stripe is not configured")
    stripe.api_key = api_key

    def _create_customer() -> dict[str, Any]:
        return stripe.Customer.create(
            email=user.get("email"),
            name=user.get("display_name"),
            metadata={"user_id": user_id},
        )

    customer = await run_in_threadpool(_create_customer)
    customer_id = customer.get("id") if isinstance(customer, Mapping) else None
    if not isinstance(customer_id, str):
        raise RuntimeError("Stripe did not return a customer id")

    await stripe_customers_repo.upsert_customer(user_id, customer_id)
    return customer_id


__all__ = ["ensure_customer_id"]
