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
                   dedup_key,
                   read_at
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


def _preference_rows(conn) -> list[dict[str, object]]:
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(
            """
            select user_id::text as user_id,
                   type,
                   push_enabled,
                   in_app_enabled
              from app.notification_preferences
             order by user_id asc, type asc
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
                "message",
                {
                    "thread_id": "thread-1",
                    "message_preview": "Hej fran test",
                },
                "test:dedup-key",
            )
            second = await notification_service.create_notification(
                user_id,
                "message",
                {
                    "thread_id": "thread-1",
                    "message_preview": "Hej fran test",
                },
                "test:dedup-key",
            )

            assert first.created is True
            assert first.delivery_count == 1
            assert second.created is False
            assert second.notification["id"] == first.notification["id"]
            assert len(_notification_rows(conn)) == 1
            assert len(_delivery_rows(conn)) == 1
            assert _delivery_rows(conn)[0]["channel"] == "in_app"
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


async def test_notification_contract_rejects_invalid_payload_before_storage():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        try:
            with pytest.raises(ValueError, match="lesson_id is required"):
                await notification_service.create_notification(
                    user_id,
                    "lesson_drip",
                    {"course_id": str(uuid4())},
                    "lesson-drip:invalid",
                )

            assert _notification_rows(conn) == []
            assert _delivery_rows(conn) == []
        finally:
            await _close_worker_pool(worker_pool, originals)


async def test_notification_contract_canonicalizes_payload_and_policy_channels():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        try:
            result = await notification_service.create_notification(
                user_id,
                "lesson_drip",
                {
                    "course_id": str(uuid4()),
                    "lesson_id": str(uuid4()),
                    "title": "  Lesson title  ",
                    "legacy_extra": "not canonical",
                },
                "lesson-drip:canonical-policy",
                channels=("email",),
            )

            notifications = _notification_rows(conn)
            deliveries = _delivery_rows(conn)
            assert result.delivery_count == 2
            assert notifications[0]["type"] == "lesson_drip"
            assert set(notifications[0]["payload_json"]) == {
                "course_id",
                "lesson_id",
                "title",
            }
            assert notifications[0]["payload_json"]["title"] == "Lesson title"
            assert sorted(row["channel"] for row in deliveries) == ["in_app", "push"]
            assert await notification_service.resolve_notification_channels(
                "message",
                user_id,
            ) == ("in_app",)
        finally:
            await _close_worker_pool(worker_pool, originals)


async def test_notification_preferences_default_and_user_override_channels():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        try:
            assert await notification_service.resolve_notification_channels(
                "lesson_drip",
                user_id,
            ) == ("in_app", "push")
            assert _preference_rows(conn) == []

            result = await notification_service.set_notification_preference(
                user_id=user_id,
                type="lesson_drip",
                push_enabled=False,
                in_app_enabled=True,
            )
            assert result.preference["push_enabled"] is False
            assert result.preference["in_app_enabled"] is True
            assert await notification_service.resolve_notification_channels(
                "lesson_drip",
                user_id,
            ) == ("in_app",)

            created = await notification_service.create_notification(
                user_id,
                "lesson_drip",
                {
                    "course_id": str(uuid4()),
                    "lesson_id": str(uuid4()),
                    "title": "Preference lesson",
                },
                "lesson-drip:preference-policy",
            )
            assert created.delivery_count == 1
            assert [row["channel"] for row in _delivery_rows(conn)] == ["in_app"]

            await notification_service.set_notification_preference(
                user_id=user_id,
                type="message",
                push_enabled=True,
                in_app_enabled=False,
            )
            assert await notification_service.resolve_notification_channels(
                "message",
                user_id,
            ) == ("push",)

            message = await notification_service.create_notification(
                user_id,
                "message",
                {
                    "thread_id": "thread-preference",
                    "message_preview": "Preference preview",
                },
                "message:preference-policy",
            )
            message_deliveries = [
                row
                for row in _delivery_rows(conn)
                if row["notification_id"] == message.notification["id"]
            ]
            assert message.delivery_count == 1
            assert [row["channel"] for row in message_deliveries] == ["push"]

            await notification_service.set_notification_preference(
                user_id=user_id,
                type="purchase",
                push_enabled=False,
                in_app_enabled=False,
            )
            assert await notification_service.resolve_notification_channels(
                "purchase",
                user_id,
            ) == ()

            disabled = await notification_service.create_notification(
                user_id,
                "purchase",
                {
                    "product_id": "membership",
                    "amount": 1000,
                    "currency": "SEK",
                },
                "purchase:preference-disabled",
            )
            disabled_deliveries = [
                row
                for row in _delivery_rows(conn)
                if row["notification_id"] == disabled.notification["id"]
            ]
            assert disabled.created is True
            assert disabled.delivery_count == 0
            assert disabled_deliveries == []
        finally:
            await _close_worker_pool(worker_pool, originals)


async def test_notification_header_read_model_maps_supported_types_without_raw_payload():
    with _baseline_v2_connection() as (conn, database_conninfo):
        _apply_baseline_v2_slots(conn)
        user_id = str(uuid4())
        _insert_auth_subject(conn, user_id, role="learner")

        worker_pool, originals = await _with_worker_pool(
            database_conninfo,
            notification_service,
        )
        try:
            lesson_id = str(uuid4())
            await notification_service.create_notification(
                user_id,
                "lesson_drip",
                {
                    "course_id": str(uuid4()),
                    "lesson_id": lesson_id,
                },
                "lesson-drip:header-model",
            )
            await notification_service.create_notification(
                user_id,
                "purchase",
                {
                    "product_id": "membership",
                    "amount": 1000,
                    "currency": "sek",
                },
                "purchase:header-model",
            )
            await notification_service.create_notification(
                user_id,
                "message",
                {
                    "thread_id": "thread-header-model",
                    "message_preview": "Nytt svar i tråden",
                },
                "message:header-model",
            )

            read_model = await notification_service.list_notification_header_read_model(
                user_id=user_id,
            )

            assert read_model.show_notifications_bar is True
            assert len(read_model.notifications) == 3
            by_title = {
                notification["title"]: notification
                for notification in read_model.notifications
            }
            assert set(by_title) == {
                "Ny lektion är upplåst",
                "Köpet är klart",
                "Nytt meddelande",
            }
            assert by_title["Ny lektion är upplåst"] == {
                "id": by_title["Ny lektion är upplåst"]["id"],
                "title": "Ny lektion är upplåst",
                "subtitle": None,
                "cta_label": "Öppna lektionen",
                "cta_url": f"/lesson/{lesson_id}",
            }
            assert by_title["Köpet är klart"] == {
                "id": by_title["Köpet är klart"]["id"],
                "title": "Köpet är klart",
                "subtitle": "Din åtkomst är aktiverad.",
                "cta_label": "Visa kurser",
                "cta_url": "/courses",
            }
            assert by_title["Nytt meddelande"] == {
                "id": by_title["Nytt meddelande"]["id"],
                "title": "Nytt meddelande",
                "subtitle": "Nytt svar i tråden",
                "cta_label": "Öppna meddelanden",
                "cta_url": "/messages",
            }
            for notification in read_model.notifications:
                assert set(notification) == {
                    "id",
                    "title",
                    "subtitle",
                    "cta_label",
                    "cta_url",
                }
                assert "type" not in notification
                assert "payload" not in notification
                assert str(notification["id"]).strip()
                assert notification["title"].strip()
                if notification["subtitle"] is not None:
                    assert notification["subtitle"].strip()
                if notification["cta_label"] is not None:
                    assert notification["cta_label"].strip()
                    assert notification["cta_url"] is not None
                    assert notification["cta_url"].strip()
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

                empty_list = await client.get("/notifications")
                assert empty_list.status_code == 200, empty_list.text
                assert empty_list.json() == {
                    "show_notifications_bar": False,
                    "notifications": [],
                }

                lesson_id = str(uuid4())
                await notification_service.create_notification(
                    user_id,
                    "lesson_drip",
                    {
                        "course_id": str(uuid4()),
                        "lesson_id": lesson_id,
                        "title": "Route lesson",
                    },
                    "lesson-drip:route-list",
                )

                listed = await client.get("/notifications")
                assert listed.status_code == 200, listed.text
                listed_payload = listed.json()
                assert listed_payload["show_notifications_bar"] is True
                assert "items" not in listed_payload
                notifications = listed_payload["notifications"]
                assert len(notifications) == 1
                assert notifications[0] == {
                    "id": notifications[0]["id"],
                    "title": "Ny lektion är upplåst",
                    "subtitle": "Route lesson",
                    "cta_label": "Öppna lektionen",
                    "cta_url": f"/lesson/{lesson_id}",
                }
                assert "type" not in notifications[0]
                assert "payload" not in notifications[0]
                assert notifications[0]["title"].strip()
                assert notifications[0]["subtitle"].strip()
                assert notifications[0]["cta_label"].strip()
                assert notifications[0]["cta_url"].strip()

                marked = await client.patch(
                    f"/notifications/{notifications[0]['id']}/read"
                )
                assert marked.status_code == 200, marked.text
                marked_payload = marked.json()
                assert marked_payload == notifications[0]
                assert "type" not in marked_payload
                assert "payload" not in marked_payload
                read_at = _notification_rows(conn)[0]["read_at"]
                assert read_at is not None

                duplicate_marked = await client.patch(
                    f"/notifications/{notifications[0]['id']}/read"
                )
                assert duplicate_marked.status_code == 200, duplicate_marked.text
                assert duplicate_marked.json() == notifications[0]
                assert _notification_rows(conn)[0]["read_at"] == read_at

                relisted = await client.get("/notifications")
                assert relisted.status_code == 200, relisted.text
                relisted_payload = relisted.json()
                assert relisted_payload["show_notifications_bar"] is True
                assert relisted_payload["notifications"][0] == notifications[0]

                default_preferences = await client.get("/notifications/preferences")
                assert default_preferences.status_code == 200, default_preferences.text
                assert default_preferences.json()["items"] == [
                    {
                        "type": "lesson_drip",
                        "push_enabled": True,
                        "in_app_enabled": True,
                    },
                    {
                        "type": "purchase",
                        "push_enabled": True,
                        "in_app_enabled": True,
                    },
                    {
                        "type": "message",
                        "push_enabled": False,
                        "in_app_enabled": True,
                    },
                ]

                updated_preference = await client.patch(
                    "/notifications/preferences/message",
                    json={"push_enabled": True, "in_app_enabled": False},
                )
                assert updated_preference.status_code == 200, updated_preference.text
                assert updated_preference.json() == {
                    "type": "message",
                    "push_enabled": True,
                    "in_app_enabled": False,
                }

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

            assert processed == 2
            assert [item["token"] for item in fake_push.sent] == [
                "push-token-a",
                "push-token-b",
            ]
            assert {item["title"] for item in fake_push.sent} == {
                "New lesson unlocked"
            }
            assert {item["body"] for item in fake_push.sent} == {"Opened lesson"}
            deliveries = _delivery_rows(conn)
            assert sorted((row["channel"], row["status"]) for row in deliveries) == [
                ("in_app", "sent"),
                ("push", "sent"),
            ]
            assert {row["attempts"] for row in deliveries} == {1}
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

            assert processed == 2
            assert [item["token"] for item in fake_push.sent] == [
                "push-token-a",
                "push-token-b",
            ]
            deliveries = _delivery_rows(conn)
            delivery_statuses = {
                row["channel"]: (row["status"], row["error_text"])
                for row in deliveries
            }
            assert delivery_statuses["in_app"] == ("sent", None)
            assert delivery_statuses["push"][0] == "failed"
            assert "push-token-b" in str(delivery_statuses["push"][1])
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
        assert notifications[0]["type"] == "purchase"
        assert notifications[0]["payload_json"] == {
            "product_id": course_id,
            "amount": 1000,
            "currency": "sek",
        }
        assert notifications[0]["dedup_key"] == (
            f"stripe_course_purchase_fulfilled:{order_id}"
        )
        stripe_deliveries = sorted(
            (row["channel"], row["status"]) for row in _delivery_rows(conn)
        )
        assert stripe_deliveries == [
            ("in_app", "pending"),
            ("push", "pending"),
        ]
