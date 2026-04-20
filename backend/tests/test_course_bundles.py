import uuid

import pytest

from psycopg import errors

from app import db, repositories
from app.config import settings
from app.services import course_bundles_service

pytestmark = pytest.mark.anyio("asyncio")


def _set_stripe_test_env(monkeypatch, *, secret: str = "sk_test_value") -> None:
    monkeypatch.delenv("STRIPE_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_TEST_SECRET_KEY", raising=False)
    monkeypatch.delenv("STRIPE_LIVE_SECRET_KEY", raising=False)
    monkeypatch.setenv("STRIPE_SECRET_KEY", secret)
    monkeypatch.setenv("STRIPE_TEST_SECRET_KEY", secret)
    settings.stripe_secret_key = secret
    settings.stripe_test_secret_key = secret


async def _create_course(client, token: str, slug: str, price_amount_cents: int) -> str:
    response = await client.post(
        "/studio/courses",
        headers=_auth(token),
        json={
            "title": f"Course {slug}",
            "slug": slug,
            "course_group_id": str(uuid.uuid4()),
            "group_position": 1,
            "price_amount_cents": price_amount_cents,
            "drip_enabled": False,
            "drip_interval_days": None,
        },
    )
    assert response.status_code == 200, response.text
    return str(response.json()["id"])


async def _set_course_bundle_eligibility(
    course_id: str,
    *,
    visibility: str = "public",
    content_ready: bool = True,
    sellable: bool = True,
) -> None:
    product_id = f"prod_bundle_course_{uuid.uuid4().hex}" if sellable else None
    price_id = f"price_bundle_course_{uuid.uuid4().hex}" if sellable else None
    required_source = "purchase" if visibility == "public" else None
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.courses
                   SET visibility = %s::app.course_visibility,
                       content_ready = %s,
                       stripe_product_id = %s,
                       active_stripe_price_id = %s,
                       sellable = %s,
                       required_enrollment_source = %s::app.course_enrollment_source,
                       updated_at = now()
                 WHERE id = %s
                """,
                (
                    visibility,
                    content_ready,
                    product_id,
                    price_id,
                    sellable,
                    required_source,
                    course_id,
                ),
            )
            await conn.commit()


async def _bundle_sellable(bundle_id: str) -> bool:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "SELECT sellable FROM app.course_bundles WHERE id = %s",
                (bundle_id,),
            )
            row = await cur.fetchone()
    assert row is not None
    return bool(row[0])


async def _bundle_snapshot_table_ready() -> bool:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("select to_regclass('app.bundle_order_courses') as tbl limit 1")
            row = await cur.fetchone()
    return bool(row and row[0])


async def _list_bundle_order_courses(order_id: str) -> list[dict]:
    rows = await repositories.list_bundle_order_courses(order_id)
    return [
        {
            "order_id": str(row["order_id"]),
            "bundle_id": str(row["bundle_id"]),
            "course_id": str(row["course_id"]),
            "position": int(row["position"]),
        }
        for row in rows
    ]


async def _count_bundle_orders_for_user(user_id: str, bundle_id: str) -> int:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT count(*)::integer
                  FROM app.orders
                 WHERE user_id = %s
                   AND bundle_id = %s
                   AND order_type = 'bundle'
                """,
                (user_id, bundle_id),
            )
            row = await cur.fetchone()
    return int(row[0] if row else 0)


async def _cleanup_user(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                DELETE FROM app.orders o
                 WHERE o.user_id = %s
                   AND NOT EXISTS (
                       SELECT 1
                         FROM app.bundle_order_courses boc
                        WHERE boc.order_id = o.id
                   )
                """,
                (user_id,),
            )
            await cur.execute("DELETE FROM app.memberships WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.course_enrollments WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM app.stripe_customers WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


async def _cleanup_course(course_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.course_enrollments WHERE course_id = %s",
                (course_id,),
            )
            try:
                await cur.execute("DELETE FROM app.course_bundle_courses WHERE course_id = %s", (course_id,))
            except errors.UndefinedTable:
                await conn.rollback()
            await cur.execute(
                """
                DELETE FROM app.courses c
                 WHERE c.id = %s
                   AND NOT EXISTS (
                       SELECT 1
                         FROM app.bundle_order_courses boc
                        WHERE boc.course_id = c.id
                   )
                """,
                (course_id,),
            )
            await conn.commit()


async def _cleanup_bundle(bundle_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            try:
                await cur.execute(
                    """
                    DELETE FROM app.orders o
                     WHERE o.bundle_id = %s
                       AND NOT EXISTS (
                           SELECT 1
                             FROM app.bundle_order_courses boc
                            WHERE boc.order_id = o.id
                       )
                    """,
                    (bundle_id,),
                )
                await cur.execute(
                    "DELETE FROM app.course_bundle_courses WHERE bundle_id = %s",
                    (bundle_id,),
                )
                await cur.execute(
                    """
                    DELETE FROM app.course_bundles cb
                     WHERE cb.id = %s
                       AND NOT EXISTS (
                           SELECT 1
                             FROM app.bundle_order_courses boc
                            WHERE boc.bundle_id = cb.id
                       )
                       AND NOT EXISTS (
                           SELECT 1
                             FROM app.orders o
                            WHERE o.bundle_id = cb.id
                       )
                    """,
                    (bundle_id,),
                )
                await conn.commit()
            except errors.UndefinedTable:
                await conn.rollback()


async def _promote_to_teacher(user_id: str):
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET onboarding_state = 'completed',

                       role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await cur.execute(
                """
                INSERT INTO app.memberships (
                    membership_id,
                    user_id,
                    status,
                    effective_at,
                    expires_at,
                    source,
                    created_at,
                    updated_at
                )
                VALUES (%s, %s, 'active', now(), now() + interval '30 days', 'purchase', now(), now())
                ON CONFLICT (user_id) DO UPDATE
                SET status = 'active',
                    effective_at = COALESCE(app.memberships.effective_at, now()),
                    expires_at = now() + interval '30 days',
                    source = 'purchase',
                    updated_at = now()
                """,
                (str(uuid.uuid4()), user_id),
            )
            await conn.commit()


def _auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def _bundles_table_ready() -> bool:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("select to_regclass('app.course_bundles') as tbl limit 1")
            row = await cur.fetchone()
    return bool(row and row[0])


async def _register_user(client, email: str, password: str, _display_name: str):
    register_resp = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200, me_resp.text
    user_id = me_resp.json()["user_id"]
    return tokens["access_token"], tokens["refresh_token"], user_id


async def _login_user(client, email: str, password: str) -> str:
    login_resp = await client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert login_resp.status_code == 200, login_resp.text
    return login_resp.json()["access_token"]


def test_bundle_database_errors_are_mapped_to_safe_swedish_messages():
    legacy_field = "de" + "scription"
    missing_column = course_bundles_service.map_bundle_database_error(
        errors.UndefinedColumn(f"column course_bundles.{legacy_field} does not exist")
    )
    assert missing_column.status_code == 503
    assert missing_column.detail == "Paketfunktionen är inte tillgänglig just nu"
    assert legacy_field not in missing_column.detail

    duplicate = course_bundles_service.map_bundle_database_error(
        errors.UniqueViolation("duplicate key value violates unique constraint")
    )
    assert duplicate.status_code == 400
    assert duplicate.detail == "Paketet kunde inte sparas med angivna uppgifter"
    assert "unique constraint" not in duplicate.detail


async def test_bundle_create_blocks_invalid_authority_compositions(async_client):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")

    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    teacher_token, _, teacher_id = await _register_user(
        async_client, teacher_email, "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    teacher_token = await _login_user(async_client, teacher_email, "Passw0rd!")

    other_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    other_token, _, other_teacher_id = await _register_user(
        async_client, other_email, "Passw0rd!", "Other Teacher"
    )
    await _promote_to_teacher(other_teacher_id)
    other_token = await _login_user(async_client, other_email, "Passw0rd!")

    course_valid = None
    course_non_public = None
    course_not_ready = None
    course_not_sellable = None
    course_other_teacher = None

    async def post_create(course_ids: list[str]):
        return await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "price_amount_cents": 2490,
                "course_ids": course_ids,
            },
        )

    try:
        course_valid = await _create_course(
            async_client,
            teacher_token,
            f"bundle-valid-{uuid.uuid4().hex[:6]}",
            1500,
        )
        course_non_public = await _create_course(
            async_client,
            teacher_token,
            f"bundle-draft-{uuid.uuid4().hex[:6]}",
            1200,
        )
        course_not_ready = await _create_course(
            async_client,
            teacher_token,
            f"bundle-not-ready-{uuid.uuid4().hex[:6]}",
            1200,
        )
        course_not_sellable = await _create_course(
            async_client,
            teacher_token,
            f"bundle-not-sellable-{uuid.uuid4().hex[:6]}",
            1200,
        )
        course_other_teacher = await _create_course(
            async_client,
            other_token,
            f"bundle-other-{uuid.uuid4().hex[:6]}",
            1200,
        )

        await _set_course_bundle_eligibility(course_valid)
        await _set_course_bundle_eligibility(
            course_non_public,
            visibility="draft",
            content_ready=True,
            sellable=False,
        )
        await _set_course_bundle_eligibility(
            course_not_ready,
            visibility="draft",
            content_ready=False,
            sellable=False,
        )
        await _set_course_bundle_eligibility(
            course_not_sellable,
            visibility="public",
            content_ready=True,
            sellable=False,
        )
        await _set_course_bundle_eligibility(course_other_teacher)

        undersized_resp = await post_create([course_valid])
        assert undersized_resp.status_code == 400
        assert undersized_resp.json()["detail"] == "Paketet måste innehålla minst två kurser"

        duplicate_resp = await post_create([course_valid, course_valid])
        assert duplicate_resp.status_code == 400
        assert duplicate_resp.json()["detail"] == "Paketet kan inte innehålla samma kurs flera gånger"

        non_public_resp = await post_create([course_valid, course_non_public])
        assert non_public_resp.status_code == 400
        assert non_public_resp.json()["detail"] == "Paketet innehåller en kurs som inte är publicerad"

        not_ready_resp = await post_create([course_valid, course_not_ready])
        assert not_ready_resp.status_code == 400
        assert not_ready_resp.json()["detail"] == "Paketet innehåller en kurs som inte är redo"

        not_sellable_resp = await post_create([course_valid, course_not_sellable])
        assert not_sellable_resp.status_code == 400
        assert not_sellable_resp.json()["detail"] == "Paketet innehåller en kurs som inte kan säljas"

        other_teacher_resp = await post_create([course_valid, course_other_teacher])
        assert other_teacher_resp.status_code == 403
        assert other_teacher_resp.json()["detail"] == "Kursen tillhör inte dig"
    finally:
        if course_other_teacher:
            await _cleanup_course(course_other_teacher)
        if course_valid:
            await _cleanup_course(course_valid)
        if course_non_public:
            await _cleanup_course(course_non_public)
        if course_not_ready:
            await _cleanup_course(course_not_ready)
        if course_not_sellable:
            await _cleanup_course(course_not_sellable)
        await _cleanup_user(str(other_teacher_id))
        await _cleanup_user(str(teacher_id))


async def test_bundle_order_snapshot_failure_rolls_back_order(async_client, monkeypatch):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")
    if not await _bundle_snapshot_table_ready():
        pytest.skip("bundle_order_courses table missing; replay Baseline V2")
    _set_stripe_test_env(monkeypatch)

    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    teacher_token, _, teacher_id = await _register_user(
        async_client, teacher_email, "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    teacher_token = await _login_user(async_client, teacher_email, "Passw0rd!")
    _, _, student_id = await _register_user(
        async_client, f"student_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Student"
    )

    course_one = None
    course_two = None
    bundle_id = None
    stripe_prices: dict[str, dict[str, object]] = {}

    def fake_product_create(**kwargs):
        return {"id": f"prod_bundle_test_{uuid.uuid4().hex}"}

    def fake_price_create(**kwargs):
        price_id = f"price_bundle_test_{uuid.uuid4().hex}"
        stripe_prices[price_id] = {
            "id": price_id,
            "product": kwargs["product"],
            "unit_amount": kwargs["unit_amount"],
            "currency": kwargs["currency"],
            "active": True,
        }
        return stripe_prices[price_id]

    def fake_price_retrieve(price_id):
        return stripe_prices[price_id]

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)

    try:
        course_one = await _create_course(
            async_client,
            teacher_token,
            f"bundle-rollback-one-{uuid.uuid4().hex[:6]}",
            1500,
        )
        course_two = await _create_course(
            async_client,
            teacher_token,
            f"bundle-rollback-two-{uuid.uuid4().hex[:6]}",
            1200,
        )
        await _set_course_bundle_eligibility(course_one)
        await _set_course_bundle_eligibility(course_two)

        create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "price_amount_cents": 2490,
                "course_ids": [course_one, course_two],
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        bundle_id = create_resp.json()["id"]

        before_count = await _count_bundle_orders_for_user(str(student_id), bundle_id)
        with pytest.raises(errors.UniqueViolation):
            await repositories.create_bundle_order_with_snapshot(
                user_id=str(student_id),
                bundle_id=bundle_id,
                amount_cents=2490,
                currency="sek",
                snapshot_courses=[
                    {"course_id": course_one, "position": 1},
                    {"course_id": course_one, "position": 2},
                ],
                metadata={"checkout_type": "bundle"},
                stripe_customer_id="cus_rollback_test",
            )
        after_count = await _count_bundle_orders_for_user(str(student_id), bundle_id)
        assert after_count == before_count
    finally:
        if bundle_id:
            await _cleanup_bundle(bundle_id)
        if course_one:
            await _cleanup_course(course_one)
        if course_two:
            await _cleanup_course(course_two)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))


async def test_bundle_checkout_stripe_failure_keeps_pending_order_snapshot(
    async_client,
    monkeypatch,
):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")
    if not await _bundle_snapshot_table_ready():
        pytest.skip("bundle_order_courses table missing; replay Baseline V2")
    _set_stripe_test_env(monkeypatch)

    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    teacher_token, _, teacher_id = await _register_user(
        async_client, teacher_email, "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    teacher_token = await _login_user(async_client, teacher_email, "Passw0rd!")
    student_token, _, student_id = await _register_user(
        async_client, f"student_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Student"
    )

    course_one = None
    course_two = None
    bundle_id = None
    stripe_prices: dict[str, dict[str, object]] = {}

    def fake_product_create(**kwargs):
        return {"id": f"prod_bundle_test_{uuid.uuid4().hex}"}

    def fake_price_create(**kwargs):
        price_id = f"price_bundle_test_{uuid.uuid4().hex}"
        stripe_prices[price_id] = {
            "id": price_id,
            "product": kwargs["product"],
            "unit_amount": kwargs["unit_amount"],
            "currency": kwargs["currency"],
            "active": True,
        }
        return stripe_prices[price_id]

    def fake_price_retrieve(price_id):
        return stripe_prices[price_id]

    stripe_customer_id = f"cus_bundle_failure_test_{uuid.uuid4().hex}"

    def fake_customer_create(**kwargs):
        return {"id": stripe_customer_id}

    def fake_session_create(**kwargs):
        raise stripe.error.StripeError("checkout failed")

    import stripe

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)

    try:
        course_one = await _create_course(
            async_client,
            teacher_token,
            f"bundle-stripe-fail-one-{uuid.uuid4().hex[:6]}",
            1500,
        )
        course_two = await _create_course(
            async_client,
            teacher_token,
            f"bundle-stripe-fail-two-{uuid.uuid4().hex[:6]}",
            1200,
        )
        await _set_course_bundle_eligibility(course_one)
        await _set_course_bundle_eligibility(course_two)

        create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "price_amount_cents": 2490,
                "course_ids": [course_one, course_two],
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        bundle_id = create_resp.json()["id"]

        checkout_resp = await async_client.post(
            f"/api/course-bundles/{bundle_id}/checkout-session",
            headers=_auth(student_token),
        )
        assert checkout_resp.status_code == 502
        assert checkout_resp.json()["detail"] == "Kunde inte skapa Stripe-session"

        orders = [
            order
            for order in await repositories.list_user_orders(str(student_id))
            if str(order["bundle_id"]) == bundle_id
        ]
        assert len(orders) == 1
        order = orders[0]
        assert order["status"] == "pending"
        assert order["stripe_checkout_id"] is None
        assert order["stripe_payment_intent"] is None
        assert order["metadata"] == {"checkout_type": "bundle"}

        snapshot_rows = await _list_bundle_order_courses(str(order["id"]))
        assert [row["course_id"] for row in snapshot_rows] == [course_one, course_two]
        assert [row["position"] for row in snapshot_rows] == [1, 2]
    finally:
        if bundle_id:
            await _cleanup_bundle(bundle_id)
        if course_one:
            await _cleanup_course(course_one)
        if course_two:
            await _cleanup_course(course_two)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))


async def test_create_bundle_and_checkout_flow(async_client, monkeypatch):
    if not await _bundles_table_ready():
        pytest.skip("course_bundles table missing; run migrations")
    if not await _bundle_snapshot_table_ready():
        pytest.skip("bundle_order_courses table missing; replay Baseline V2")
    _set_stripe_test_env(monkeypatch)
    teacher_email = f"teacher_{uuid.uuid4().hex[:6]}@example.com"
    teacher_token, _, teacher_id = await _register_user(
        async_client, teacher_email, "Passw0rd!", "Teacher"
    )
    await _promote_to_teacher(teacher_id)
    teacher_token = await _login_user(async_client, teacher_email, "Passw0rd!")
    student_token, _, student_id = await _register_user(
        async_client, f"student_{uuid.uuid4().hex[:6]}@example.com", "Passw0rd!", "Student"
    )

    slug_one = f"bundle-course-{uuid.uuid4().hex[:6]}"
    slug_two = f"bundle-course-{uuid.uuid4().hex[6:12]}"
    slug_three = f"bundle-course-{uuid.uuid4().hex[12:18]}"
    course_one = None
    course_two = None
    course_three = None
    course_bad = None
    bundle_id = None

    captured_session: dict[str, object] = {}
    stripe_prices: dict[str, dict[str, object]] = {}

    def fake_product_create(**kwargs):
        return {"id": f"prod_bundle_test_{uuid.uuid4().hex}"}

    def fake_price_create(**kwargs):
        price_id = f"price_bundle_test_{uuid.uuid4().hex}"
        stripe_prices[price_id] = {
            "id": price_id,
            "product": kwargs["product"],
            "unit_amount": kwargs["unit_amount"],
            "currency": kwargs["currency"],
            "active": True,
        }
        return stripe_prices[price_id]

    def fake_price_retrieve(price_id):
        return stripe_prices[price_id]

    stripe_customer_id = f"cus_bundle_test_{uuid.uuid4().hex}"

    def fake_customer_create(**kwargs):
        return {"id": stripe_customer_id}

    stripe_session_id = f"cs_bundle_test_{uuid.uuid4().hex}"
    stripe_session_url = f"https://stripe.test/{stripe_session_id}"
    stripe_payment_intent = f"pi_bundle_test_{uuid.uuid4().hex}"

    def fake_session_create(**kwargs):
        captured_session.update(kwargs)
        return {
            "id": stripe_session_id,
            "url": stripe_session_url,
            "payment_intent": stripe_payment_intent,
        }

    monkeypatch.setattr("stripe.Product.create", fake_product_create)
    monkeypatch.setattr("stripe.Price.create", fake_price_create)
    monkeypatch.setattr("stripe.Price.retrieve", fake_price_retrieve)
    monkeypatch.setattr("stripe.Customer.create", fake_customer_create)
    monkeypatch.setattr("stripe.checkout.Session.create", fake_session_create)
    monkeypatch.setattr(settings, "checkout_success_url", "https://checkout.test/success")
    monkeypatch.setattr(settings, "checkout_cancel_url", "https://checkout.test/cancel")

    try:
        course_one = await _create_course(async_client, teacher_token, slug_one, 1500)
        course_two = await _create_course(async_client, teacher_token, slug_two, 1200)
        course_three = await _create_course(async_client, teacher_token, slug_three, 900)
        course_bad = await _create_course(
            async_client,
            teacher_token,
            f"bundle-course-bad-{uuid.uuid4().hex[:6]}",
            700,
        )
        await _set_course_bundle_eligibility(course_one)
        await _set_course_bundle_eligibility(course_two)
        await _set_course_bundle_eligibility(course_three)
        await _set_course_bundle_eligibility(
            course_bad,
            visibility="draft",
            content_ready=True,
            sellable=False,
        )

        forbidden_create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "price_amount_cents": 2490,
                "course_ids": [course_one, course_two],
                "sellable": True,
            },
        )
        assert forbidden_create_resp.status_code == 400
        assert forbidden_create_resp.json()["detail"] == "Paketförfrågan innehåller otillåtna fält"

        create_resp = await async_client.post(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
            json={
                "title": "Paket A",
                "price_amount_cents": 2490,
                "course_ids": [course_one, course_two],
            },
        )
        assert create_resp.status_code == 201, create_resp.text
        bundle = create_resp.json()
        bundle_id = bundle["id"]
        assert bundle["title"] == "Paket A"
        assert bundle["price_amount_cents"] == 2490
        assert set(bundle) == {"id", "teacher_id", "title", "price_amount_cents", "courses"}
        assert [item["position"] for item in bundle["courses"]] == [1, 2]
        assert await _bundle_sellable(bundle_id) is True

        forbidden_update_resp = await async_client.patch(
            f"/api/teachers/course-bundles/{bundle_id}",
            headers=_auth(teacher_token),
            json={"sellable": False},
        )
        assert forbidden_update_resp.status_code == 400
        assert forbidden_update_resp.json()["detail"] == "Paketförfrågan innehåller otillåtna fält"

        duplicate_update_resp = await async_client.patch(
            f"/api/teachers/course-bundles/{bundle_id}",
            headers=_auth(teacher_token),
            json={"course_ids": [course_one, course_one]},
        )
        assert duplicate_update_resp.status_code == 400
        assert duplicate_update_resp.json()["detail"] == "Paketet kan inte innehålla samma kurs flera gånger"

        update_resp = await async_client.patch(
            f"/api/teachers/course-bundles/{bundle_id}",
            headers=_auth(teacher_token),
            json={
                "title": "Paket B",
                "price_amount_cents": 2790,
                "course_ids": [course_two, course_one],
            },
        )
        assert update_resp.status_code == 200, update_resp.text
        updated_bundle = update_resp.json()
        assert updated_bundle["title"] == "Paket B"
        assert updated_bundle["price_amount_cents"] == 2790
        assert [item["course_id"] for item in updated_bundle["courses"]] == [
            course_two,
            course_one,
        ]
        assert [item["position"] for item in updated_bundle["courses"]] == [1, 2]
        assert await _bundle_sellable(bundle_id) is True

        list_resp = await async_client.get(
            "/api/teachers/course-bundles",
            headers=_auth(teacher_token),
        )
        assert list_resp.status_code == 200, list_resp.text
        listed_bundle = next(
            item for item in list_resp.json()["items"] if item["id"] == bundle_id
        )
        assert set(listed_bundle) == {"id", "teacher_id", "title", "price_amount_cents", "courses"}
        assert [item["position"] for item in listed_bundle["courses"]] == [1, 2]

        forbidden_attach_resp = await async_client.post(
            f"/api/teachers/course-bundles/{bundle_id}/courses",
            headers=_auth(teacher_token),
            json={"course_id": course_three, "sellable": True},
        )
        assert forbidden_attach_resp.status_code == 400
        assert forbidden_attach_resp.json()["detail"] == "Paketförfrågan innehåller otillåtna fält"

        invalid_attach_resp = await async_client.post(
            f"/api/teachers/course-bundles/{bundle_id}/courses",
            headers=_auth(teacher_token),
            json={"course_id": course_bad},
        )
        assert invalid_attach_resp.status_code == 400
        assert invalid_attach_resp.json()["detail"] == "Paketet innehåller en kurs som inte är publicerad"

        attach_resp = await async_client.post(
            f"/api/teachers/course-bundles/{bundle_id}/courses",
            headers=_auth(teacher_token),
            json={"course_id": course_three, "position": 2},
        )
        assert attach_resp.status_code == 200, attach_resp.text
        attached_courses = attach_resp.json()["courses"]
        assert [item["course_id"] for item in attached_courses] == [
            course_two,
            course_three,
            course_one,
        ]
        assert [item["position"] for item in attached_courses] == [1, 2, 3]

        checkout_resp = await async_client.post(
            f"/api/course-bundles/{bundle_id}/checkout-session",
            headers=_auth(student_token),
        )
        assert checkout_resp.status_code == 201, checkout_resp.text
        payload = checkout_resp.json()
        assert payload["url"] == stripe_session_url
        assert payload["session_id"] == stripe_session_id
        assert payload["order_id"]
        assert captured_session.get("locale") == "sv"
        metadata = captured_session.get("metadata") or {}
        assert metadata.get("bundle_id") == bundle_id
        assert metadata.get("checkout_type") == "bundle"
        assert metadata.get("order_id") == payload["order_id"]
        assert "course_ids" not in metadata
        assert "course_slugs" not in metadata
        assert "price_id" not in metadata
        assert "user_id" not in metadata

        order = await repositories.get_order(payload["order_id"])
        assert order is not None
        assert order["status"] == "pending"
        assert order["order_type"] == "bundle"
        assert str(order["bundle_id"]) == bundle_id
        assert order["course_id"] is None
        assert order["amount_cents"] == 2790
        assert order["currency"] == "sek"
        assert order["metadata"] == {"checkout_type": "bundle"}

        snapshot_rows = await _list_bundle_order_courses(payload["order_id"])
        assert [row["course_id"] for row in snapshot_rows] == [
            course_two,
            course_three,
            course_one,
        ]
        assert [row["position"] for row in snapshot_rows] == [1, 2, 3]

        live_change_resp = await async_client.patch(
            f"/api/teachers/course-bundles/{bundle_id}",
            headers=_auth(teacher_token),
            json={"course_ids": [course_one, course_two]},
        )
        assert live_change_resp.status_code == 200, live_change_resp.text
        unchanged_snapshot_rows = await _list_bundle_order_courses(payload["order_id"])
        assert [row["course_id"] for row in unchanged_snapshot_rows] == [
            course_two,
            course_three,
            course_one,
        ]
        assert [row["position"] for row in unchanged_snapshot_rows] == [1, 2, 3]
        assert await repositories.get_membership(str(student_id)) is None
    finally:
        if bundle_id:
            await _cleanup_bundle(bundle_id)
        if course_one:
            await _cleanup_course(course_one)
        if course_two:
            await _cleanup_course(course_two)
        if course_three:
            await _cleanup_course(course_three)
        if course_bad:
            await _cleanup_course(course_bad)
        await _cleanup_user(str(teacher_id))
        await _cleanup_user(str(student_id))
