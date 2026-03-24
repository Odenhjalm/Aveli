from __future__ import annotations

from datetime import datetime, timezone
import logging
from types import SimpleNamespace

import pytest
from psycopg import errors

from app import permissions
from app.main import app
from app.repositories import courses as courses_repo
from app.routes import studio as studio_routes
from app.services import courses_service

pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "course-1"
MEDIA_ID = "11111111-1111-1111-1111-111111111111"
DERIVED_PATH = "media/derived/cover/courses/course-1/cover.jpg"
LEGACY_URL = "/api/files/public-media/courses/legacy-cover.jpg"


class _FakeStorageService:
    def __init__(self, bucket: str) -> None:
        self.bucket = bucket

    def public_url(self, path: str) -> str:
        normalized = path.lstrip("/")
        return f"https://storage.local/{self.bucket}/{normalized}"

    async def get_presigned_url(self, path: str, ttl: int, *, download: bool = False):
        normalized = path.lstrip("/")
        return SimpleNamespace(
            url=f"https://signed.local/{self.bucket}/{normalized}",
            expires_in=ttl,
            headers={},
        )


def _course(*, cover_media_id: str | None = MEDIA_ID, cover_url: str | None = None) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "cover_media_id": cover_media_id,
        "cover_url": cover_url,
    }


class _FakeCourseCursor:
    def __init__(
        self,
        *,
        rows: list[dict[str, object]] | None = None,
        fail_on_direct_step_level: bool = False,
    ) -> None:
        self._rows = rows or []
        self._fail_on_direct_step_level = fail_on_direct_step_level
        self.executed: list[tuple[str, tuple[object, ...]]] = []

    async def __aenter__(self) -> _FakeCourseCursor:
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    async def execute(
        self,
        query: str,
        params: list[object] | tuple[object, ...] | None = None,
    ) -> None:
        normalized_query = " ".join(query.split())
        normalized_params = tuple(params or ())
        self.executed.append((normalized_query, normalized_params))
        if self._fail_on_direct_step_level and "c.step_level" in normalized_query:
            raise errors.UndefinedColumn('column "step_level" does not exist')

    async def fetchone(self) -> dict[str, object] | None:
        return self._rows[0] if self._rows else None

    async def fetchall(self) -> list[dict[str, object]]:
        return list(self._rows)


class _FakeCourseConnection:
    def __init__(self, cursor: _FakeCourseCursor) -> None:
        self._cursor = cursor
        self.rollback_calls = 0

    async def __aenter__(self) -> _FakeCourseConnection:
        return self

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        return False

    def cursor(self, *, row_factory=None) -> _FakeCourseCursor:
        return self._cursor

    async def rollback(self) -> None:
        self.rollback_calls += 1


class _FakeCoursePool:
    def __init__(self, connection: _FakeCourseConnection) -> None:
        self._connection = connection

    def connection(self) -> _FakeCourseConnection:
        return self._connection


def _asset(*, state: str = "ready", path: str = DERIVED_PATH) -> dict:
    return {
        "id": MEDIA_ID,
        "course_id": COURSE_ID,
        "purpose": "course_cover",
        "state": state,
        "streaming_object_path": path,
        "streaming_storage_bucket": "public-media",
        "storage_bucket": "course-media",
    }


def _install_storage(monkeypatch, *, existing_pairs: dict[tuple[str, str], bool]):
    async def fake_fetch_storage_object_existence(pairs):
        normalized = {tuple(pair): existing_pairs.get(tuple(pair), False) for pair in pairs}
        return normalized, True

    monkeypatch.setattr(
        courses_service.storage_objects,
        "fetch_storage_object_existence",
        fake_fetch_storage_object_existence,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: _FakeStorageService(bucket),
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_signer.settings,
        "supabase_url",
        None,
        raising=False,
    )


async def test_resolve_course_cover_ready_asset_returns_control_plane(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_media_asset(media_id: str):
        assert media_id == MEDIA_ID
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "ready",
        "resolved_url": f"https://storage.local/public-media/{DERIVED_PATH}",
        "source": "control_plane",
    }


async def test_resolve_course_cover_uploaded_asset_returns_placeholder(monkeypatch):
    async def fake_get_media_asset(media_id: str):
        return _asset(state="uploaded")

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "uploaded",
        "resolved_url": None,
        "source": "placeholder",
    }


async def test_resolve_course_cover_missing_asset_returns_placeholder(monkeypatch):
    async def fake_get_media_asset(media_id: str):
        return None

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "placeholder",
        "resolved_url": None,
        "source": "placeholder",
    }


async def test_resolve_course_cover_missing_asset_without_legacy_returns_placeholder(
    monkeypatch,
):
    async def fake_get_media_asset(media_id: str):
        return None

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "placeholder",
        "resolved_url": None,
        "source": "placeholder",
    }


async def test_resolve_course_cover_missing_derived_bytes_never_returns_ready(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): False})

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == {
        "media_id": MEDIA_ID,
        "state": "missing",
        "resolved_url": None,
        "source": "placeholder",
    }


async def test_resolve_course_cover_logs_contract_violation(monkeypatch, caplog):
    asset = _asset(state="processing")

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    with caplog.at_level(logging.ERROR):
        cover = await courses_service.resolve_course_cover(
            course_id=COURSE_ID,
            cover_media_id=MEDIA_ID,
        )

    assert cover["source"] == "placeholder"
    assert "COURSE_COVER_RESOLVED_ASSET_NOT_READY" in caplog.text


async def test_attach_course_cover_read_contract_respects_feature_flag(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_media_asset(media_id: str):
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )

    course_enabled = _course()
    monkeypatch.setenv("COURSE_COVER_RESOLVED_READ_ENABLED", "1")
    await courses_service.attach_course_cover_read_contract(course_enabled)
    assert course_enabled["cover"]["source"] == "control_plane"
    assert "cover_url" not in course_enabled

    course_disabled = _course()
    course_disabled["cover"] = {
        "media_id": MEDIA_ID,
        "state": "placeholder",
        "resolved_url": None,
        "source": "placeholder",
    }
    monkeypatch.delenv("COURSE_COVER_RESOLVED_READ_ENABLED", raising=False)
    await courses_service.attach_course_cover_read_contract(course_disabled)
    assert course_disabled["cover"]["source"] == "control_plane"
    assert "cover_url" not in course_disabled
    assert (
        course_disabled["cover"]["resolved_url"]
        == f"https://storage.local/public-media/{DERIVED_PATH}"
    )

    legacy_only = _course(cover_media_id=None, cover_url=LEGACY_URL)
    legacy_only["cover"] = {
        "media_id": None,
        "state": "placeholder",
        "resolved_url": None,
        "source": "placeholder",
    }
    await courses_service.attach_course_cover_read_contract(legacy_only)
    assert "cover" not in legacy_only
    assert "cover_url" not in legacy_only


async def test_fetch_course_includes_cover_when_cover_media_id_resolves(monkeypatch):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return _course()

    async def fake_get_media_asset(media_id: str):
        assert media_id == MEDIA_ID
        return asset

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    monkeypatch.delenv("COURSE_COVER_RESOLVED_READ_ENABLED", raising=False)

    course = await courses_service.fetch_course(course_id=COURSE_ID)

    assert course is not None
    assert "cover_url" not in course
    assert course["cover"]["media_id"] == MEDIA_ID
    assert course["cover"]["source"] == "control_plane"
    assert (
        course["cover"]["resolved_url"]
        == f"https://storage.local/public-media/{DERIVED_PATH}"
    )


async def test_course_repository_read_preserves_cover_media_id_when_step_level_missing(
    monkeypatch,
):
    row = {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "description": "Example",
        "cover_url": LEGACY_URL,
        "cover_media_id": MEDIA_ID,
        "video_url": None,
        "branch": None,
        "is_free_intro": False,
        "journey_step": None,
        "step_level": "step1",
        "course_family": "course",
        "price_amount_cents": 0,
        "currency": "sek",
        "stripe_product_id": None,
        "stripe_price_id": None,
        "is_published": True,
        "created_by": MEDIA_ID,
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
    }
    cursor = _FakeCourseCursor(
        rows=[row],
        fail_on_direct_step_level=True,
    )
    connection = _FakeCourseConnection(cursor)
    monkeypatch.setattr(
        courses_repo,
        "pool",
        _FakeCoursePool(connection),
        raising=True,
    )

    course = await courses_repo.get_course(course_id=COURSE_ID)

    assert course is not None
    assert course["cover_media_id"] == MEDIA_ID
    assert course["cover_url"] == LEGACY_URL
    assert connection.rollback_calls == 0
    assert all(
        "NULL::uuid AS cover_media_id" not in query for query, _ in cursor.executed
    )


async def test_list_public_courses_includes_cover_when_cover_media_id_resolves(
    monkeypatch,
):
    asset = _asset()
    _install_storage(monkeypatch, existing_pairs={("public-media", DERIVED_PATH): True})

    async def fake_list_public_courses(**kwargs):
        return [_course()]

    async def fake_get_media_asset(media_id: str):
        assert media_id == MEDIA_ID
        return asset

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_media_asset",
        fake_get_media_asset,
        raising=True,
    )
    monkeypatch.delenv("COURSE_COVER_RESOLVED_READ_ENABLED", raising=False)

    courses = await courses_service.list_public_courses()

    assert len(courses) == 1
    assert "cover_url" not in courses[0]
    assert courses[0]["cover"]["media_id"] == MEDIA_ID
    assert courses[0]["cover"]["source"] == "control_plane"


async def test_courses_list_response_includes_cover_when_present(
    async_client, monkeypatch
):
    now = datetime.now(timezone.utc)

    async def fake_list_public_courses(**kwargs):
        return [
            {
                "id": MEDIA_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_media_id": MEDIA_ID,
                "cover": {
                    "media_id": MEDIA_ID,
                    "state": "ready",
                    "resolved_url": "https://storage.local/public-media/media/derived/cover/courses/course-1/cover.jpg",
                    "source": "control_plane",
                },
                "video_url": None,
                "is_free_intro": False,
                "journey_step": None,
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover_url" not in body["items"][0]
    assert body["items"][0]["cover"]["source"] == "control_plane"


async def test_courses_list_response_omits_cover_when_absent(async_client, monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_list_public_courses(**kwargs):
        return [
            {
                "id": MEDIA_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_media_id": MEDIA_ID,
                "video_url": None,
                "is_free_intro": False,
                "journey_step": None,
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover_url" not in body["items"][0]
    assert "cover" not in body["items"][0]


async def test_intro_first_response_omits_cover_url(async_client, monkeypatch):
    now = datetime.now(timezone.utc)

    async def fake_list_public_courses(**kwargs):
        assert kwargs == {
            "published_only": True,
            "free_intro": True,
            "limit": 1,
        }
        return [
            {
                "id": MEDIA_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_media_id": MEDIA_ID,
                "cover": {
                    "media_id": MEDIA_ID,
                    "state": "ready",
                    "resolved_url": "https://storage.local/public-media/media/derived/cover/courses/course-1/cover.jpg",
                    "source": "control_plane",
                },
                "video_url": None,
                "is_free_intro": True,
                "journey_step": None,
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )

    response = await async_client.get("/courses/intro-first")
    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover_url" not in body["course"]
    assert body["course"]["cover"]["source"] == "control_plane"


async def test_studio_courses_list_response_includes_cover_when_present(
    async_client, monkeypatch
):
    now = datetime.now(timezone.utc)
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": MEDIA_ID}

    async def fake_apply_course_read_contract(courses):
        rows = [courses] if isinstance(courses, dict) else list(courses or [])
        for row in rows:
            row.pop("cover_url", None)

    async def fake_list_courses(**kwargs):
        assert kwargs == {"teacher_id": MEDIA_ID}
        return [
            {
                "id": COURSE_ID,
                "slug": "course-1",
                "title": "Course 1",
                "description": "Example",
                "cover_media_id": MEDIA_ID,
                "cover": {
                    "media_id": MEDIA_ID,
                    "state": "ready",
                    "resolved_url": "https://storage.local/public-media/media/derived/cover/courses/course-1/cover.jpg",
                    "source": "control_plane",
                },
                "video_url": None,
                "branch": None,
                "is_free_intro": False,
                "journey_step": None,
                "step_level": "step1",
                "course_family": "course",
                "price_amount_cents": 0,
                "currency": "sek",
                "stripe_product_id": None,
                "stripe_price_id": None,
                "is_published": True,
                "created_by": MEDIA_ID,
                "created_at": now,
                "updated_at": now,
            }
        ]

    monkeypatch.setattr(
        studio_routes.courses_service,
        "list_courses",
        fake_list_courses,
        raising=True,
    )
    monkeypatch.setattr(
        studio_routes,
        "_apply_course_read_contract",
        fake_apply_course_read_contract,
        raising=True,
    )

    try:
        response = await async_client.get("/studio/courses")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover_url" not in body["items"][0]
    assert body["items"][0]["cover"]["source"] == "control_plane"
    assert body["items"][0]["cover"]["media_id"] == MEDIA_ID
    assert body["items"][0]["cover_media_id"] == MEDIA_ID


async def test_studio_course_detail_response_includes_cover_when_present(
    async_client, monkeypatch
):
    now = datetime.now(timezone.utc)
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": MEDIA_ID}

    async def fake_apply_course_read_contract(courses):
        rows = [courses] if isinstance(courses, dict) else list(courses or [])
        for row in rows:
            row.pop("cover_url", None)

    async def fake_is_course_owner(user_id: str, course_id: str):
        assert user_id == MEDIA_ID
        assert course_id == COURSE_ID
        return True

    async def fake_fetch_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return {
            "id": COURSE_ID,
            "slug": "course-1",
            "title": "Course 1",
            "description": "Example",
            "cover_media_id": MEDIA_ID,
            "cover": {
                "media_id": MEDIA_ID,
                "state": "ready",
                "resolved_url": "https://storage.local/public-media/media/derived/cover/courses/course-1/cover.jpg",
                "source": "control_plane",
            },
            "video_url": None,
            "branch": None,
            "is_free_intro": False,
            "journey_step": None,
            "price_amount_cents": 0,
            "currency": "sek",
            "stripe_product_id": None,
            "stripe_price_id": None,
            "is_published": True,
            "created_by": MEDIA_ID,
            "created_at": now,
            "updated_at": now,
        }

    monkeypatch.setattr(
        studio_routes.models,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        studio_routes.courses_service,
        "fetch_course",
        fake_fetch_course,
        raising=True,
    )
    monkeypatch.setattr(
        studio_routes,
        "_apply_course_read_contract",
        fake_apply_course_read_contract,
        raising=True,
    )

    try:
        response = await async_client.get(f"/studio/courses/{COURSE_ID}")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200, response.text
    body = response.json()
    assert "cover_url" not in body
    assert body["cover"]["source"] == "control_plane"
    assert body["cover"]["media_id"] == MEDIA_ID
    assert body["cover_media_id"] == MEDIA_ID


async def test_studio_course_create_rejects_cover_url_payload(async_client):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": MEDIA_ID}

    try:
        response = await async_client.post(
            "/studio/courses",
            json={
                "title": "Course 1",
                "slug": "course-1",
                "cover_url": LEGACY_URL,
            },
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422, response.text


async def test_studio_course_update_rejects_cover_url_payload(async_client):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": MEDIA_ID}

    try:
        response = await async_client.patch(
            f"/studio/courses/{COURSE_ID}",
            json={"cover_url": LEGACY_URL},
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422, response.text
