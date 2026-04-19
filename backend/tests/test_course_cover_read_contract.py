from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest
from pydantic import ValidationError

from app import permissions, schemas
from app.main import app
from app.routes import courses as courses_routes
from app.routes import landing as landing_routes
from app.routes import studio as studio_routes
from app.services import courses_service


pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "11111111-1111-1111-1111-111111111111"
COURSE_GROUP_ID = "22222222-2222-2222-2222-222222222222"
MEDIA_ID = "33333333-3333-3333-3333-333333333333"
TEACHER_ID = "44444444-4444-4444-4444-444444444444"
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


def _course(*, cover_media_id: str | None = MEDIA_ID) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "course_group_id": COURSE_GROUP_ID,
        "group_position": 1,
        "cover_media_id": cover_media_id,
        "price_amount_cents": 0,
        "drip_enabled": False,
        "drip_interval_days": None,
    }


def _landing_course(*, cover: dict | None) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "course_group_id": COURSE_GROUP_ID,
        "group_position": 1,
        "cover_media_id": MEDIA_ID,
        "cover": cover,
        "price_amount_cents": 0,
        "drip_enabled": False,
        "drip_interval_days": None,
    }


def _detail_row(
    *,
    cover_media_id: str | None = MEDIA_ID,
    price_amount_cents: int | None = 0,
) -> dict:
    return {
        **_course(cover_media_id=cover_media_id),
        "price_amount_cents": price_amount_cents,
        "short_description": "Detail",
        "lesson_id": "55555555-5555-5555-5555-555555555555",
        "lesson_title": "Lesson 1",
        "lesson_position": 1,
    }


def _runtime_row(
    *,
    state: str = "ready",
    path: str = DERIVED_PATH,
    media_type: str = "image",
    purpose: str = "course_cover",
    playback_format: str = "jpg",
) -> dict:
    return {
        "course_id": COURSE_ID,
        "media_asset_id": MEDIA_ID,
        "media_type": media_type,
        "purpose": purpose,
        "playback_object_path": path,
        "playback_format": playback_format,
        "state": state,
    }


def _course_cover_pipeline_asset(
    *,
    media_type: str = "image",
    purpose: str = "course_cover",
    state: str = "ready",
    playback_format: str = "jpg",
    original_object_path: str | None = None,
    playback_object_path: str | None = "__DEFAULT__",
) -> dict:
    exact_playback_object_path = (
        f"media/derived/cover/courses/{COURSE_ID}/cover.jpg"
        if playback_object_path == "__DEFAULT__"
        else playback_object_path
    )
    return {
        "media_type": media_type,
        "purpose": purpose,
        "state": state,
        "original_object_path": original_object_path
        or f"media/source/cover/courses/{COURSE_ID}/source.png",
        "playback_object_path": exact_playback_object_path,
        "playback_format": playback_format,
    }


def _resolved_cover_payload(path: str = DERIVED_PATH) -> dict[str, str | None]:
    return {
        "media_id": MEDIA_ID,
        "state": "ready",
        "resolved_url": f"https://storage.local/public-media/{path}",
    }


def _install_storage(monkeypatch) -> None:
    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: _FakeStorageService(bucket),
        raising=True,
    )


async def test_resolve_course_cover_ready_asset_returns_public_url(monkeypatch):
    _install_storage(monkeypatch)

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        assert course_id == COURSE_ID
        assert media_asset_id == MEDIA_ID
        return _runtime_row()

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover == _resolved_cover_payload()


async def test_validate_course_cover_assignment_accepts_ready_canonical_media(
    monkeypatch,
):
    _install_storage(monkeypatch)

    async def fake_get_pipeline_asset(media_asset_id: str):
        assert media_asset_id == MEDIA_ID
        return _course_cover_pipeline_asset()

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_course_cover_pipeline_asset",
        fake_get_pipeline_asset,
        raising=True,
    )

    assert (
        await courses_service._validate_course_cover_assignment(
            course_id=COURSE_ID,
            cover_media_id=MEDIA_ID,
        )
        == MEDIA_ID
    )


@pytest.mark.parametrize(
    ("cover_media_id", "message"),
    [
        ("https://cdn.test/cover.jpg", "cover_media_id must be a UUID or null"),
        ({"media_id": MEDIA_ID}, "cover_media_id must be a UUID or null"),
        ("media/source/cover/courses/course-1/cover.jpg", "cover_media_id must be a UUID or null"),
    ],
)
async def test_validate_course_cover_assignment_rejects_non_id_inputs(
    cover_media_id,
    message: str,
):
    with pytest.raises(ValueError, match=message):
        await courses_service._validate_course_cover_assignment(
            course_id=COURSE_ID,
            cover_media_id=cover_media_id,
        )


@pytest.mark.parametrize(
    ("asset", "message"),
    [
        (None, "cover_media_id does not reference an existing media asset"),
        (
            _course_cover_pipeline_asset(media_type="audio"),
            "cover_media_id must reference image media",
        ),
        (
            _course_cover_pipeline_asset(purpose="lesson_media"),
            "cover_media_id must reference course cover media",
        ),
        (
            _course_cover_pipeline_asset(state="uploaded"),
            "cover_media_id must reference ready media",
        ),
        (
            _course_cover_pipeline_asset(
                original_object_path="media/source/cover/courses/wrong-course/source.png"
            ),
            "cover_media_id is not scoped to this course",
        ),
        (
            _course_cover_pipeline_asset(
                original_object_path="courses/course-1/covers/source.png"
            ),
            "cover_media_id is not scoped to this course",
        ),
        (
            _course_cover_pipeline_asset(playback_object_path=""),
            "cover_media_id is missing ready media output",
        ),
        (
            _course_cover_pipeline_asset(playback_format="png"),
            "cover_media_id ready media output must be jpg",
        ),
        (
            _course_cover_pipeline_asset(
                playback_object_path="media/derived/cover/courses/wrong-course/cover.jpg"
            ),
            "cover_media_id ready output is not scoped to this course",
        ),
    ],
)
async def test_validate_course_cover_assignment_rejects_invalid_media_assets(
    monkeypatch,
    asset,
    message: str,
):
    async def fake_get_pipeline_asset(media_asset_id: str):
        assert media_asset_id == MEDIA_ID
        return asset

    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_course_cover_pipeline_asset",
        fake_get_pipeline_asset,
        raising=True,
    )

    with pytest.raises(ValueError, match=message):
        await courses_service._validate_course_cover_assignment(
            course_id=COURSE_ID,
            cover_media_id=MEDIA_ID,
        )


async def test_validate_course_cover_assignment_allows_explicit_clear():
    assert (
        await courses_service._validate_course_cover_assignment(
            course_id=COURSE_ID,
            cover_media_id=None,
        )
        is None
    )


async def test_update_course_cover_omission_does_not_validate_or_clear(
    monkeypatch,
):
    existing = _course()
    changed = {**existing, "title": "Renamed"}

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return existing

    async def fake_is_course_owner(course_id: str, teacher_id: str):
        assert course_id == COURSE_ID
        assert teacher_id == TEACHER_ID
        return True

    async def fake_update_course(course_id: str, patch: dict):
        assert course_id == COURSE_ID
        assert patch == {"title": "Renamed"}
        return changed

    async def fail_get_pipeline_asset(media_asset_id: str):
        raise AssertionError("omitted cover_media_id must not validate media")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "update_course",
        fake_update_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_course_cover_pipeline_asset",
        fail_get_pipeline_asset,
        raising=True,
    )

    assert (
        await courses_service.update_course(
            COURSE_ID,
            {"title": "Renamed"},
            teacher_id=TEACHER_ID,
        )
        == changed
    )


async def test_update_course_rejects_wrong_teacher_before_cover_assignment(
    monkeypatch,
):
    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return _course()

    async def fake_is_course_owner(course_id: str, teacher_id: str):
        assert course_id == COURSE_ID
        assert teacher_id == TEACHER_ID
        return False

    async def fail_get_pipeline_asset(media_asset_id: str):
        raise AssertionError("wrong teacher must not reach media validation")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "is_course_owner",
        fake_is_course_owner,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.media_assets_repo,
        "get_course_cover_pipeline_asset",
        fail_get_pipeline_asset,
        raising=True,
    )

    with pytest.raises(PermissionError, match="Not course owner"):
        await courses_service.update_course(
            COURSE_ID,
            {"cover_media_id": MEDIA_ID},
            teacher_id=TEACHER_ID,
        )


async def test_resolve_course_cover_uploaded_asset_returns_null(monkeypatch):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(state="uploaded")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_missing_asset_returns_null(monkeypatch):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return None

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_missing_derived_bytes_never_returns_ready(monkeypatch):
    _install_storage(monkeypatch)

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(path="")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_non_jpg_format_returns_null(monkeypatch):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(playback_format="png")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_wrong_media_type_returns_null(monkeypatch):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(media_type="audio")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_wrong_purpose_returns_null(monkeypatch):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(purpose="profile_media")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_blank_storage_url_returns_null(monkeypatch):
    class BlankUrlStorageService:
        def public_url(self, path: str) -> str:
            return ""

    monkeypatch.setattr(
        courses_service.storage_service,
        "get_storage_service",
        lambda bucket: BlankUrlStorageService(),
        raising=True,
    )

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row()

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    cover = await courses_service.resolve_course_cover(
        course_id=COURSE_ID,
        cover_media_id=MEDIA_ID,
    )

    assert cover is None


async def test_resolve_course_cover_logs_contract_violation(monkeypatch, caplog):
    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(state="processing")

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    with caplog.at_level("ERROR"):
        cover = await courses_service.resolve_course_cover(
            course_id=COURSE_ID,
            cover_media_id=MEDIA_ID,
        )

    assert cover is None
    assert "COURSE_COVER_RESOLVED_ASSET_NOT_READY" in caplog.text


async def test_attach_course_cover_read_contract_removes_legacy_fields_and_attaches_cover(
    monkeypatch,
):
    _install_storage(monkeypatch)

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        assert course_id == COURSE_ID
        assert media_asset_id == MEDIA_ID
        return _runtime_row()

    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    row = _course()
    row["cover_url"] = LEGACY_URL
    row["signed_cover_url"] = "https://signed.local/legacy"
    row["signed_cover_url_expires_at"] = "2026-04-10T00:00:00+00:00"

    await courses_service.attach_course_cover_read_contract(row)

    assert "cover_url" not in row
    assert "signed_cover_url" not in row
    assert "signed_cover_url_expires_at" not in row
    assert row["cover"] == _resolved_cover_payload()


async def test_attach_course_cover_read_contract_drops_cover_when_no_cover_media_id():
    row = _course(cover_media_id=None)
    row["cover_url"] = LEGACY_URL
    row["cover"] = {"media_id": None, "state": "placeholder", "resolved_url": None}

    await courses_service.attach_course_cover_read_contract(row)

    assert "cover_url" not in row
    assert row["cover"] is None


async def test_fetch_course_includes_cover_when_cover_media_id_resolves(monkeypatch):
    _install_storage(monkeypatch)

    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return _course()

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        assert course_id == COURSE_ID
        assert media_asset_id == MEDIA_ID
        return _runtime_row()

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    course = await courses_service.fetch_course(course_id=COURSE_ID)

    assert course is not None
    assert "cover_url" not in course
    assert course["cover"] == _resolved_cover_payload()


async def test_list_public_courses_includes_cover_when_cover_media_id_resolves(monkeypatch):
    _install_storage(monkeypatch)

    async def fake_list_public_courses(**kwargs):
        return [_course()]

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row()

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_public_course_discovery",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    courses = await courses_service.list_public_courses()

    assert len(courses) == 1
    assert "cover_url" not in courses[0]
    assert courses[0]["cover"] == _resolved_cover_payload()


async def test_courses_list_response_includes_cover_when_present(async_client, monkeypatch):
    async def fake_list_public_courses(**kwargs):
        return [
            {
                **_course(),
                "cover": _resolved_cover_payload(),
            }
        ]

    async def fake_attach(rows):
        return None

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "attach_course_cover_read_contract",
        fake_attach,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["items"][0]["cover"] == _resolved_cover_payload()
    assert "cover_url" not in body["items"][0]


async def test_courses_list_response_returns_null_cover_for_invalid_cover(
    async_client,
    monkeypatch,
):
    async def fake_list_public_courses(**kwargs):
        return [{**_course(), "cover": None}]

    async def fake_attach(rows):
        return None

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "attach_course_cover_read_contract",
        fake_attach,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["items"][0]["cover_media_id"] == MEDIA_ID
    assert body["items"][0]["cover"] is None
    assert "resolved_cover_url" not in body["items"][0]
    assert "cover_url" not in body["items"][0]


async def test_courses_list_exposes_premium_cover_without_purchase(
    async_client,
    monkeypatch,
):
    async def fake_list_public_courses(**kwargs):
        return [
            {
                **_course(),
                "price_amount_cents": 9900,
                "cover": _resolved_cover_payload(),
            }
        ]

    async def fake_attach(rows):
        return None

    monkeypatch.setattr(
        courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "attach_course_cover_read_contract",
        fake_attach,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["items"][0]["price_amount_cents"] == 9900
    assert body["items"][0]["cover"] == _resolved_cover_payload()


async def test_course_detail_by_slug_uses_canonical_cover_contract(
    async_client,
    monkeypatch,
):
    _install_storage(monkeypatch)

    async def fake_fetch_detail_rows(*, course_id: str | None = None, slug: str | None = None):
        assert course_id is None
        assert slug == "course-1"
        return [_detail_row()]

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        assert course_id == COURSE_ID
        assert media_asset_id == MEDIA_ID
        return _runtime_row()

    monkeypatch.setattr(
        courses_service,
        "fetch_public_course_detail_rows",
        fake_fetch_detail_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    response = await async_client.get("/courses/by-slug/course-1")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["course"]["cover_media_id"] == MEDIA_ID
    assert body["course"]["cover"] == _resolved_cover_payload()
    assert "resolved_cover_url" not in body["course"]
    assert "cover_url" not in body["course"]


async def test_course_detail_by_id_returns_null_cover_for_non_ready_media(
    async_client,
    monkeypatch,
):
    async def fake_fetch_detail_rows(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return [_detail_row()]

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row(state="processing")

    monkeypatch.setattr(
        courses_service,
        "fetch_public_course_detail_rows",
        fake_fetch_detail_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    response = await async_client.get(f"/courses/{COURSE_ID}")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["course"]["cover_media_id"] == MEDIA_ID
    assert body["course"]["cover"] is None
    assert "resolved_cover_url" not in body["course"]


async def test_premium_course_detail_exposes_cover_without_purchase_gate(
    async_client,
    monkeypatch,
):
    _install_storage(monkeypatch)

    async def fake_fetch_detail_rows(*, course_id: str | None = None, slug: str | None = None):
        assert slug == "premium-course"
        return [_detail_row(price_amount_cents=9900)]

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row()

    async def fail_access_lookup(*args, **kwargs):
        raise AssertionError("public course detail cover must not require purchase state")

    monkeypatch.setattr(
        courses_service,
        "fetch_public_course_detail_rows",
        fake_fetch_detail_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "read_canonical_course_state",
        fail_access_lookup,
        raising=True,
    )

    response = await async_client.get("/courses/by-slug/premium-course")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["course"]["price_amount_cents"] == 9900
    assert body["course"]["cover"] == _resolved_cover_payload()


async def test_courses_me_uses_same_canonical_cover_contract(monkeypatch):
    _install_storage(monkeypatch)

    async def fake_list_my_courses(user_id: str):
        assert user_id == TEACHER_ID
        return [_course()]

    async def fake_get_runtime_media(*, course_id: str, media_asset_id: str):
        return _runtime_row()

    monkeypatch.setattr(
        courses_service,
        "list_my_courses",
        fake_list_my_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.runtime_media_repo,
        "get_course_cover_runtime_media",
        fake_get_runtime_media,
        raising=True,
    )

    response = await courses_routes.my_courses({"id": TEACHER_ID})
    body = response.model_dump(mode="json")
    assert body["items"][0]["cover_media_id"] == MEDIA_ID
    assert body["items"][0]["cover"] == _resolved_cover_payload()
    assert "resolved_cover_url" not in body["items"][0]


async def test_landing_popular_courses_uses_canonical_cover_shape(
    monkeypatch,
):
    async def fake_list_popular_courses():
        return [_landing_course(cover=_resolved_cover_payload())]

    monkeypatch.setattr(
        landing_routes.models,
        "list_popular_courses",
        fake_list_popular_courses,
        raising=True,
    )

    response = await landing_routes.popular_courses()
    body = response.model_dump(mode="json")
    assert body["items"][0]["cover_media_id"] == MEDIA_ID
    assert body["items"][0]["cover"] == _resolved_cover_payload()
    assert "resolved_cover_url" not in body["items"][0]
    assert "cover_url" not in body["items"][0]


async def test_landing_intro_courses_returns_null_cover_without_placeholder(
    monkeypatch,
):
    async def fake_list_intro_courses():
        return [_landing_course(cover=None)]

    monkeypatch.setattr(
        landing_routes.models,
        "list_intro_courses",
        fake_list_intro_courses,
        raising=True,
    )

    response = await landing_routes.intro_courses()
    body = response.model_dump(mode="json")
    assert body["items"][0]["cover_media_id"] == MEDIA_ID
    assert body["items"][0]["cover"] is None
    assert "resolved_cover_url" not in body["items"][0]


async def test_landing_course_schema_rejects_legacy_parallel_cover_shape():
    with pytest.raises(ValidationError):
        schemas.Course(
            **{
                **_landing_course(cover=_resolved_cover_payload()),
                "resolved_cover_url": LEGACY_URL,
            }
        )


async def test_course_schema_rejects_legacy_parallel_cover_shape():
    with pytest.raises(ValidationError):
        schemas.Course(
            **{
                **_course(),
                "cover": _resolved_cover_payload(),
                "resolved_cover_url": LEGACY_URL,
            }
        )


@pytest.mark.parametrize(
    "cover",
    [
        {"media_id": MEDIA_ID, "state": "uploaded", "resolved_url": LEGACY_URL},
        {"media_id": MEDIA_ID, "state": "ready", "resolved_url": None},
        {"media_id": MEDIA_ID, "state": "ready", "resolved_url": "   "},
        {
            "media_id": MEDIA_ID,
            "state": "ready",
            "resolved_url": LEGACY_URL,
            "playback_object_path": DERIVED_PATH,
        },
    ],
)
async def test_course_schema_rejects_non_canonical_cover_objects(cover):
    with pytest.raises(ValidationError):
        schemas.Course(**{**_course(), "cover": cover})


async def test_course_route_response_rejects_legacy_fields_before_filtering():
    with pytest.raises(ValueError, match="legacy course cover public fields"):
        courses_routes._course_response(
            {
                **_course(),
                "cover": _resolved_cover_payload(),
                "resolved_cover_url": LEGACY_URL,
            }
        )


async def test_landing_routes_are_mounted_in_canonical_app():
    app_paths = {route.path for route in app.routes}
    landing_router_paths = {route.path for route in landing_routes.router.routes}

    assert "/landing/intro-courses" in landing_router_paths
    assert "/landing/popular-courses" in landing_router_paths
    assert "/landing/intro-courses" in app_paths
    assert "/landing/popular-courses" in app_paths


async def test_studio_courses_list_response_uses_canonical_cover_shape(
    async_client,
    monkeypatch,
):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": TEACHER_ID}

    async def fake_list_courses(**kwargs):
        assert kwargs == {"teacher_id": TEACHER_ID}
        return [{**_course(), "cover": _resolved_cover_payload()}]

    async def fake_apply_course_read_contract(courses):
        return None

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
    assert body["items"][0]["cover"] == _resolved_cover_payload()
    assert "cover_url" not in body["items"][0]


async def test_studio_course_detail_response_uses_canonical_cover_shape(
    async_client,
    monkeypatch,
):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": TEACHER_ID}

    async def fake_get_course_for_teacher_or_404(course_id: str, teacher_id: str):
        assert course_id == COURSE_ID
        assert teacher_id == TEACHER_ID
        return {**_course(), "cover": _resolved_cover_payload()}

    async def fake_apply_course_read_contract(courses):
        return None

    monkeypatch.setattr(
        studio_routes.studio_authority,
        "get_course_for_teacher_or_404",
        fake_get_course_for_teacher_or_404,
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
    assert body["cover"] == _resolved_cover_payload()
    assert "cover_url" not in body


async def test_studio_course_create_rejects_cover_url_payload(async_client):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": TEACHER_ID}

    try:
        response = await async_client.post(
            "/studio/courses",
            json={
                "title": "Course 1",
                "slug": "course-1",
                "course_group_id": COURSE_GROUP_ID,
                "group_position": 0,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
                "cover_url": LEGACY_URL,
            },
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422, response.text


async def test_studio_course_update_rejects_cover_url_payload(async_client):
    app.dependency_overrides[permissions.require_teacher] = lambda: {"id": TEACHER_ID}

    try:
        response = await async_client.patch(
            f"/studio/courses/{COURSE_ID}",
            json={"cover_url": LEGACY_URL},
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 422, response.text


async def test_create_course_rejects_legacy_cover_url_runtime_write():
    with pytest.raises(ValueError, match="cover_url is deprecated"):
        await courses_service.create_course(
            {
                "title": "Course 1",
                "slug": "course-1",
                "course_group_id": COURSE_GROUP_ID,
                "group_position": 0,
                "price_amount_cents": None,
                "drip_enabled": False,
                "drip_interval_days": None,
                "cover_url": LEGACY_URL,
            },
            teacher_id=TEACHER_ID,
        )


async def test_update_course_rejects_legacy_cover_url_runtime_write():
    with pytest.raises(ValueError, match="cover_url is deprecated"):
        await courses_service.update_course(
            COURSE_ID,
            {"cover_url": LEGACY_URL},
            teacher_id=TEACHER_ID,
        )


async def test_course_cover_runtime_sources_do_not_reintroduce_legacy_url_fields():
    root = Path(__file__).resolve().parents[1]
    source = (root / "app/services/courses_service.py").read_text(encoding="utf-8")

    assert "_COURSE_COVER_FORBIDDEN_PUBLIC_FIELDS" in source
    assert "strip_legacy_course_cover_output_fields(row)" in source
    assert "reject_legacy_course_cover_output_fields(course)" in (
        root / "app/routes/courses.py"
    ).read_text(encoding="utf-8")
    assert "reject_legacy_course_cover_output_fields(course)" in (
        root / "app/services/courses_read_service.py"
    ).read_text(encoding="utf-8")


async def test_active_backend_read_sources_do_not_reintroduce_legacy_cover_shapes():
    root = Path(__file__).resolve().parents[1]
    active_sources = [
        root / "app/routes/courses.py",
        root / "app/routes/landing.py",
        root / "app/services/courses_read_service.py",
        root / "app/repositories/runtime_media.py",
        root / "app/models.py",
        root / "app/schemas/__init__.py",
    ]

    for path in active_sources:
        source = path.read_text(encoding="utf-8")
        assert "resolved_cover_url" not in source
        assert "resolvedCoverUrl" not in source
        assert "_course_cover_placeholder" not in source
        assert "cover_url" not in source
