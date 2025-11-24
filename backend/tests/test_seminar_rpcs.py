import uuid

import pytest
from psycopg import errors

from app import db

pytestmark = pytest.mark.anyio("asyncio")


async def _seed_user(
    cur, user_id: uuid.UUID, email: str, profile_role: str, role_v2: str
) -> None:
    await cur.execute(
        """
        insert into auth.users (id, email, encrypted_password)
        values (%s, %s, 'test-hash')
        on conflict (id) do nothing
        """,
        (user_id, email),
    )
    await cur.execute(
        """
        insert into app.profiles (
            user_id, email, display_name, role, role_v2, is_admin
        )
        values (%s, %s, %s, %s, %s, false)
        on conflict (user_id) do nothing
        """,
        (user_id, email, profile_role.title(), profile_role, role_v2),
    )


@pytest.fixture
async def seminar_context():
    host_id = uuid.uuid4()
    attendee_id = uuid.uuid4()
    outsider_id = uuid.uuid4()
    seminar_id = None

    if db.pool.closed:  # type: ignore[attr-defined]
        await db.pool.open(wait=True)  # type: ignore[attr-defined]

    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _seed_user(
                cur,
                host_id,
                f"host_{host_id.hex[:8]}@aveli.local",
                profile_role="teacher",
                role_v2="teacher",
            )
            await _seed_user(
                cur,
                attendee_id,
                f"attendee_{attendee_id.hex[:8]}@aveli.local",
                profile_role="student",
                role_v2="user",
            )
            await _seed_user(
                cur,
                outsider_id,
                f"outsider_{outsider_id.hex[:8]}@aveli.local",
                profile_role="student",
                role_v2="user",
            )

            await cur.execute(
                """
                insert into app.seminars (host_id, title, status)
                values (%s, 'Test Seminar', 'scheduled')
                returning id
                """,
                (host_id,),
            )
            seminar_id = (await cur.fetchone())[0]

            await cur.execute(
                """
                insert into app.seminar_attendees (seminar_id, user_id, role)
                values (%s, %s, 'participant')
                on conflict do nothing
                """,
                (seminar_id, attendee_id),
            )
            await conn.commit()

    try:
        yield {
            "host_id": host_id,
            "attendee_id": attendee_id,
            "outsider_id": outsider_id,
            "seminar_id": seminar_id,
        }
    finally:
        async with db.pool.connection() as cleanup_conn:  # type: ignore
            async with cleanup_conn.cursor() as cleanup_cur:  # type: ignore[attr-defined]
                await cleanup_cur.execute(
                    "delete from app.seminar_attendees where seminar_id = %s",
                    (seminar_id,),
                )
                await cleanup_cur.execute(
                    "delete from app.seminars where id = %s",
                    (seminar_id,),
                )
                await cleanup_cur.execute(
                    "delete from app.profiles where user_id in (%s, %s, %s)",
                    (host_id, attendee_id, outsider_id),
                )
                await cleanup_cur.execute(
                    "delete from auth.users where id in (%s, %s, %s)",
                    (host_id, attendee_id, outsider_id),
                )
                await cleanup_conn.commit()


async def _set_auth(cur, user_id: uuid.UUID | None, role: str) -> None:
    await cur.execute(
        "select set_config('request.jwt.claim.sub', %s, true)",
        (str(user_id) if user_id else "",),
    )
    await cur.execute(
        "select set_config('request.jwt.claim.role', %s, true)",
        (role,),
    )


async def _reset_auth(cur) -> None:
    await cur.execute("select set_config('request.jwt.claim.sub', '', true)")
    await cur.execute("select set_config('request.jwt.claim.role', '', true)")


async def test_host_has_access(seminar_context):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _set_auth(cur, seminar_context["host_id"], "authenticated")
            await cur.execute(
                "select app.is_seminar_host(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is True

            await cur.execute(
                "select app.can_access_seminar(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is True
            await _reset_auth(cur)


async def test_attendee_is_recognized(seminar_context):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _set_auth(cur, seminar_context["attendee_id"], "authenticated")

            await cur.execute(
                "select app.is_seminar_attendee(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is True

            await cur.execute(
                "select app.can_access_seminar(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is True

            await cur.execute(
                "select app.is_seminar_host(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is False
            await _reset_auth(cur)


async def test_outsider_cannot_access_without_role(seminar_context):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _set_auth(cur, seminar_context["outsider_id"], "authenticated")
            await cur.execute(
                "select app.can_access_seminar(%s)",
                (seminar_context["seminar_id"],),
            )
            assert (await cur.fetchone())[0] is False
            await _reset_auth(cur)


async def test_impersonation_attempt_fails(seminar_context):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _set_auth(cur, seminar_context["attendee_id"], "authenticated")
            with pytest.raises(errors.InsufficientPrivilege):
                await cur.execute(
                    "select app.is_seminar_host(%s, %s)",
                    (
                        seminar_context["seminar_id"],
                        seminar_context["host_id"],
                    ),
                )
            await conn.rollback()
            await _reset_auth(cur)


async def test_service_role_can_specify_target_user(seminar_context):
    async with db.pool.connection() as conn:  # type: ignore
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await _set_auth(cur, None, "service_role")
            await cur.execute(
                "select app.is_seminar_host(%s, %s)",
                (
                    seminar_context["seminar_id"],
                    seminar_context["host_id"],
                ),
            )
            assert (await cur.fetchone())[0] is True
            await _reset_auth(cur)
