from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

from app import db
from app.auth import get_current_user
from app.main import app
from app.routes import stripe_webhooks
from app.services import (
    notification_service,
    notifications_dispatcher_worker,
    push_provider,
)
from tests.test_course_drip_worker_selection import (
    _apply_baseline_v2_slots,
    _baseline_v2_connection,
    _create_enrollment,
    _insert_auth_subject,
    _insert_course,
    _insert_lessons,
    _run_course_drip_worker_once,
)


pytestmark = pytest.mark.anyio("asyncio")


async def _with_worker_pool(database_conninfo: str, *modules):
    worker_pool = db.ContextAwareAsyncConnectionPool(
        conninfo=database_conninfo,
        min_size=1,
        max_size=1,
        check=db.ContextAwareAsyncConnectionPool.check_connection,
        open=False,
    )
    originals = [(module, module.pool) for module in modules]
    for module, _ in originals:
        module.pool = worker_pool
    await worker_pool.open(wait=True)
    return worker_pool, originals


async def _close_worker_pool(worker_pool, originals) -> None:
    for module, original_pool in originals:
        module.pool = original_pool
    if not worker_pool.closed:
        await worker_pool.close()


def _notification_rows(conn) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select id::text as id,
                   user_id::text as user_id,
                   type,
                   payload_json,
                   dedup_key
              from app.notifications
             order by created_at asc, id asc
            """
        )
        return [dict(row) for row in cur.fetchall()]


def _delivery_rows(conn) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select id::text as id,
                   notification_id::text as notification_id,
                   channel,
                   status,
                   attempts,
                   last_attempt_at,
                   error_text
              from app.notification_deliveries
             order by id asc
            """
        )
        return [dict(row) for row in cur.fetchall()]


def _device_rows(conn) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select id::text as id,
                   user_id::text as user_id,
                   push_token,
                   platform,
                   active
              from app.user_devices
             order by created_at asc, id asc
            """
        )
        return [dict(row) for row in cur.fetchall()]


def _push_delivery_rows(conn) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select pdd.delivery_id::text as delivery_id,
                   pdd.notification_id::text as notification_id,
                   pdd.device_id::text as device_id,
                   ud.push_token,
                   pdd.status,
                   pdd.attempts,
                   pdd.provider_message_id,
                   pdd.error_text
              from app.notification_push_device_deliveries as pdd
              join app.user_devices as ud
                on ud.id = pdd.device_id
             order by ud.push_token asc
            """
        )
        return [dict(row) for row in cur.fetchall()]


class _FakePushProvider:
    def __init__(self, *, fail_tokens: set[str] | None = None) -> None:
        self.fail_tokens = fail_tokens or set()
        self.sent: list[dict[str, object]] = []

    async def send(
        self,
        *,
        token: str,
        message: push_provider.PushMessage,
    ) -> str | None:
        self.sent.append(
            {
                "token": token,
                "title": message.title,
                "body": message.body,
                "data": dict(message.data),
            }
        )
        if token in self.fail_tokens:
            raise RuntimeError(f"push rejected for {token}")
        return f"provider-message-{token}"


def _insert_pending_course_order(
    conn,
    *,
    order_id: str,
    user_id: str,
    course_id: str,
    checkout_id: str,
    payment_intent: str,
    price_id: str,
) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            insert into app.orders (
                id,
                user_id,
                course_id,
                order_type,
                amount_cents,
                currency,
                status,
                stripe_checkout_id,
                stripe_payment_intent,
                metadata
            )
            values (
                %s,
                %s,
                %s,
                'one_off',
                1000,
                'sek',
                'pending',
                %s,
                %s,
                %s
            )
            """,
            (
                order_id,
                user_id,
                course_id,
                checkout_id,
                payment_intent,
                Jsonb({"price_id": price_id}),
            ),
        )


async def test_create_notification_is_deduped_and_dispatcher_marks_sent():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
            notifications_dispatcher_worker,
        )
        try:
            first = await notification_service.create_notification(
                user_id,
                "manual_test",
                {"source": "test"},
                "test:dedup-key",
            )
            second = await notification_service.create_notification(
                user_id,
                "manual_test",
                {"source": "test"},
                "test:dedup-key",
            )

            assert first.created is True
            assert first.delivery_count == 1
            assert second.created is False
            assert second.notification["id"] == first.notification["id"]
            assert len(_notification_rows(conn)) == 1
            assert len(_delivery_rows(conn)) == 1
            assert _delivery_rows(conn)[0]["status"] == "pending"

            processed = await notifications_dispatcher_worker.run_once()

            deliveries = _delivery_rows(conn)
            assert processed == 1
            assert deliveries[0]["status"] == "sent"
            assert deliveries[0]["attempts"] == 1
            assert deliveries[0]["last_attempt_at"] is not None
            assert deliveries[0]["error_text"] is None
        finally:
            await _close_worker_pool(worker_pool, originals)


async def test_device_registration_is_idempotent_and_deactivation_is_scoped():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        other_user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")
        _insert_auth_subject(conn, other_user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        try:
            first = await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-1",
                platform="ios",
            )
            second = await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-1",
                platform="android",
            )
            rows = _device_rows(conn)

            assert first.device["id"] == second.device["id"]
            assert len(rows) == 1
            assert rows[0]["push_token"] == "push-token-1"
            assert rows[0]["platform"] == "android"
            assert rows[0]["active"] is True

            wrong_user = await notification_service.deactivate_device(
                user_id=other_user_id,
                device_id=str(rows[0]["id"]),
            )
            assert wrong_user is False
            assert _device_rows(conn)[0]["active"] is True

            deactivated = await notification_service.deactivate_device(
                user_id=user_id,
                device_id=str(rows[0]["id"]),
            )
            assert deactivated is True
            assert _device_rows(conn)[0]["active"] is False
        finally:
            await _close_worker_pool(worker_pool, originals)


async def test_notification_routes_register_device_and_list_backend_truth():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        async def _fake_current_user():
            return {"id": user_id, "role": "learner"}

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        app.dependency_overrides[get_current_user] = _fake_current_user
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport,
                base_url="http://testserver",
            ) as client:
                registered = await client.post(
                    "/notifications/devices",
                    json={"push_token": "route-token", "platform": "ios"},
                )
                assert registered.status_code == 201, registered.text
                registered_payload = registered.json()
                assert registered_payload["push_token"] == "route-token"
                assert registered_payload["active"] is True

                await notification_service.create_notification(
                    user_id,
                    "lesson_drip",
                    {
                        "course_id": str(uuid4()),
                        "lesson_id": str(uuid4()),
                        "title": "Route lesson",
                    },
                    "lesson-drip:route-list",
                )

                listed = await client.get("/notifications")
                assert listed.status_code == 200, listed.text
                items = listed.json()["items"]
                assert len(items) == 1
                assert items[0]["type"] == "lesson_drip"
                assert items[0]["payload"]["title"] == "Route lesson"

                deleted = await client.delete(
                    f"/notifications/devices/{registered_payload['id']}"
                )
                assert deleted.status_code == 204, deleted.text
                assert _device_rows(conn)[0]["active"] is False
        finally:
            app.dependency_overrides.pop(get_current_user, None)
            await _close_worker_pool(worker_pool, originals)


async def test_push_dispatcher_sends_to_all_active_devices_and_records_status():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        fake_push = _FakePushProvider()
        push_provider.set_push_provider_for_tests(fake_push)
        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
            notifications_dispatcher_worker,
        )
        try:
            await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-a",
                platform="ios",
            )
            await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-b",
                platform="android",
            )
            await notification_service.create_notification(
                user_id,
                "lesson_drip",
                {
                    "course_id": str(uuid4()),
                    "lesson_id": str(uuid4()),
                    "title": "Opened lesson",
                },
                "lesson-drip:multi-device",
                channels=("push",),
            )

            processed = await notifications_dispatcher_worker.run_once()

            assert processed == 1
            assert [item["token"] for item in fake_push.sent] == [
                "push-token-a",
                "push-token-b",
            ]
            assert {item["title"] for item in fake_push.sent} == {
                "New lesson unlocked"
            }
            assert {item["body"] for item in fake_push.sent} == {"Opened lesson"}
            deliveries = _delivery_rows(conn)
            assert deliveries[0]["status"] == "sent"
            assert deliveries[0]["attempts"] == 1
            push_rows = _push_delivery_rows(conn)
            assert [row["status"] for row in push_rows] == ["sent", "sent"]
            assert [row["attempts"] for row in push_rows] == [1, 1]

            rerun = await notifications_dispatcher_worker.run_once()
            assert rerun == 0
            assert len(fake_push.sent) == 2
        finally:
            push_provider.set_push_provider_for_tests(None)
            await _close_worker_pool(worker_pool, originals)


async def test_push_dispatcher_is_fail_safe_per_device():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        fake_push = _FakePushProvider(fail_tokens={"push-token-b"})
        push_provider.set_push_provider_for_tests(fake_push)
        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
            notifications_dispatcher_worker,
        )
        try:
            await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-a",
                platform="ios",
            )
            await notification_service.register_device(
                user_id=user_id,
                push_token="push-token-b",
                platform="android",
            )
            await notification_service.create_notification(
                user_id,
                "lesson_drip",
                {
                    "course_id": str(uuid4()),
                    "lesson_id": str(uuid4()),
                    "title": "Opened lesson",
                },
                "lesson-drip:partial-failure",
                channels=("push",),
            )

            processed = await notifications_dispatcher_worker.run_once()

            assert processed == 1
            assert [item["token"] for item in fake_push.sent] == [
                "push-token-a",
                "push-token-b",
            ]
            deliveries = _delivery_rows(conn)
            assert deliveries[0]["status"] == "failed"
            assert "push-token-b" in str(deliveries[0]["error_text"])
            push_rows = _push_delivery_rows(conn)
            assert [(row["push_token"], row["status"]) for row in push_rows] == [
                ("push-token-a", "sent"),
                ("push-token-b", "failed"),
            ]
        finally:
            push_provider.set_push_provider_for_tests(None)
            await _close_worker_pool(worker_pool, originals)


async def test_drip_unlock_creates_notification_record():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        course_id = str(uuid4())
        user_id = str(uuid4())
        granted_at = datetime(2026, 1, 1, tzinfo=timezone.utc)

        _insert_course(
            conn,
            course_id=course_id,
            slug="notification-drip-course",
            required_enrollment_source="purchase",
            drip_enabled=True,
            drip_interval_days=2,
        )
        _insert_lessons(conn, course_id, count=3)
        enrollment = _create_enrollment(
            conn,
            enrollment_id=str(uuid4()),
            user_id=user_id,
            course_id=course_id,
            source="purchase",
            granted_at=granted_at,
        )

        advanced = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )

        notifications = _notification_rows(conn)
        assert advanced == 1
        assert len(notifications) == 1
        assert notifications[0]["user_id"] == user_id
        assert notifications[0]["type"] == "lesson_drip"
        assert notifications[0]["payload_json"]["course_id"] == course_id
        assert notifications[0]["payload_json"]["lesson_id"] is not None
        assert notifications[0]["payload_json"]["title"] == "lesson-3"
        assert notifications[0]["dedup_key"] == (
            f"lesson_drip:{enrollment['id']}:{notifications[0]['payload_json']['lesson_id']}"
        )
        deliveries = _delivery_rows(conn)
        assert sorted((row["channel"], row["status"]) for row in deliveries) == [
            ("in_app", "pending"),
            ("push", "pending"),
        ]

        duplicate = await _run_course_drip_worker_once(
            database_conninfo,
            now=granted_at + timedelta(days=10),
        )
        assert duplicate == 0
        assert len(_notification_rows(conn)) == 1


async def test_stripe_course_webhook_fulfillment_creates_notification_record():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        course_id = str(uuid4())
        user_id = str(uuid4())
        order_id = str(uuid4())
        checkout_id = "cs_test_notification"
        payment_intent = "pi_test_notification"
        price_id = "price_notification"

        _insert_auth_subject(conn, user_id, role="learner")
        _insert_course(
            conn,
            course_id=course_id,
            slug="notification-stripe-course",
            required_enrollment_source="purchase",
            drip_enabled=False,
            drip_interval_days=None,
        )
        _insert_lessons(conn, course_id, count=2)
        _insert_pending_course_order(
            conn,
            order_id=order_id,
            user_id=user_id,
            course_id=course_id,
            checkout_id=checkout_id,
            payment_intent=payment_intent,
            price_id=price_id,
        )

        session = {
            "id": checkout_id,
            "amount_total": 1000,
            "currency": "sek",
            "payment_intent": payment_intent,
            "client_reference_id": order_id,
            "metadata": {
                "checkout_type": "course",
                "order_id": order_id,
                "user_id": user_id,
                "price_id": price_id,
            },
        }
        order = {
            "id": order_id,
            "user_id": user_id,
            "course_id": course_id,
            "bundle_id": None,
            "order_type": "one_off",
            "amount_cents": 1000,
            "currency": "sek",
            "status": "pending",
            "stripe_checkout_id": checkout_id,
            "stripe_payment_intent": payment_intent,
            "stripe_subscription_id": None,
            "stripe_customer_id": None,
            "metadata": {"price_id": price_id},
        }

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            stripe_webhooks,
        )
        try:
            await stripe_webhooks._fulfill_course_checkout_order(
                order=order,
                session=session,
                event_type="checkout.session.completed",
            )
        finally:
            await _close_worker_pool(worker_pool, originals)

        notifications = _notification_rows(conn)
        assert len(notifications) == 1
        assert notifications[0]["user_id"] == user_id
        assert notifications[0]["type"] == "stripe_course_purchase_fulfilled"
        assert notifications[0]["dedup_key"] == (
            f"stripe_course_purchase_fulfilled:{order_id}"
        )
        assert _delivery_rows(conn)[0]["status"] == "pending"
