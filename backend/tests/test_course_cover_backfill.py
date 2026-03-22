from __future__ import annotations

import pytest

from app.services import course_cover_backfill as backfill

pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "course-1"
OWNER_ID = "owner-1"
MEDIA_ID = "11111111-1111-1111-1111-111111111111"
LEGACY_PATH = "courses/course-1/cover.jpg"
LEGACY_URL = f"/api/files/public-media/{LEGACY_PATH}"


def _course(
    *,
    cover_media_id: str | None = None,
    cover_url: str | None = LEGACY_URL,
) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "cover_url": cover_url,
        "cover_media_id": cover_media_id,
        "created_by": OWNER_ID,
    }


def _asset(
    *,
    media_id: str = MEDIA_ID,
    path: str = LEGACY_PATH,
    state: str = "ready",
    course_id: str = COURSE_ID,
) -> dict:
    return {
        "id": media_id,
        "owner_id": OWNER_ID,
        "course_id": course_id,
        "lesson_id": None,
        "media_type": "image",
        "purpose": "course_cover",
        "ingest_format": "jpg",
        "original_object_path": path,
        "original_content_type": "image/jpeg",
        "original_filename": "cover.jpg",
        "original_size_bytes": 1234,
        "storage_bucket": "public-media",
        "streaming_object_path": path,
        "streaming_storage_bucket": "public-media",
        "streaming_format": "jpg",
        "duration_seconds": None,
        "codec": "jpeg",
        "state": state,
        "error_message": None,
        "processing_attempts": 0,
        "processing_locked_at": None,
        "next_retry_at": None,
        "created_at": None,
        "updated_at": None,
    }


def _storage_detail(
    path: str,
    *,
    content_type: str = "image/jpeg",
    public: bool = True,
    size_bytes: int = 4321,
) -> dict:
    return {
        "bucket": "public-media",
        "storage_path": path,
        "exists": True,
        "content_type": content_type,
        "size_bytes": size_bytes,
        "public": public,
        "metadata": {},
        "created_at": None,
        "updated_at": None,
    }


async def test_classify_already_control_plane(monkeypatch):
    async def fake_get_media_assets(media_ids):
        return {MEDIA_ID: _asset()}

    async def fake_fetch_storage_object_details(pairs):
        return {
            ("public-media", LEGACY_PATH): _storage_detail(LEGACY_PATH),
        }, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        raise AssertionError("reusable asset lookup should not run for already_control_plane")

    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )

    items = await backfill.classify_course_cover_batch([_course(cover_media_id=MEDIA_ID)])
    assert len(items) == 1
    item = items[0]
    assert item.classification == backfill.CLASS_ALREADY_CONTROL_PLANE
    assert item.reason == "control_plane_ready"


async def test_classify_legacy_migratable_with_reuse(monkeypatch):
    async def fake_get_media_assets(media_ids):
        assert list(media_ids) == []
        return {}

    async def fake_fetch_storage_object_details(pairs):
        return {
            ("public-media", LEGACY_PATH): _storage_detail(LEGACY_PATH),
        }, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        assert course_id == COURSE_ID
        assert storage_bucket == "public-media"
        assert storage_path == LEGACY_PATH
        return [_asset()]

    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )

    items = await backfill.classify_course_cover_batch([_course()])
    item = items[0]
    assert item.classification == backfill.CLASS_LEGACY_MIGRATABLE
    assert item.planned_action == "reuse_asset"
    assert item.planned_media_id == MEDIA_ID
    assert item.reusable_asset_ids == [MEDIA_ID]


async def test_classify_noncanonical_public_lesson_cover(monkeypatch):
    noncanonical_path = "lessons/lesson-1/images/demo.png"
    noncanonical_url = f"/api/files/public-media/{noncanonical_path}"

    async def fake_get_media_assets(media_ids):
        return {}

    async def fake_fetch_storage_object_details(pairs):
        return {
            ("public-media", noncanonical_path): _storage_detail(
                noncanonical_path,
                content_type="image/png",
            ),
        }, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        raise AssertionError("reusable asset lookup should not run for noncanonical covers")

    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )

    items = await backfill.classify_course_cover_batch([_course(cover_url=noncanonical_url)])
    item = items[0]
    assert item.classification == backfill.CLASS_LEGACY_MIGRATABLE
    assert item.reason == "legacy_lesson_cover_requires_copy"
    assert item.planned_action == "create_asset"


async def test_classify_legacy_unverifiable_for_non_image(monkeypatch):
    async def fake_get_media_assets(media_ids):
        return {}

    async def fake_fetch_storage_object_details(pairs):
        return {
            ("public-media", LEGACY_PATH): _storage_detail(
                LEGACY_PATH,
                content_type="application/pdf",
            ),
        }, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        raise AssertionError("reusable asset lookup should not run for unverifiable covers")

    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )

    items = await backfill.classify_course_cover_batch([_course()])
    item = items[0]
    assert item.classification == backfill.CLASS_LEGACY_UNVERIFIABLE
    assert item.reason == "storage_object_not_image"


async def test_classify_hybrid_broken_when_asset_missing(monkeypatch):
    async def fake_get_media_assets(media_ids):
        return {}

    async def fake_fetch_storage_object_details(pairs):
        return {
            ("public-media", LEGACY_PATH): _storage_detail(LEGACY_PATH),
        }, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        raise AssertionError("reusable asset lookup should not run for hybrid_broken")

    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )

    items = await backfill.classify_course_cover_batch([_course(cover_media_id=MEDIA_ID)])
    item = items[0]
    assert item.classification == backfill.CLASS_HYBRID_BROKEN
    assert item.reason == "asset_missing"


async def test_apply_mode_is_idempotent_for_create_path(monkeypatch):
    course = _course()
    created_assets: dict[str, dict] = {}
    created_ids: list[str] = []

    async def fake_list_courses_with_cover_url(*, limit=100, after_id=None):
        if after_id is not None:
            return []
        return [course]

    async def fake_get_media_assets(media_ids):
        return {
            media_id: created_assets[media_id]
            for media_id in media_ids
            if media_id in created_assets
        }

    async def fake_fetch_storage_object_details(pairs):
        pairs = list(pairs)
        details = {
            ("public-media", LEGACY_PATH): _storage_detail(LEGACY_PATH),
        }
        for media_id, asset in created_assets.items():
            path = str(asset.get("streaming_object_path") or "")
            if path:
                details[("public-media", path)] = _storage_detail(path)
        return details, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        return [
            asset
            for asset in created_assets.values()
            if asset.get("course_id") == course_id
            and asset.get("streaming_storage_bucket") == storage_bucket
            and asset.get("streaming_object_path") == storage_path
        ]

    async def fake_set_course_cover_media_id_if_unset(*, course_id, cover_media_id):
        if course_id != COURSE_ID:
            return False
        if course.get("cover_media_id"):
            return False
        course["cover_media_id"] = cover_media_id
        return True

    async def fake_create_ready_public_course_cover_asset(
        *,
        owner_id,
        course_id,
        storage_bucket,
        storage_path,
        content_type,
        filename,
        size_bytes,
        ingest_format,
        codec=None,
    ):
        media_id = f"created-{len(created_assets) + 1}"
        asset = _asset(media_id=media_id, path=storage_path, course_id=course_id)
        asset["owner_id"] = owner_id
        asset["original_content_type"] = content_type
        asset["original_filename"] = filename
        asset["original_size_bytes"] = size_bytes
        asset["ingest_format"] = ingest_format
        asset["streaming_format"] = ingest_format
        asset["codec"] = codec
        created_assets[media_id] = asset
        created_ids.append(media_id)
        return asset

    monkeypatch.setattr(backfill.courses_repo, "list_courses_with_cover_url", fake_list_courses_with_cover_url, raising=True)
    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )
    monkeypatch.setattr(
        backfill.courses_repo,
        "set_course_cover_media_id_if_unset",
        fake_set_course_cover_media_id_if_unset,
        raising=True,
    )
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "create_ready_public_course_cover_asset",
        fake_create_ready_public_course_cover_asset,
        raising=True,
    )

    first = await backfill.run_course_cover_backfill(apply=True, batch_size=10)
    assert first.migrated_courses == 1
    assert first.created_assets == 1
    assert created_ids == ["created-1"]
    assert course["cover_media_id"] == "created-1"

    second = await backfill.run_course_cover_backfill(apply=True, batch_size=10)
    assert second.class_counts[backfill.CLASS_ALREADY_CONTROL_PLANE] == 1
    assert second.migrated_courses == 0
    assert second.created_assets == 0
    assert created_ids == ["created-1"]


async def test_apply_mode_copies_lesson_cover_before_creating_asset(monkeypatch):
    legacy_path = "lessons/lesson-1/images/demo.png"
    legacy_url = f"/api/files/public-media/{legacy_path}"
    course = _course(cover_url=legacy_url)
    created_assets: dict[str, dict] = {}
    copy_calls: list[dict[str, str | None]] = []

    async def fake_list_courses_with_cover_url(*, limit=100, after_id=None):
        if after_id is not None:
            return []
        return [course]

    async def fake_get_media_assets(media_ids):
        return {
            media_id: created_assets[media_id]
            for media_id in media_ids
            if media_id in created_assets
        }

    async def fake_fetch_storage_object_details(pairs):
        details = {
            ("public-media", legacy_path): _storage_detail(
                legacy_path,
                content_type="image/png",
            ),
        }
        for asset in created_assets.values():
            path = str(asset.get("streaming_object_path") or "")
            if path:
                details[("public-media", path)] = _storage_detail(
                    path,
                    content_type="image/png",
                )
        return details, True

    async def fake_list_ready_course_cover_assets_for_object(*, course_id, storage_bucket, storage_path):
        raise AssertionError("lesson cover backfill should copy instead of reusing source path")

    async def fake_set_course_cover_media_id_if_unset(*, course_id, cover_media_id):
        if course.get("cover_media_id"):
            return False
        course["cover_media_id"] = cover_media_id
        return True

    async def fake_copy_object(
        *,
        source_bucket,
        source_path,
        destination_bucket,
        destination_path,
        content_type=None,
        cache_seconds=None,
    ):
        copy_calls.append(
            {
                "source_bucket": source_bucket,
                "source_path": source_path,
                "destination_bucket": destination_bucket,
                "destination_path": destination_path,
                "content_type": content_type,
            }
        )

    async def fake_create_ready_public_course_cover_asset(
        *,
        owner_id,
        course_id,
        storage_bucket,
        storage_path,
        content_type,
        filename,
        size_bytes,
        ingest_format,
        codec=None,
    ):
        media_id = f"created-{len(created_assets) + 1}"
        asset = _asset(media_id=media_id, path=storage_path, course_id=course_id)
        asset["owner_id"] = owner_id
        asset["original_content_type"] = content_type
        asset["original_filename"] = filename
        asset["original_size_bytes"] = size_bytes
        asset["ingest_format"] = ingest_format
        asset["streaming_format"] = ingest_format
        asset["codec"] = codec
        created_assets[media_id] = asset
        return asset

    monkeypatch.setattr(backfill.courses_repo, "list_courses_with_cover_url", fake_list_courses_with_cover_url, raising=True)
    monkeypatch.setattr(backfill.media_assets_repo, "get_media_assets", fake_get_media_assets, raising=True)
    monkeypatch.setattr(backfill.storage_objects, "fetch_storage_object_details", fake_fetch_storage_object_details, raising=True)
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "list_ready_course_cover_assets_for_object",
        fake_list_ready_course_cover_assets_for_object,
        raising=True,
    )
    monkeypatch.setattr(
        backfill.courses_repo,
        "set_course_cover_media_id_if_unset",
        fake_set_course_cover_media_id_if_unset,
        raising=True,
    )
    monkeypatch.setattr(
        backfill.storage_service,
        "copy_object",
        fake_copy_object,
        raising=True,
    )
    monkeypatch.setattr(
        backfill.media_assets_repo,
        "create_ready_public_course_cover_asset",
        fake_create_ready_public_course_cover_asset,
        raising=True,
    )

    report = await backfill.run_course_cover_backfill(apply=True, batch_size=10)
    assert report.migrated_courses == 1
    assert report.created_assets == 1
    assert report.errors == 0
    assert len(copy_calls) == 1
    copied = copy_calls[0]
    assert copied["source_bucket"] == "public-media"
    assert copied["source_path"] == legacy_path
    assert copied["destination_bucket"] == "public-media"
    assert copied["destination_path"] is not None
    assert str(copied["destination_path"]).startswith(
        f"media/derived/cover/courses/{COURSE_ID}/"
    )
    assert course["cover_media_id"] == "created-1"
    created_asset = created_assets["created-1"]
    assert created_asset["original_object_path"] == copied["destination_path"]
    assert created_asset["original_object_path"] != legacy_path
