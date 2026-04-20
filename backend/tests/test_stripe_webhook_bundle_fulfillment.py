import pytest

from app.repositories import course_enrollments
from app.routes import stripe_webhooks
from app.services import stripe_webhook_bundle_service


class _FakeCursor:
    def __init__(
        self,
        *,
        order,
        snapshot_rows,
        enrollment_rows,
        fail_on_enrollment_call: int | None = None,
    ) -> None:
        self.order = order
        self.snapshot_rows = snapshot_rows
        self.enrollment_rows = enrollment_rows
        self.fail_on_enrollment_call = fail_on_enrollment_call
        self.enrollment_calls = 0
        self.queries: list[tuple[str, tuple[object, ...]]] = []
        self._last_kind: str | None = None
        self._last_enrollment_index = -1

    async def execute(self, query, params=()):
        self.queries.append((query, tuple(params)))
        normalized = " ".join(str(query).lower().split())
        if "from app.orders" in normalized:
            self._last_kind = "order"
            return
        if "from app.bundle_order_courses" in normalized:
            self._last_kind = "snapshot"
            return
        if "canonical_create_course_enrollment" in normalized:
            self.enrollment_calls += 1
            if self.fail_on_enrollment_call == self.enrollment_calls:
                raise RuntimeError("simulated enrollment failure")
            self._last_kind = "enrollment"
            self._last_enrollment_index = self.enrollment_calls - 1
            return
        self._last_kind = "other"

    async def fetchone(self):
        if self._last_kind == "order":
            return self.order
        if self._last_kind == "enrollment":
            return self.enrollment_rows[self._last_enrollment_index]
        return None

    async def fetchall(self):
        if self._last_kind == "snapshot":
            return self.snapshot_rows
        return []


class _FakeCursorContext:
    def __init__(self, cursor: _FakeCursor) -> None:
        self.cursor = cursor

    async def __aenter__(self):
        return self.cursor

    async def __aexit__(self, exc_type, exc, tb):
        return False


class _FakeConnection:
    def __init__(self, cursor: _FakeCursor) -> None:
        self.cursor_instance = cursor
        self.commits = 0
        self.rollbacks = 0

    def cursor(self, **kwargs):  # noqa: ARG002
        return _FakeCursorContext(self.cursor_instance)

    async def commit(self):
        self.commits += 1

    async def rollback(self):
        self.rollbacks += 1


class _FakeConnectionContext:
    def __init__(self, conn: _FakeConnection) -> None:
        self.conn = conn

    async def __aenter__(self):
        return self.conn

    async def __aexit__(self, exc_type, exc, tb):
        return False


class _FakePool:
    def __init__(self, conn: _FakeConnection) -> None:
        self.conn = conn

    def connection(self):
        return _FakeConnectionContext(self.conn)


def _bundle_order():
    return {
        "id": "00000000-0000-0000-0000-000000000010",
        "user_id": "00000000-0000-0000-0000-000000000020",
        "bundle_id": "00000000-0000-0000-0000-000000000030",
        "order_type": "bundle",
        "status": "paid",
    }


def _snapshot_rows():
    return [
        {
            "id": "00000000-0000-0000-0000-000000000101",
            "order_id": "00000000-0000-0000-0000-000000000010",
            "bundle_id": "00000000-0000-0000-0000-000000000030",
            "course_id": "00000000-0000-0000-0000-000000000201",
            "position": 1,
        },
        {
            "id": "00000000-0000-0000-0000-000000000102",
            "order_id": "00000000-0000-0000-0000-000000000010",
            "bundle_id": "00000000-0000-0000-0000-000000000030",
            "course_id": "00000000-0000-0000-0000-000000000202",
            "position": 2,
        },
    ]


def _enrollment_rows():
    return [
        {
            "id": "00000000-0000-0000-0000-000000000301",
            "user_id": "00000000-0000-0000-0000-000000000020",
            "course_id": "00000000-0000-0000-0000-000000000201",
            "source": "purchase",
            "current_unlock_position": 1,
        },
        {
            "id": "00000000-0000-0000-0000-000000000302",
            "user_id": "00000000-0000-0000-0000-000000000020",
            "course_id": "00000000-0000-0000-0000-000000000202",
            "source": "purchase",
            "current_unlock_position": 1,
        },
    ]


@pytest.mark.anyio("asyncio")
async def test_bundle_fulfillment_uses_snapshot_and_commits_atomically(monkeypatch):
    cursor = _FakeCursor(
        order=_bundle_order(),
        snapshot_rows=_snapshot_rows(),
        enrollment_rows=_enrollment_rows(),
    )
    conn = _FakeConnection(cursor)
    monkeypatch.setattr(course_enrollments, "pool", _FakePool(conn))

    rows = await course_enrollments.fulfill_bundle_order_snapshot(
        order_id="00000000-0000-0000-0000-000000000010",
        user_id="00000000-0000-0000-0000-000000000020",
        bundle_id="00000000-0000-0000-0000-000000000030",
    )

    assert [row["course_id"] for row in rows] == [
        "00000000-0000-0000-0000-000000000201",
        "00000000-0000-0000-0000-000000000202",
    ]
    assert cursor.enrollment_calls == 2
    assert conn.commits == 1
    assert conn.rollbacks == 0
    assert all("course_bundle_courses" not in query for query, _ in cursor.queries)


@pytest.mark.anyio("asyncio")
async def test_bundle_fulfillment_failure_rolls_back_new_enrollments(monkeypatch):
    cursor = _FakeCursor(
        order=_bundle_order(),
        snapshot_rows=_snapshot_rows(),
        enrollment_rows=_enrollment_rows(),
        fail_on_enrollment_call=2,
    )
    conn = _FakeConnection(cursor)
    monkeypatch.setattr(course_enrollments, "pool", _FakePool(conn))

    with pytest.raises(RuntimeError, match="simulated enrollment failure"):
        await course_enrollments.fulfill_bundle_order_snapshot(
            order_id="00000000-0000-0000-0000-000000000010",
            user_id="00000000-0000-0000-0000-000000000020",
            bundle_id="00000000-0000-0000-0000-000000000030",
        )

    assert cursor.enrollment_calls == 2
    assert conn.commits == 0
    assert conn.rollbacks == 1


@pytest.mark.anyio("asyncio")
async def test_existing_purchase_enrollments_are_preserved(monkeypatch):
    existing = _enrollment_rows()
    existing[0] = {
        **existing[0],
        "id": "00000000-0000-0000-0000-000000000999",
        "source": "purchase",
    }
    cursor = _FakeCursor(
        order=_bundle_order(),
        snapshot_rows=_snapshot_rows(),
        enrollment_rows=existing,
    )
    conn = _FakeConnection(cursor)
    monkeypatch.setattr(course_enrollments, "pool", _FakePool(conn))

    rows = await course_enrollments.fulfill_bundle_order_snapshot(
        order_id="00000000-0000-0000-0000-000000000010",
        user_id="00000000-0000-0000-0000-000000000020",
        bundle_id="00000000-0000-0000-0000-000000000030",
    )

    assert rows[0]["id"] == "00000000-0000-0000-0000-000000000999"
    assert all(
        "update app.course_enrollments" not in query.lower()
        for query, _ in cursor.queries
    )
    assert conn.commits == 1


@pytest.mark.anyio("asyncio")
async def test_bundle_webhook_service_ignores_metadata_as_authority(monkeypatch):
    captured: dict[str, str] = {}

    async def fake_fulfill_bundle_order_snapshot(*, order_id, user_id, bundle_id):
        captured.update(
            {
                "order_id": order_id,
                "user_id": user_id,
                "bundle_id": bundle_id,
            }
        )
        return []

    monkeypatch.setattr(
        stripe_webhook_bundle_service.course_enrollments,
        "fulfill_bundle_order_snapshot",
        fake_fulfill_bundle_order_snapshot,
    )

    await stripe_webhook_bundle_service.handle_paid_checkout_order(
        order={
            "id": "order_canonical",
            "user_id": "user_canonical",
            "bundle_id": "bundle_canonical",
            "order_type": "bundle",
            "metadata": {
                "user_id": "user_metadata",
                "bundle_id": "bundle_metadata",
                "course_ids": ["course_from_metadata"],
            },
        },
        event_type="checkout.session.completed",
    )

    assert captured == {
        "order_id": "order_canonical",
        "user_id": "user_canonical",
        "bundle_id": "bundle_canonical",
    }


@pytest.mark.anyio("asyncio")
async def test_bundle_webhook_service_fails_closed_on_order_type_mismatch(
    monkeypatch,
):
    async def fail_fulfill_bundle_order_snapshot(*args, **kwargs):
        raise AssertionError("non-bundle orders must not be fulfilled")

    monkeypatch.setattr(
        stripe_webhook_bundle_service.course_enrollments,
        "fulfill_bundle_order_snapshot",
        fail_fulfill_bundle_order_snapshot,
    )

    with pytest.raises(stripe_webhook_bundle_service.BundleFulfillmentError) as exc:
        await stripe_webhook_bundle_service.handle_paid_checkout_order(
            order={
                "id": "order_course",
                "user_id": "user_canonical",
                "bundle_id": "bundle_canonical",
                "order_type": "one_off",
                "metadata": {"bundle_id": "bundle_metadata"},
            },
            event_type="checkout.session.completed",
        )

    assert str(exc.value) == (
        "Betalningen är registrerad, men kurserna kunde inte aktiveras ännu."
    )


@pytest.mark.anyio("asyncio")
async def test_duplicate_paid_bundle_event_reruns_idempotent_snapshot_fulfillment(
    monkeypatch,
):
    calls: list[str] = []
    order = {
        "id": "order_bundle_paid",
        "user_id": "user_123",
        "bundle_id": "bundle_123",
        "course_id": None,
        "order_type": "bundle",
        "status": "paid",
        "stripe_checkout_id": "cs_paid",
        "metadata": {},
    }

    async def fake_get_order_by_checkout_id(checkout_id):
        assert checkout_id == "cs_paid"
        return order

    async def fail_settle(*args, **kwargs):
        raise AssertionError("paid duplicate events must not create duplicate payments")

    async def fake_bundle_fulfillment(*, order, event_type):
        calls.append(f"{order['id']}:{event_type}")

    monkeypatch.setattr(
        stripe_webhooks.orders_repo,
        "get_order_by_checkout_id",
        fake_get_order_by_checkout_id,
    )
    monkeypatch.setattr(stripe_webhooks.payments_repo, "mark_order_paid", fail_settle)
    monkeypatch.setattr(stripe_webhooks.payments_repo, "record_payment", fail_settle)
    monkeypatch.setattr(
        stripe_webhooks.stripe_webhook_bundle_service,
        "handle_paid_checkout_order",
        fake_bundle_fulfillment,
    )

    await stripe_webhooks._handle_checkout_session_completion(
        {
            "id": "cs_paid",
            "metadata": {
                "order_id": "malicious_order",
                "bundle_id": "malicious_bundle",
                "course_ids": ["malicious_course"],
            },
            "payment_intent": "pi_paid",
            "amount_total": 2490,
            "currency": "sek",
        },
        "checkout.session.completed",
    )

    assert calls == ["order_bundle_paid:checkout.session.completed"]
