import pytest

from app.main import app


pytestmark = pytest.mark.anyio("asyncio")


def test_removed_legacy_auth_and_profile_routes_are_not_mounted():
    inventory = {
        (route.path, method)
        for route in app.routes
        for method in getattr(route, "methods", set())
        if method not in {"HEAD", "OPTIONS"}
    }

    forbidden = {
        ("/auth/change-password", "POST"),
        ("/auth/request-password-reset", "POST"),
        ("/profiles/me/avatar", "POST"),
    }

    assert inventory.isdisjoint(forbidden)


async def test_register_rejects_referral_code_with_canonical_failure_envelope(
    async_client,
):
    resp = await async_client.post(
        "/auth/register",
        json={
            "email": "referral@example.com",
            "password": "Secret123!",
            "referral_code": "legacy-code",
        },
    )

    assert resp.status_code == 422, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "validation_error",
        "message": "Begaran innehaller ogiltiga eller saknade falt.",
        "field_errors": [
            {
                "field": "referral_code",
                "error_code": "extra_forbidden",
                "message": "Faltet ar inte tillatet.",
            }
        ],
    }


async def test_register_rejects_display_name_with_canonical_failure_envelope(
    async_client,
):
    resp = await async_client.post(
        "/auth/register",
        json={
            "email": "name-at-register@example.com",
            "password": "Secret123!",
            "display_name": "Register Name",
        },
    )

    assert resp.status_code == 422, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "validation_error",
        "message": "Begaran innehaller ogiltiga eller saknade falt.",
        "field_errors": [
            {
                "field": "display_name",
                "error_code": "extra_forbidden",
                "message": "Faltet ar inte tillatet.",
            }
        ],
    }


async def test_invalid_login_uses_canonical_failure_envelope(async_client):
    resp = await async_client.post(
        "/auth/login",
        json={"email": "missing@example.com", "password": "wrong-password"},
    )

    assert resp.status_code == 401, resp.text
    assert resp.json() == {
        "status": "error",
        "error_code": "invalid_credentials",
        "message": "Fel e-postadress eller losenord.",
    }
