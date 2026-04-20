import pytest


pytestmark = pytest.mark.anyio("asyncio")


class _FakeCursor:
    def __init__(self, rows):
        self.rows = rows
        self.query = ""
        self.params = None

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def execute(self, query, params=()):
        self.query = query
        self.params = params

    async def fetchall(self):
        return self.rows


def _fake_get_conn(cursor):
    class _Context:
        async def __aenter__(self):
            return cursor

        async def __aexit__(self, exc_type, exc, tb):
            return False

    return _Context()


async def test_landing_teacher_profiles_query_uses_role_authority_only(monkeypatch):
    from app import models

    cursor = _FakeCursor(rows=[])
    monkeypatch.setattr(models, "get_conn", lambda: _fake_get_conn(cursor))

    rows = await models.list_teacher_profiles(limit=2)

    assert rows == []
    assert cursor.params == (2,)
    assert "subj.role::text = 'teacher'" in cursor.query
    assert "email" not in cursor.query.lower()
    assert "photo_url" not in cursor.query
    assert "avatar_media_id" in cursor.query


async def test_landing_teachers_uses_profile_projection_and_exact_shape(monkeypatch):
    from app.routes import landing

    calls = []

    async def fake_list_teacher_profiles():
        return [
            {
                "user_id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Teacher One",
                "bio": "First bio",
                "avatar_media_id": "media-1",
            },
            {
                "user_id": "00000000-0000-0000-0000-000000000002",
                "display_name": "Teacher Two",
                "bio": None,
                "avatar_media_id": None,
            },
        ]

    async def fake_profile_projection_with_avatar(profile):
        calls.append(profile)
        projected = dict(profile)
        projected["photo_url"] = (
            f"https://cdn.example/{profile['avatar_media_id']}.jpg"
            if profile.get("avatar_media_id")
            else None
        )
        return projected

    monkeypatch.setattr(landing.models, "list_teacher_profiles", fake_list_teacher_profiles)
    monkeypatch.setattr(
        landing,
        "profile_projection_with_avatar",
        fake_profile_projection_with_avatar,
    )

    response = await landing.teachers()
    payload = response.model_dump(mode="json")

    assert len(calls) == 2
    assert payload == {
        "items": [
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "display_name": "Teacher One",
                "avatar_url": "https://cdn.example/media-1.jpg",
                "bio": "First bio",
            },
            {
                "id": "00000000-0000-0000-0000-000000000002",
                "display_name": "Teacher Two",
                "avatar_url": None,
                "bio": None,
            },
        ]
    }
    assert set(payload["items"][0]) == {"id", "display_name", "avatar_url", "bio"}
    assert "user_id" not in payload["items"][0]
    assert "photo_url" not in payload["items"][0]


async def test_landing_teachers_empty_backend_data_returns_empty_items(monkeypatch):
    from app.routes import landing

    async def fake_list_teacher_profiles():
        return []

    async def fail_if_called(profile):
        raise AssertionError("projection should not run without backend rows")

    monkeypatch.setattr(landing.models, "list_teacher_profiles", fake_list_teacher_profiles)
    monkeypatch.setattr(landing, "profile_projection_with_avatar", fail_if_called)

    response = await landing.teachers()

    assert response.model_dump(mode="json") == {"items": []}
