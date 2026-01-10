import pytest

from app import db

pytestmark = pytest.mark.anyio("asyncio")


async def test_course_entitlements_rls_enabled_and_policies_present():
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                select c.relrowsecurity
                from pg_class c
                join pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'app'
                  and c.relname = 'course_entitlements'
                """
            )
            row = await cur.fetchone()
            assert row is not None, "app.course_entitlements missing; run migrations"
            assert row[0] is True

            await cur.execute(
                """
                select policyname
                from pg_policies
                where schemaname = 'app'
                  and tablename = 'course_entitlements'
                """
            )
            policies = {policy[0] for policy in await cur.fetchall()}

    assert "service_role_full_access" in policies
    assert "course_entitlements_self_read" in policies
