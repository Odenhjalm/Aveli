from __future__ import annotations

import json
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone
from pathlib import Path

import pytest
from pydantic import ValidationError

from app.config import settings
from app.main import app
from app.schemas.billing import SubscriptionInterval, SubscriptionSessionRequest
from app.services import subscription_service
from app.utils import membership_status

pytestmark = pytest.mark.anyio("asyncio")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", secret)
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", secret)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = secret
    settings.stripe_test_membership_product_id = "prod_test"
    settings.stripe_test_membership_price_monthly = "price_month_test"
    settings.stripe_test_membership_price_id_yearly = "price_year_test"


def _route_paths() -> set[str]:
    return {
        route.path
        for route in app.routes
        if getattr(route, "path", None)
    }


async def test_forbidden_billing_surfaces_are_not_mounted(async_client) -> None:
    assert "/api/billing/create-subscription" in _route_paths()
    assert "/api/billing/cancel-subscription-intent" in _route_paths()
    assert "/api/billing/session-status" not in _route_paths()
    assert "/api/billing/customer-portal" not in _route_paths()
    assert "/api/billing/cancel-subscription" not in _route_paths()
    assert "/api/billing/create-checkout-session" not in _route_paths()

    for method, path in (
        ("get", "/api/billing/session-status"),
        ("post", "/api/billing/customer-portal"),
        ("post", "/api/billing/cancel-subscription"),
        ("post", "/api/billing/create-checkout-session"),
    ):
        response = await getattr(async_client, method)(path)
        assert response.status_code == 404, response.text


async def test_connect_surfaces_are_inactive(async_client, monkeypatch) -> None:
    assert "/connect/onboarding" not in _route_paths()
    assert "/connect/status" not in _route_paths()

    onboarding_resp = await async_client.post("/connect/onboarding")
    assert onboarding_resp.status_code == 404, onboarding_resp.text

    status_resp = await async_client.get("/connect/status")
    assert status_resp.status_code == 404, status_resp.text

    _set_stripe_test_env(monkeypatch)
    settings.stripe_test_webhook_secret = "whsec_test"

    def fake_construct_event(payload, sig_header, secret):
        assert sig_header == "sig_test"
        assert secret == "whsec_test"
        body = json.loads(payload)
        return {
            "id": "evt_connect_inactive",
            "type": body.get("event_type", "account.updated"),
            "data": {"object": body.get("object", body)},
        }

    async def fail_connect_handler(*args, **kwargs):
        raise AssertionError("Connect webhook handler must stay inactive")

    monkeypatch.setattr("stripe.Webhook.construct_event", fake_construct_event)
    monkeypatch.setattr(
        "app.routes.stripe_webhooks.stripe_webhook_support_service.handle_connect_event",
        fail_connect_handler,
    )

    webhook_resp = await async_client.post(
        "/api/stripe/webhook",
        content=json.dumps(
            {
                "event_type": "account.updated",
                "object": {"id": "acct_test"},
            }
        ),
        headers={"stripe-signature": "sig_test"},
    )
    assert webhook_resp.status_code == 200, webhook_resp.text
    assert webhook_resp.json() == {"status": "ok"}


async def test_membership_checkout_rejects_legacy_request_shape() -> None:
    with pytest.raises(ValidationError):
        SubscriptionSessionRequest.model_validate({"plan_interval": "month"})

    parsed = SubscriptionSessionRequest.model_validate({"interval": "month"})
    assert parsed.interval == SubscriptionInterval.month


async def test_course_checkout_rejects_polymorphic_body() -> None:
    source = (_repo_root() / "backend/app/routes/api_checkout.py").read_text(
        encoding="utf-8"
    )
    assert 'allowed_keys = {"slug"}' in source
    assert 'Course checkout accepts only {\\"slug\\": string}' in source
    assert '"type"' not in source


async def test_membership_checkout_is_order_backed_and_non_authoritative(
    monkeypatch,
) -> None:
    _set_stripe_test_env(monkeypatch)
    captured: dict[str, object] = {}

    async def fake_get_customer(user):
        captured["customer_user_id"] = user["id"]
        return "cus_test"

    async def fake_create_order(**kwargs):
        captured["order_kwargs"] = kwargs
        return {
            "id": "order_123",
            "user_id": kwargs["user_id"],
            "status": "pending",
            "amount_cents": kwargs["amount_cents"],
            "currency": kwargs["currency"],
        }

    async def fake_set_checkout_reference(**kwargs):
        captured["checkout_reference"] = kwargs

    async def fake_insert_billing_log(**kwargs):
        captured.setdefault("billing_logs", []).append(kwargs)

    async def fail_membership_write(*args, **kwargs):
        raise AssertionError("membership must not be written during checkout initiation")

    async def fake_price_accessible(price_config, stripe_context):
        return {
            "id": price_config.price_id,
            "unit_amount": 9900,
            "currency": "sek",
            "product": settings.stripe_test_membership_product_id,
            "livemode": False,
        }

    def fake_session_create(**kwargs):
        captured["session_kwargs"] = kwargs
        return {"id": "cs_test", "url": "https://checkout.stripe.com/cs_test"}

    monkeypatch.setattr(
        subscription_service,
        "_get_or_create_customer",
        fake_get_customer,
    )
    monkeypatch.setattr(
        subscription_service.orders_repo,
        "create_order",
        fake_create_order,
    )
    monkeypatch.setattr(
        subscription_service.orders_repo,
        "set_order_checkout_reference",
        fake_set_checkout_reference,
    )
    monkeypatch.setattr(
        subscription_service.membership_support_repo,
        "insert_billing_log",
        fake_insert_billing_log,
    )
    monkeypatch.setattr(
        subscription_service.memberships_repo,
        "upsert_membership_record",
        fail_membership_write,
    )
    monkeypatch.setattr(
        "stripe.checkout.Session.create",
        fake_session_create,
    )
    monkeypatch.setattr(
        subscription_service.stripe_mode,
        "resolve_stripe_context",
        lambda: SimpleNamespace(secret_key="sk_test_value", mode=SimpleNamespace(value="test")),
    )
    monkeypatch.setattr(
        subscription_service.stripe_mode,
        "resolve_membership_price",
        lambda interval, context: SimpleNamespace(
            price_id="price_month_test",
            env_var="STRIPE_TEST_MEMBERSHIP_PRICE_MONTHLY",
        ),
    )
    monkeypatch.setattr(
        subscription_service.stripe_mode,
        "ensure_price_accessible",
        fake_price_accessible,
    )

    payload = await subscription_service.create_subscription_checkout(
        {"id": "user_123", "email": "member@example.com", "display_name": "Member"},
        SubscriptionInterval.month,
    )

    assert payload.url == "https://checkout.stripe.com/cs_test"
    assert payload.session_id == "cs_test"
    assert payload.order_id == "order_123"
    assert captured["order_kwargs"]["user_id"] == "user_123"
    assert captured["order_kwargs"]["order_type"] == "subscription"
    assert captured["session_kwargs"]["metadata"]["checkout_type"] == "membership"
    assert captured["session_kwargs"]["metadata"]["source"] == "purchase"
    assert captured["session_kwargs"]["metadata"]["order_id"] == "order_123"


async def test_cancel_intent_is_non_authoritative(monkeypatch) -> None:
    _set_stripe_test_env(monkeypatch)
    captured: dict[str, object] = {}

    async def fake_resolve_membership_subscription_id(user_id, *, requested_subscription_id=None):
        captured["resolved_user_id"] = user_id
        captured["requested_subscription_id"] = requested_subscription_id
        return "sub_test"

    async def fake_insert_billing_log(**kwargs):
        captured.setdefault("billing_logs", []).append(kwargs)

    def fake_modify(subscription_id, **kwargs):
        captured["subscription_id"] = subscription_id
        captured["modify_kwargs"] = kwargs
        return {
            "id": subscription_id,
            "cancel_at_period_end": True,
            "current_period_end": int(
                (datetime.now(timezone.utc) + timedelta(days=30)).timestamp()
            ),
        }

    async def fail_membership_write(*args, **kwargs):
        raise AssertionError("cancel intent must not mutate memberships")

    monkeypatch.setattr(
        subscription_service,
        "_resolve_membership_subscription_id",
        fake_resolve_membership_subscription_id,
    )
    monkeypatch.setattr(
        subscription_service.membership_support_repo,
        "insert_billing_log",
        fake_insert_billing_log,
    )
    monkeypatch.setattr(
        subscription_service.memberships_repo,
        "upsert_membership_record",
        fail_membership_write,
    )
    monkeypatch.setattr(
        "stripe.Subscription.modify",
        fake_modify,
    )
    monkeypatch.setattr(
        subscription_service.stripe_mode,
        "resolve_stripe_context",
        lambda: SimpleNamespace(secret_key="sk_test_value"),
    )

    payload = await subscription_service.cancel_subscription_intent(
        {"id": "user_123"},
        subscription_id="sub_test",
    )

    assert payload["ok"] is True
    assert payload["subscription_id"] == "sub_test"
    assert payload["cancel_at_period_end"] is True
    assert "status" not in payload
    assert captured["resolved_user_id"] == "user_123"
    assert captured["requested_subscription_id"] == "sub_test"
    assert captured["subscription_id"] == "sub_test"
    assert captured["modify_kwargs"]["cancel_at_period_end"] is True


async def test_invoice_settlement_records_payment_before_membership_state(
    monkeypatch,
) -> None:
    call_order: list[str] = []
    order = {
        "id": "order_123",
        "user_id": "user_123",
        "amount_cents": 9900,
        "currency": "sek",
        "status": "pending",
    }

    async def fake_resolve_order(payload):
        call_order.append("resolve_order")
        return order

    async def fake_set_reference(**kwargs):
        call_order.append("set_order_reference")

    async def fake_mark_order_paid(order_id, **kwargs):
        call_order.append("mark_order_paid")
        return {**order, "status": "paid"}

    async def fake_record_payment(**kwargs):
        call_order.append("record_payment")

    async def fake_apply_membership_state(*args, **kwargs):
        call_order.append("apply_membership_state")

    monkeypatch.setattr(
        subscription_service,
        "_resolve_membership_order_from_invoice",
        fake_resolve_order,
    )
    monkeypatch.setattr(
        subscription_service.orders_repo,
        "set_order_checkout_reference",
        fake_set_reference,
    )
    monkeypatch.setattr(
        subscription_service.payments_repo,
        "mark_order_paid",
        fake_mark_order_paid,
    )
    monkeypatch.setattr(
        subscription_service.payments_repo,
        "record_payment",
        fake_record_payment,
    )
    monkeypatch.setattr(
        subscription_service,
        "_apply_membership_state",
        fake_apply_membership_state,
    )

    await subscription_service.process_event(
        {
            "type": "invoice.payment_succeeded",
            "data": {
                "object": {
                    "id": "in_123",
                    "subscription": "sub_123",
                    "customer": "cus_123",
                    "payment_intent": "pi_123",
                    "amount_paid": 9900,
                    "currency": "sek",
                    "lines": {
                        "data": [
                            {"period": {"start": 1, "end": 2}},
                        ]
                    },
                }
            },
        }
    )

    assert call_order == [
        "resolve_order",
        "set_order_reference",
        "mark_order_paid",
        "record_payment",
        "apply_membership_state",
    ]


async def test_membership_access_rule_matches_contract() -> None:
    now = datetime.now(timezone.utc)

    assert membership_status.is_membership_active("active", None, now=now) is True
    assert (
        membership_status.is_membership_active(
            "canceled",
            now + timedelta(days=1),
            now=now,
        )
        is True
    )
    assert (
        membership_status.is_membership_active(
            "canceled",
            now - timedelta(seconds=1),
            now=now,
        )
        is False
    )
    assert membership_status.is_membership_active("inactive", None, now=now) is False
    assert membership_status.is_membership_active("past_due", None, now=now) is False
    assert membership_status.is_membership_active("expired", None, now=now) is False
    assert membership_status.is_membership_active("trialing", None, now=now) is False


async def test_legacy_backend_surfaces_are_removed_from_source() -> None:
    root = _repo_root()

    assert not (root / "backend/app/services/universal_checkout_service.py").exists()
    assert not (root / "backend/app/repositories/subscriptions.py").exists()
    assert not (root / "backend/app/services/billing_portal_service.py").exists()

    billing_source = (root / "backend/app/routes/billing.py").read_text(encoding="utf-8")
    assert "session-status" not in billing_source
    assert "customer-portal" not in billing_source
    assert '"/cancel-subscription"' not in billing_source
    assert "cancel-subscription-intent" in billing_source

    billing_schema = (root / "backend/app/schemas/billing.py").read_text(encoding="utf-8")
    assert "plan_interval" not in billing_schema
    assert "SessionStatusResponse" not in billing_schema
    assert "SubscriptionCancelResponse" not in billing_schema

    memberships_source = (
        root / "backend/app/repositories/memberships.py"
    ).read_text(encoding="utf-8")
    assert "get_latest_subscription" not in memberships_source


async def test_frontend_contract_gate_scan() -> None:
    root = _repo_root()

    for deleted_path in (
        "frontend/lib/features/payments/presentation/claim_purchase_page.dart",
        "frontend/lib/features/payments/presentation/order_history_page.dart",
        "frontend/lib/data/repositories/orders_repository.dart",
        "frontend/lib/features/payments/widgets/payment_panel.dart",
        "frontend/lib/features/paywall/presentation/subscription_webview_page.dart",
        "frontend/lib/features/paywall/data/customer_portal_api.dart",
        "frontend/lib/features/payments/data/payments_repository.dart",
        "frontend/lib/features/payments/application/payments_providers.dart",
    ):
        assert not (root / deleted_path).exists(), deleted_path

    app_router = (root / "frontend/lib/core/routing/app_router.dart").read_text(
        encoding="utf-8"
    )
    route_manifest = (
        root / "frontend/lib/core/routing/route_manifest.dart"
    ).read_text(encoding="utf-8")
    route_paths = (root / "frontend/lib/core/routing/route_paths.dart").read_text(
        encoding="utf-8"
    )
    app_routes = (root / "frontend/lib/core/routing/app_routes.dart").read_text(
        encoding="utf-8"
    )
    api_paths = (root / "frontend/lib/api/api_paths.dart").read_text(encoding="utf-8")
    checkout_api = (
        root / "frontend/lib/features/paywall/data/checkout_api.dart"
    ).read_text(encoding="utf-8")
    return_page = (
        root / "frontend/landing/pages/checkout/return.tsx"
    ).read_text(encoding="utf-8")

    assert "/api/billing/create-subscription" in api_paths
    assert "/api/checkout/create" in api_paths
    assert "/orders" not in api_paths
    assert "profileSubscriptionPortal" not in app_router
    assert "AppRoute.orders" not in app_router
    assert "AppRoute.claim" not in app_router
    assert "RoutePath.orders" not in route_manifest
    assert "RoutePath.claim" not in route_manifest
    assert "profileSubscriptionPortal" not in route_paths
    assert "orders =" not in route_paths
    assert "claim =" not in route_paths
    assert "profileSubscriptionPortal" not in app_routes
    assert "orders =" not in app_routes
    assert "claim =" not in app_routes
    assert "billingCreateSubscription" in checkout_api
    assert "checkoutCreate" in checkout_api
    assert "subscription_status" not in return_page
    assert "session-status" not in return_page


async def test_bundle_guardrail_source_scan() -> None:
    root = _repo_root()

    bundle_route = root / "backend/app/routes/course_bundles.py"
    bundle_service = root / "backend/app/services/course_bundles_service.py"
    webhook_route = root / "backend/app/routes/stripe_webhooks.py"
    bundle_webhook_service = (
        root / "backend/app/services/stripe_webhook_bundle_service.py"
    )

    assert bundle_route.exists()
    assert bundle_service.exists()
    assert bundle_webhook_service.exists()

    bundle_service_source = bundle_service.read_text(encoding="utf-8")
    webhook_source = webhook_route.read_text(encoding="utf-8")
    bundle_webhook_source = bundle_webhook_service.read_text(encoding="utf-8")

    assert "upsert_membership_record" not in bundle_service_source
    assert "grant_bundle_entitlements" not in webhook_source
    assert "grant_bundle_entitlements" in bundle_webhook_source
