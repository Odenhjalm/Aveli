from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
import uuid

import pytest

from app import db, repositories
from app.repositories import studio_home_player_library as library_repo
from app.routes import home as home_routes
from app.routes import studio as studio_routes


pytestmark = pytest.mark.anyio("asyncio")


def _timestamp(*, minutes_ago: int = 0) -> datetime:
    return datetime.now(timezone.utc) - timedelta(minutes=minutes_ago)


async def _promote_to_teacher(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                UPDATE app.auth_subjects
                   SET role = 'teacher'
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            await conn.commit()


async def _register_teacher(async_client) -> tuple[dict[str, str], str]:
    email = f"teacher_{uuid.uuid4().hex[:8]}@example.com"
    register_resp = await async_client.post(
        "/auth/register",
        json={"email": email, "password": "Secret123!"},
    )
    assert register_resp.status_code == 201, register_resp.text
    tokens = register_resp.json()
    headers = {"Authorization": f"Bearer {tokens['access_token']}"}

    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = profile_resp.json()["user_id"]

    onboarding_profile_resp = await async_client.post(
        "/auth/onboarding/create-profile",
        headers=headers,
        json={"display_name": "Teacher", "bio": None},
    )
    assert onboarding_profile_resp.status_code == 200, onboarding_profile_resp.text
    onboarding_resp = await async_client.post(
        "/auth/onboarding/complete",
        headers=headers,
    )
    assert onboarding_resp.status_code == 200, onboarding_resp.text
    await repositories.upsert_membership_record(
        user_id,
        status="active",
        source="coupon",
    )
    await _promote_to_teacher(user_id)
    return headers, user_id


async def _cleanup_user(user_id: str) -> None:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute("DELETE FROM app.refresh_tokens WHERE user_id = %s", (user_id,))
            await cur.execute("DELETE FROM auth.users WHERE id = %s", (user_id,))
            await conn.commit()


class _FakeCursor:
    def __init__(self) -> None:
        self.executed: list[tuple[str, object]] = []

    async def execute(self, query: str, params=None) -> None:
        self.executed.append((query, params))

    async def fetchall(self):
        return []


class _FakeConn:
    def __init__(self, cursor: _FakeCursor) -> None:
        self._cursor = cursor

    async def __aenter__(self) -> _FakeCursor:
        return self._cursor

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False


def _install_fake_conn(monkeypatch, cursor: _FakeCursor) -> None:
    monkeypatch.setattr(library_repo, "get_conn", lambda: _FakeConn(cursor))


def _assert_no_forbidden_library_fields(item: dict[str, object]) -> None:
    forbidden = {
        "media_id",
        "owner_id",
        "original_name",
        "original_filename",
        "original_content_type",
        "original_size_bytes",
        "storage_url",
        "storage_path",
        "signed_url",
        "download_url",
        "upload_url",
    }
    assert forbidden.isdisjoint(item)


async def test_studio_home_player_library_endpoint_returns_canonical_groups(
    async_client,
    monkeypatch,
):
    headers, user_id = await _register_teacher(async_client)
    try:
        upload_id = str(uuid.uuid4())
        media_asset_id = str(uuid.uuid4())
        link_id = str(uuid.uuid4())
        lesson_media_id = str(uuid.uuid4())
        lesson_id = str(uuid.uuid4())
        course_id = str(uuid.uuid4())
        now = _timestamp()

        async def fake_get_home_player_library(*, teacher_id: str):
            assert teacher_id == user_id
            return {
                "uploads": [
                    {
                        "id": upload_id,
                        "media_asset_id": media_asset_id,
                        "title": "Direct audio",
                        "active": True,
                        "created_at": now,
                        "updated_at": now,
                        "kind": "audio",
                        "media_state": "uploaded",
                    }
                ],
                "course_links": [
                    {
                        "id": link_id,
                        "lesson_media_id": lesson_media_id,
                        "title": "Linked audio",
                        "course_title": "Course title",
                        "enabled": True,
                        "created_at": now,
                        "updated_at": now,
                        "kind": "audio",
                        "status": "active",
                    }
                ],
                "course_media": [
                    {
                        "id": lesson_media_id,
                        "lesson_id": lesson_id,
                        "lesson_title": "Lesson title",
                        "course_id": course_id,
                        "course_title": "Course title",
                        "course_slug": "course-title",
                        "kind": "audio",
                        "content_type": None,
                        "duration_seconds": None,
                        "position": 1,
                        "created_at": None,
                        "media": None,
                    }
                ],
            }

        monkeypatch.setattr(
            studio_routes.studio_home_player_library_repo,
            "get_home_player_library",
            fake_get_home_player_library,
            raising=True,
        )

        response = await async_client.get(
            "/studio/home-player/library",
            headers=headers,
        )
        assert response.status_code == 200, response.text
        payload = response.json()
        assert set(payload) == {"uploads", "course_links", "course_media", "text_bundle"}
        assert isinstance(payload["text_bundle"], dict)
        assert "studio_editor.profile_media.home_player_library_title" in payload["text_bundle"]
        title_text = payload["text_bundle"]["studio_editor.profile_media.home_player_library_title"]
        assert title_text == {
            "surface_id": "TXT-SURF-071",
            "text_id": "studio_editor.profile_media.home_player_library_title",
            "authority_class": "contract_text",
            "canonical_owner": "backend_text_catalog",
            "source_contract": "actual_truth/contracts/backend_text_catalog_contract.md",
            "backend_namespace": "backend_text_catalog.studio_editor",
            "api_surface": "/studio/home-player/library",
            "delivery_surface": "/studio/home-player/library",
            "render_surface": "frontend/lib/features/studio/presentation/profile_media_page.dart",
            "language": "sv",
            "interpolation_keys": [],
            "forbidden_render_fields": [],
            "value": "Home-spelarens bibliotek",
        }

        upload = payload["uploads"][0]
        assert set(upload) == {
            "id",
            "media_asset_id",
            "title",
            "active",
            "created_at",
            "updated_at",
            "kind",
            "media_state",
        }
        assert upload["media_asset_id"] == media_asset_id
        assert upload["title"] == "Direct audio"
        assert upload["kind"] == "audio"
        assert upload["media_state"] == "uploaded"
        _assert_no_forbidden_library_fields(upload)

        link = payload["course_links"][0]
        assert link["lesson_media_id"] == lesson_media_id
        assert link["title"] == "Linked audio"
        assert link["course_title"] == "Course title"
        assert link["kind"] == "audio"
        assert link["status"] == "active"
        _assert_no_forbidden_library_fields(link)

        source = payload["course_media"][0]
        assert source["id"] == lesson_media_id
        assert source["lesson_id"] == lesson_id
        assert source["course_id"] == course_id
        assert source["kind"] == "audio"
        assert source["media"] is None
        _assert_no_forbidden_library_fields(source)
    finally:
        await _cleanup_user(user_id)


async def test_studio_home_player_library_queries_use_baseline_v2_columns(
    monkeypatch,
):
    cursor = _FakeCursor()
    _install_fake_conn(monkeypatch, cursor)

    payload = await library_repo.get_home_player_library(teacher_id=str(uuid.uuid4()))

    assert payload == {"uploads": [], "course_links": [], "course_media": []}
    assert len(cursor.executed) == 3
    queries = "\n".join(query for query, _ in cursor.executed).lower()
    for forbidden in (
        "owner_id",
        "original_",
        "storage",
        "signed_url",
        "download_url",
        "runtime_media",
        "course_title_snapshot",
        "hpu.kind",
        "hpcl.teacher_id",
    ):
        assert forbidden not in queries
    assert re.search(r"\bmedia_id\b", queries) is None

    assert "from app.home_player_uploads hpu" in queries
    assert "join app.media_assets ma on ma.id = hpu.media_asset_id" in queries
    assert "hpu.teacher_id = %s::uuid" in queries
    assert "ma.purpose = 'home_player_audio'::app.media_purpose" in queries

    assert "from app.home_player_course_links hpcl" in queries
    assert "join app.lesson_media lm on lm.id = hpcl.lesson_media_id" in queries
    assert "join app.courses c on c.id = l.course_id" in queries
    assert "c.teacher_id = %s::uuid" in queries

    assert "from app.lesson_media lm" in queries
    assert "ma.purpose = 'lesson_media'::app.media_purpose" in queries
    assert "ma.media_type = 'audio'::app.media_type" in queries


async def test_studio_home_player_library_endpoint_runs_against_baseline_schema(
    async_client,
):
    headers, user_id = await _register_teacher(async_client)
    try:
        response = await async_client.get(
            "/studio/home-player/library",
            headers=headers,
        )
        assert response.status_code == 200, response.text
        payload = response.json()
        assert payload == {
            "uploads": [],
            "course_links": [],
            "course_media": [],
            "text_bundle": payload["text_bundle"],
        }
        assert payload["text_bundle"]["home.player_upload.title"]["value"] == (
            "Lägg till ljud i hemspelaren"
        )
        assert payload["text_bundle"]["home.player_upload.title"]["authority_class"] == (
            "contract_text"
        )
        assert payload["text_bundle"]["home.player_upload.auth_failed_error"]["value"] == (
            "Du har inte behörighet att hantera uppladdningen i Home-spelaren."
        )
    finally:
        await _cleanup_user(user_id)


async def test_studio_home_player_library_requires_backend_owned_auth_copy(async_client):
    response = await async_client.get("/studio/home-player/library")
    assert response.status_code == 401, response.text
    assert response.json() == {
        "status": "error",
        "error_code": "home_player_auth_failed",
        "message": "Du har inte behörighet att hantera Home-spelaren.",
    }


async def test_home_audio_runtime_endpoint_shape_is_unaffected(
    async_client,
    monkeypatch,
):
    headers, user_id = await _register_teacher(async_client)
    try:
        media_asset_id = str(uuid.uuid4())
        now = _timestamp()

        async def fake_list_home_audio_media(user_id_arg: str, *, limit: int = 12):
            assert user_id_arg == user_id
            assert limit == 12
            return [
                {
                    "source_type": "direct_upload",
                    "title": "Runtime audio",
                    "lesson_title": None,
                    "course_id": None,
                    "course_title": None,
                    "course_slug": None,
                    "teacher_id": user_id,
                    "teacher_name": None,
                    "created_at": now,
                    "media": {
                        "media_id": media_asset_id,
                        "state": "uploaded",
                        "resolved_url": None,
                    },
                }
            ]

        monkeypatch.setattr(
            home_routes.home_audio_service,
            "list_home_audio_media",
            fake_list_home_audio_media,
            raising=True,
        )

        response = await async_client.get("/home/audio", headers=headers)
        assert response.status_code == 200, response.text
        payload = response.json()
        assert set(payload) == {"items", "text_bundle"}
        assert "uploads" not in payload
        assert "course_links" not in payload
        assert "course_media" not in payload
        assert payload["text_bundle"]["home.audio.section_title"]["value"] == (
            "Ljud i Home-spelaren"
        )
        item = payload["items"][0]
        assert item["media"] == {
            "media_id": media_asset_id,
            "state": "uploaded",
            "resolved_url": None,
        }
    finally:
        await _cleanup_user(user_id)
