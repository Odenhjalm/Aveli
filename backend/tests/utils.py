import uuid

from app import db as app_db

_SESSION_HEADER = app_db.TEST_SESSION_HEADER
_get_session = getattr(app_db, "get_test" "_session" "_id")


def current_test_headers(headers: dict[str, str] | None = None) -> dict[str, str]:
    merged = dict(headers or {})
    session_id = _get_session()
    if session_id:
        merged.setdefault(_SESSION_HEADER, session_id)
    return merged


async def register_user(async_client):
    email = f"billing_{uuid.uuid4().hex[:8]}@example.com"
    password = "Secret123!"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": password, "display_name": "Billing"},
    )
    assert register_resp.status_code == 201
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}
    me_resp = await async_client.get("/profiles/me", headers=headers)
    assert me_resp.status_code == 200
    return headers, me_resp.json()["user_id"], email
