import uuid


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
    me_resp = await async_client.get("/auth/me", headers=headers)
    assert me_resp.status_code == 200
    return headers, me_resp.json()["user_id"], email
