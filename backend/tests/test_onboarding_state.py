import uuid

import pytest

from app import db
from app.services.email_tokens import create_email_token

from .utils import auth_header, fetch_auth_subject, register_auth_user


pytestmark = pytest.mark.anyio("asyncio")


@pytest.fixture(autouse=True)
def _stable_password_hashing_for_onboarding_tests(monkeypatch):
    from app import models
    from app.routes import auth as auth_routes

    def _hash_password(password: str) -> str:
        return f"test-hash:{password}"

    def _verify_password(password: str, hashed: str) -> bool:
        return hashed == _hash_password(password)

    monkeypatch.setattr(models, "hash_password", _hash_password)
    monkeypatch.setattr(auth_routes, "verify_password", _verify_password)


async def _event_types_for(user_id: str) -> list[str]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT event_type
                  FROM app.auth_events
                 WHERE subject_user_id = %s
                 ORDER BY created_at ASC
                """,
                (user_id,),
            )
            rows = await cur.fetchall()
    return [str(row[0]) for row in rows]


async def _set_profile_display_name(user_id: str, display_name: str | None) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.profiles
                   SET display_name = %s,
                       updated_at = now()
                 WHERE user_id = %s
                """,
                (display_name, user_id),
            )
            await conn.commit()


async def _delete_profile_projection(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "DELETE FROM app.profiles WHERE user_id = %s",
                (user_id,),
            )
            await conn.commit()


async def _create_profile_step(async_client, user: dict[str, str]) -> None:
    create_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(user["access_token"]),
        json={"display_name": "Welcome Pending User", "bio": "Kort bio"},
    )
    assert create_resp.status_code == 200, create_resp.text


async def test_register_initializes_subject_and_projection_without_required_name(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"initial_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Initial User",
    )

    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "incomplete",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] is None
    assert me_resp.json()["bio"] is None


async def test_create_profile_persists_required_name_and_optional_bio(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"create_profile_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Ignored Register Name",
    )

    create_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(user["access_token"]),
        json={
            "display_name": "  Create Profile User  ",
            "bio": "  Kort bio  ",
        },
    )
    assert create_resp.status_code == 200, create_resp.text
    assert create_resp.json()["display_name"] == "Create Profile User"
    assert create_resp.json()["bio"] == "Kort bio"
    assert create_resp.json()["photo_url"] is None
    assert create_resp.json()["avatar_media_id"] is None

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] == "Create Profile User"
    assert me_resp.json()["bio"] == "Kort bio"

    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "welcome_pending",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


@pytest.mark.parametrize("payload", [{}, {"display_name": ""}, {"display_name": "   "}])
async def test_create_profile_requires_display_name(async_client, payload):
    user = await register_auth_user(
        async_client,
        email=f"create_profile_missing_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Ignored Register Name",
    )

    create_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(user["access_token"]),
        json=payload,
    )
    assert create_resp.status_code == 422, create_resp.text

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] is None
    assert me_resp.json()["bio"] is None


async def test_create_profile_rejects_non_profile_authority_and_media_fields(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"create_profile_forbidden_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Ignored Register Name",
    )

    create_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(user["access_token"]),
        json={
            "display_name": "Create Profile User",
            "bio": "Allowed bio",
            "photo_url": "https://example.com/avatar.png",
            "avatar_media_id": str(uuid.uuid4()),
            "onboarding_state": "completed",
            "role_v2": "teacher",
            "is_admin": True,
        },
    )
    assert create_resp.status_code == 422, create_resp.text
    payload = create_resp.json()
    assert payload["status"] == "error"
    assert payload["error_code"] == "validation_error"
    assert {entry["field"] for entry in payload["field_errors"]} == {
        "photo_url",
        "avatar_media_id",
        "onboarding_state",
        "role_v2",
        "is_admin",
    }

    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] is None
    assert me_resp.json()["bio"] is None


async def test_auth_subject_repository_cannot_complete_onboarding_directly():
    from app import repositories
    from app.repositories import auth_subjects as auth_subjects_repo

    assert not hasattr(repositories, "complete_onboarding")
    assert not hasattr(auth_subjects_repo, "complete_onboarding")

    with pytest.raises(ValueError, match="cannot complete onboarding"):
        await auth_subjects_repo.ensure_auth_subject(
            uuid.uuid4(),
            onboarding_state="completed",
            role_v2="learner",
            role="learner",
            is_admin=False,
        )


async def test_onboarding_complete_rejects_incomplete_state(async_client):
    user = await register_auth_user(
        async_client,
        email=f"complete_incomplete_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Incomplete User",
    )

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )

    assert complete_resp.status_code == 409, complete_resp.text
    assert complete_resp.json()["detail"] == "Välkomststeget måste bekräftas först."
    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "incomplete",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }
    assert await _event_types_for(user["user_id"]) == []


async def test_create_profile_rejects_completed_state_without_profile_mutation(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"create_completed_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Completed User",
    )
    await _create_profile_step(async_client, user)
    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )
    assert complete_resp.status_code == 200, complete_resp.text

    create_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=auth_header(user["access_token"]),
        json={"display_name": "Mutated Name", "bio": "Mutated bio"},
    )

    assert create_resp.status_code == 409, create_resp.text
    assert create_resp.json()["detail"] == (
        "Profilsteget kan bara slutföras från ofullständig onboarding."
    )
    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] == "Welcome Pending User"
    assert me_resp.json()["bio"] == "Kort bio"
    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "completed",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


async def test_onboarding_complete_requires_explicit_refresh_boundary(async_client):
    user = await register_auth_user(
        async_client,
        email=f"complete_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Complete User",
    )
    me_resp = await async_client.get(
        "/profiles/me",
        headers=auth_header(user["access_token"]),
    )
    assert me_resp.status_code == 200, me_resp.text
    assert me_resp.json()["display_name"] is None
    assert me_resp.json()["bio"] is None
    await _create_profile_step(async_client, user)

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )
    assert complete_resp.status_code == 200, complete_resp.text
    assert complete_resp.json() == {
        "status": "completed",
        "onboarding_state": "completed",
        "token_refresh_required": True,
    }

    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "completed",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }

    refresh_resp = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": user["refresh_token"]},
    )
    assert refresh_resp.status_code == 200, refresh_resp.text
    refreshed = refresh_resp.json()
    assert set(refreshed) == {"access_token", "token_type", "refresh_token"}
    assert refreshed["token_type"] == "bearer"

    assert await _event_types_for(user["user_id"]) == ["onboarding_completed"]


@pytest.mark.parametrize("display_name", [None, "", "   "])
async def test_onboarding_complete_does_not_derive_completion_from_profile_name(
    async_client,
    display_name,
):
    user = await register_auth_user(
        async_client,
        email=f"missing_name_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Temporary Name",
    )
    await _create_profile_step(async_client, user)
    await _set_profile_display_name(user["user_id"], display_name)

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )

    assert complete_resp.status_code == 200, complete_resp.text
    assert complete_resp.json() == {
        "status": "completed",
        "onboarding_state": "completed",
        "token_refresh_required": True,
    }
    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "completed",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }
    assert await _event_types_for(user["user_id"]) == ["onboarding_completed"]


async def test_onboarding_complete_does_not_require_profile_projection_before_mutation(
    async_client,
):
    user = await register_auth_user(
        async_client,
        email=f"missing_profile_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Temporary Name",
    )
    await _create_profile_step(async_client, user)
    await _delete_profile_projection(user["user_id"])

    complete_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )

    assert complete_resp.status_code == 200, complete_resp.text
    assert complete_resp.json() == {
        "status": "completed",
        "onboarding_state": "completed",
        "token_refresh_required": True,
    }
    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "completed",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }
    assert await _event_types_for(user["user_id"]) == ["onboarding_completed"]


async def test_login_and_refresh_do_not_complete_onboarding(async_client):
    user = await register_auth_user(
        async_client,
        email=f"login_refresh_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Login Refresh User",
    )

    login_resp = await async_client.post(
        "/auth/login",
        json={"email": user["email"], "password": user["password"]},
    )
    assert login_resp.status_code == 200, login_resp.text
    login_tokens = login_resp.json()

    refresh_resp = await async_client.post(
        "/auth/refresh",
        json={"refresh_token": login_tokens["refresh_token"]},
    )
    assert refresh_resp.status_code == 200, refresh_resp.text

    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "incomplete",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }


async def test_onboarding_complete_rejects_completed_state(async_client):
    user = await register_auth_user(
        async_client,
        email=f"already_completed_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Already Completed User",
    )
    await _create_profile_step(async_client, user)

    first_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )
    second_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=auth_header(user["access_token"]),
    )

    assert first_resp.status_code == 200, first_resp.text
    assert second_resp.status_code == 409, second_resp.text
    assert second_resp.json()["detail"] == "Välkomststeget måste bekräftas först."
    assert await _event_types_for(user["user_id"]) == ["onboarding_completed"]


async def test_verify_email_does_not_complete_onboarding(async_client):
    user = await register_auth_user(
        async_client,
        email=f"verify_{uuid.uuid4().hex[:8]}@example.com",
        password="Passw0rd!",
        display_name="Verify User",
    )

    token = create_email_token(user["email"], "verify", 15)
    verify_resp = await async_client.get(
        "/auth/verify-email",
        params={"token": token},
    )
    assert verify_resp.status_code == 200, verify_resp.text
    assert verify_resp.json() == {"status": "verified"}

    assert await fetch_auth_subject(user["user_id"]) == {
        "onboarding_state": "incomplete",
        "role_v2": "learner",
        "role": "learner",
        "is_admin": False,
    }
