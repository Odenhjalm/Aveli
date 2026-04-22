from datetime import datetime, timezone

import pytest

from app import schemas
from app.routes import studio

pytestmark = pytest.mark.anyio("asyncio")

LESSON_ID = "22222222-2222-2222-2222-222222222222"
LESSON_MEDIA_ID = "11111111-1111-1111-1111-111111111111"
LESSON_MEDIA_ID_2 = "11111111-1111-1111-1111-111111111112"
MEDIA_ASSET_ID = "33333333-3333-3333-3333-333333333333"
TEACHER_ID = "44444444-4444-4444-4444-444444444444"
FORBIDDEN_MEDIA_FIELDS = {
    "upload_url",
    "storage_path",
    "object_path",
    "download_url",
    "signed_url",
    "provider_url",
}


def _row(*, state: str = "ready") -> dict[str, object]:
    return {
        "lesson_media_id": LESSON_MEDIA_ID,
        "lesson_id": LESSON_ID,
        "media_asset_id": MEDIA_ASSET_ID,
        "position": 1,
        "media_type": "document",
        "state": state,
    }


def _payload_keys(value: object) -> set[str]:
    keys: set[str] = set()
    if isinstance(value, dict):
        keys.update(str(key) for key in value)
        for nested in value.values():
            keys.update(_payload_keys(nested))
    elif isinstance(value, list):
        for nested in value:
            keys.update(_payload_keys(nested))
    return keys


async def test_studio_lesson_media_item_ready_composes_canonical_media(monkeypatch):
    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        assert lesson_media_id == "11111111-1111-1111-1111-111111111111"
        assert user_id == "teacher-1"
        return {"resolved_url": "https://cdn.test/lesson-media/guide.pdf"}

    monkeypatch.setattr(
        studio.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    item = await studio._studio_lesson_media_item_from_row(
        row=_row(state="ready"),
        user_id="teacher-1",
    )

    assert str(item.lesson_media_id) == "11111111-1111-1111-1111-111111111111"
    assert item.media is not None
    assert str(item.media.media_id) == "33333333-3333-3333-3333-333333333333"
    assert item.media.state == "ready"
    assert item.media.resolved_url == "https://cdn.test/lesson-media/guide.pdf"
    payload = item.model_dump(mode="json")
    assert _payload_keys(payload).isdisjoint(FORBIDDEN_MEDIA_FIELDS)


async def test_studio_lesson_media_item_non_ready_keeps_media_object_without_url(
    monkeypatch,
):
    called = False

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        nonlocal called
        called = True
        return {"resolved_url": "https://cdn.test/should-not-run"}

    monkeypatch.setattr(
        studio.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    item = await studio._studio_lesson_media_item_from_row(
        row=_row(state="uploaded"),
        user_id="teacher-1",
    )

    assert item.media is not None
    assert item.media.state == "uploaded"
    assert item.media.resolved_url is None
    assert called is False


async def test_studio_lesson_media_item_ready_returns_null_media_when_unresolvable(
    monkeypatch,
):
    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        raise studio.HTTPException(status_code=503, detail="unavailable")

    monkeypatch.setattr(
        studio.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    item = await studio._studio_lesson_media_item_from_row(
        row=_row(state="ready"),
        user_id="teacher-1",
    )

    assert item.media is None


async def test_studio_preview_lesson_media_preserves_canonical_row_identity(
    monkeypatch,
):
    preview_expires_at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    resolver_calls: list[dict[str, str]] = []

    async def fake_require_studio_lesson(lesson_id: str):
        assert lesson_id == LESSON_ID
        return {"id": LESSON_ID}

    async def fake_get_lesson_media_for_studio(
        lesson_id: str,
        lesson_media_id: str,
    ):
        assert lesson_id == LESSON_ID
        assert lesson_media_id == LESSON_MEDIA_ID
        return {
            "lesson_media_id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
            "media_type": "video",
            "state": "ready",
            "preview_ready": True,
        }

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        resolver_calls.append(
            {"lesson_media_id": lesson_media_id, "user_id": user_id}
        )
        return {
            "resolved_url": "https://cdn.test/preview.mp4",
            "expires_at": preview_expires_at,
        }

    monkeypatch.setattr(
        studio,
        "_require_studio_lesson",
        fake_require_studio_lesson,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "get_lesson_media_for_studio",
        fake_get_lesson_media_for_studio,
        raising=True,
    )
    monkeypatch.setattr(
        studio.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    response = await studio.studio_preview_lesson_media(
        lesson_id=studio.UUID(LESSON_ID),
        lesson_media_id=studio.UUID(LESSON_MEDIA_ID),
        current={"id": TEACHER_ID},
    )

    assert resolver_calls == [
        {"lesson_media_id": LESSON_MEDIA_ID, "user_id": TEACHER_ID}
    ]
    payload = response.model_dump(mode="json")
    assert payload == {
        "lesson_media_id": LESSON_MEDIA_ID,
        "preview_url": "https://cdn.test/preview.mp4",
        "expires_at": "2026-01-01T00:00:00Z",
    }
    assert _payload_keys(payload).isdisjoint(
        FORBIDDEN_MEDIA_FIELDS | {"storage_bucket"}
    )


async def test_legacy_studio_lesson_media_listing_is_inert():
    with pytest.raises(studio.HTTPException) as exc_info:
        await studio.list_lesson_media(
            request=object(),
            lesson_id=studio.UUID(LESSON_ID),
            current={"id": TEACHER_ID},
        )

    assert exc_info.value.status_code == 410


async def test_legacy_api_lesson_media_listing_is_inert():
    with pytest.raises(studio.HTTPException) as exc_info:
        await studio.studio_list_lesson_media(
            lesson_id=studio.UUID(LESSON_ID),
            current={"id": TEACHER_ID},
        )

    assert exc_info.value.status_code == 410


async def test_studio_preview_lesson_media_fails_closed_without_row_identity(
    monkeypatch,
):
    resolver_called = False

    async def fake_require_studio_lesson(lesson_id: str):
        assert lesson_id == LESSON_ID
        return {"id": LESSON_ID}

    async def fake_get_lesson_media_for_studio(
        lesson_id: str,
        lesson_media_id: str,
    ):
        assert lesson_id == LESSON_ID
        assert lesson_media_id == LESSON_MEDIA_ID
        return {
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
            "media_type": "video",
            "state": "ready",
            "preview_ready": True,
        }

    async def fake_resolve_lesson_media_playback(*, lesson_media_id: str, user_id: str):
        nonlocal resolver_called
        resolver_called = True
        return {
            "resolved_url": "https://cdn.test/preview.mp4",
            "expires_at": datetime(2026, 1, 1, tzinfo=timezone.utc),
        }

    monkeypatch.setattr(
        studio,
        "_require_studio_lesson",
        fake_require_studio_lesson,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "get_lesson_media_for_studio",
        fake_get_lesson_media_for_studio,
        raising=True,
    )
    monkeypatch.setattr(
        studio.lesson_playback_service,
        "resolve_lesson_media_playback",
        fake_resolve_lesson_media_playback,
        raising=True,
    )

    with pytest.raises(studio.HTTPException) as exc_info:
        await studio.studio_preview_lesson_media(
            lesson_id=studio.UUID(LESSON_ID),
            lesson_media_id=studio.UUID(LESSON_MEDIA_ID),
            current={"id": TEACHER_ID},
        )

    assert exc_info.value.status_code == 503
    assert resolver_called is False


async def test_canonical_upload_url_creates_asset_without_placement(monkeypatch):
    upload_calls: list[dict[str, object]] = []
    asset_calls: list[dict[str, object]] = []

    async def fake_authoring_context(*, lesson_id: str, current):
        assert lesson_id == LESSON_ID
        assert str(current["id"]) == TEACHER_ID
        return "55555555-5555-5555-5555-555555555555"

    class FakeStorageClient:
        async def create_upload_url(
            self,
            path,
            *,
            content_type=None,
            upsert=False,
            cache_seconds=None,
        ):
            upload_calls.append(
                {
                    "path": path,
                    "content_type": content_type,
                    "upsert": upsert,
                    "cache_seconds": cache_seconds,
                }
            )
            return studio.storage_service.PresignedUpload(
                url=f"https://storage.test/{path}",
                headers={"content-type": content_type or ""},
                path=path,
                expires_in=300,
            )

    async def fake_create_media_asset(**kwargs):
        asset_calls.append(dict(kwargs))
        return {"id": MEDIA_ASSET_ID, "state": "pending_upload"}

    async def fail_create_lesson_media(**kwargs):
        raise AssertionError("upload-url must not create lesson_media")

    monkeypatch.setattr(
        studio,
        "_require_canonical_lesson_media_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio.storage_service,
        "storage_service",
        FakeStorageClient(),
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "create_media_asset",
        fake_create_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "create_lesson_media",
        fail_create_lesson_media,
        raising=True,
    )

    response = await studio.canonical_issue_lesson_media_upload_url(
        lesson_id=studio.UUID(LESSON_ID),
        payload=schemas.CanonicalLessonMediaUploadUrlRequest(
            media_type="document",
            filename="guide.pdf",
            mime_type="application/pdf",
            size_bytes=12,
        ),
        current={"id": TEACHER_ID},
    )

    assert str(response.media_asset_id) == MEDIA_ASSET_ID
    assert response.asset_state == "pending_upload"
    assert not hasattr(response, "lesson_media_id")
    assert _payload_keys(response.model_dump(mode="json")).isdisjoint(
        FORBIDDEN_MEDIA_FIELDS | {"headers", "storage_bucket"}
    )
    assert len(asset_calls) == 1
    assert asset_calls[0]["purpose"] == "lesson_media"
    assert asset_calls[0]["state"] == "pending_upload"
    assert asset_calls[0]["original_filename"] == "guide.pdf"
    assert asset_calls[0]["lesson_id"] == LESSON_ID
    assert asset_calls[0]["course_id"] == "55555555-5555-5555-5555-555555555555"
    assert upload_calls == []


def test_canonical_lesson_media_scope_prefers_metadata_over_path() -> None:
    media_type, lesson_id, course_id = studio._canonical_lesson_media_asset_scope(
        {
            "media_type": "video",
            "purpose": "lesson_media",
            "lesson_id": LESSON_ID,
            "course_id": "55555555-5555-5555-5555-555555555555",
            "original_object_path": "legacy/incorrect/path.mp4",
        }
    )

    assert media_type == "video"
    assert lesson_id == LESSON_ID
    assert course_id == "55555555-5555-5555-5555-555555555555"


async def test_canonical_upload_completion_does_not_attach(monkeypatch):
    completed: list[str] = []

    async def fake_authorize_media_asset(**kwargs):
        assert kwargs["media_asset_id"] == MEDIA_ASSET_ID
        return {"id": MEDIA_ASSET_ID, "state": "pending_upload"}

    async def fake_mark_uploaded(*, media_id: str):
        completed.append(media_id)
        return {"id": media_id, "state": "uploaded"}

    async def fake_assert_storage_write(media_asset):
        assert media_asset["id"] == MEDIA_ASSET_ID

    async def fail_create_lesson_media(**kwargs):
        raise AssertionError("upload-completion must not attach lesson_media")

    monkeypatch.setattr(
        studio,
        "_authorize_canonical_lesson_media_asset",
        fake_authorize_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "mark_lesson_media_pipeline_asset_uploaded",
        fake_mark_uploaded,
        raising=True,
    )
    monkeypatch.setattr(
        studio,
        "_assert_canonical_media_storage_write",
        fake_assert_storage_write,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "create_lesson_media",
        fail_create_lesson_media,
        raising=True,
    )

    response = await studio.canonical_complete_lesson_media_upload(
        media_asset_id=studio.UUID(MEDIA_ASSET_ID),
        payload=schemas.CanonicalMediaAssetUploadCompletionRequest(),
        current={"id": TEACHER_ID},
    )

    assert str(response.media_asset_id) == MEDIA_ASSET_ID
    assert response.asset_state == "uploaded"
    assert not hasattr(response, "lesson_media_id")
    assert completed == [MEDIA_ASSET_ID]


async def test_course_cover_upload_url_persists_metadata_without_exposing_storage(
    monkeypatch,
) -> None:
    created: dict[str, object] = {}
    course_id = "55555555-5555-5555-5555-555555555555"

    async def fake_authoring_context(*, course_id: str, current):
        assert str(current["id"]) == TEACHER_ID
        return course_id

    async def fake_create_media_asset(**kwargs):
        created.update(kwargs)
        return {"id": MEDIA_ASSET_ID, "state": "pending_upload"}

    monkeypatch.setattr(
        studio,
        "_require_canonical_course_cover_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "create_media_asset",
        fake_create_media_asset,
        raising=True,
    )

    response = await studio.canonical_issue_course_cover_upload_url(
        course_id=studio.UUID(course_id),
        payload=schemas.CanonicalCourseCoverUploadUrlRequest(
            filename="cover art.png",
            mime_type="image/png",
            size_bytes=12,
        ),
        current={"id": TEACHER_ID},
    )

    assert str(response.media_asset_id) == MEDIA_ASSET_ID
    assert response.upload_endpoint == f"/api/media-assets/{MEDIA_ASSET_ID}/upload-bytes"
    assert _payload_keys(response.model_dump(mode="json")).isdisjoint(
        FORBIDDEN_MEDIA_FIELDS | {"headers", "storage_bucket"}
    )
    assert created["purpose"] == "course_cover"
    assert created["original_filename"] == "cover art.png"
    assert created["course_id"] == course_id


async def test_home_player_upload_url_persists_owner_metadata_without_exposing_storage(
    monkeypatch,
) -> None:
    created: dict[str, object] = {}

    async def fake_create_media_asset(**kwargs):
        created.update(kwargs)
        return {"id": MEDIA_ASSET_ID, "state": "pending_upload"}

    monkeypatch.setattr(
        studio.media_assets_repo,
        "create_media_asset",
        fake_create_media_asset,
        raising=True,
    )

    response = await studio.canonical_issue_home_player_upload_url(
        payload=schemas.CanonicalHomePlayerMediaUploadUrlRequest(
            filename="focus mix.m4a",
            mime_type="audio/mp4",
            size_bytes=12,
        ),
        current={"id": TEACHER_ID},
    )

    assert str(response.media_asset_id) == MEDIA_ASSET_ID
    assert response.upload_endpoint == f"/api/media-assets/{MEDIA_ASSET_ID}/upload-bytes"
    assert _payload_keys(response.model_dump(mode="json")).isdisjoint(
        FORBIDDEN_MEDIA_FIELDS | {"headers", "storage_bucket"}
    )
    assert created["purpose"] == "home_player_audio"
    assert created["original_filename"] == "focus mix.m4a"
    assert created["owner_user_id"] == TEACHER_ID


async def test_canonical_placement_attaches_uploaded_asset_without_asset_creation(
    monkeypatch,
):
    placements: list[dict[str, object]] = []

    async def fake_authoring_context(*, lesson_id: str, current):
        assert lesson_id == LESSON_ID
        return "55555555-5555-5555-5555-555555555555"

    async def fake_authorize_media_asset(**kwargs):
        assert kwargs["media_asset_id"] == MEDIA_ASSET_ID
        assert kwargs["expected_lesson_id"] == LESSON_ID
        return {"id": MEDIA_ASSET_ID, "state": "uploaded"}

    async def fake_asset_is_linked(media_asset_id: str):
        assert media_asset_id == MEDIA_ASSET_ID
        return False

    async def fake_create_lesson_media(**kwargs):
        placements.append(dict(kwargs))
        return {
            "lesson_media_id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
            "media_type": "document",
            "state": "uploaded",
        }

    async def fail_create_media_asset(**kwargs):
        raise AssertionError("placement must not create media_assets")

    monkeypatch.setattr(
        studio,
        "_require_canonical_lesson_media_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio,
        "_authorize_canonical_lesson_media_asset",
        fake_authorize_media_asset,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "lesson_media_asset_is_linked",
        fake_asset_is_linked,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "create_lesson_media",
        fake_create_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "create_media_asset",
        fail_create_media_asset,
        raising=True,
    )

    response = await studio.canonical_create_lesson_media_placement(
        lesson_id=studio.UUID(LESSON_ID),
        payload=schemas.CanonicalLessonMediaPlacementCreate(
            media_asset_id=studio.UUID(MEDIA_ASSET_ID),
        ),
        current={"id": TEACHER_ID},
    )

    assert str(response.lesson_media_id) == LESSON_MEDIA_ID
    assert str(response.media_asset_id) == MEDIA_ASSET_ID
    assert response.asset_state == "uploaded"
    assert placements == [
        {"lesson_id": LESSON_ID, "media_asset_id": MEDIA_ASSET_ID}
    ]


async def test_canonical_placement_read_returns_backend_authored_media(monkeypatch):
    async def fake_get_lesson_media_by_id_for_studio(lesson_media_id: str):
        assert lesson_media_id == LESSON_MEDIA_ID
        return {
            "lesson_media_id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
            "media_type": "document",
            "state": "ready",
        }

    async def fake_authoring_context(*, lesson_id: str, current):
        assert lesson_id == LESSON_ID
        return "55555555-5555-5555-5555-555555555555"

    async def fake_compose_studio_media(**kwargs):
        assert kwargs["lesson_media_id"] == LESSON_MEDIA_ID
        assert kwargs["media_asset_id"] == MEDIA_ASSET_ID
        return schemas.ResolvedMedia(
            media_id=studio.UUID(MEDIA_ASSET_ID),
            state="ready",
            resolved_url="https://cdn.test/guide.pdf",
        )

    monkeypatch.setattr(
        studio.courses_repo,
        "get_lesson_media_by_id_for_studio",
        fake_get_lesson_media_by_id_for_studio,
        raising=True,
    )
    monkeypatch.setattr(
        studio,
        "_require_canonical_lesson_media_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio,
        "_compose_studio_media",
        fake_compose_studio_media,
        raising=True,
    )

    response = await studio.canonical_get_lesson_media_placement(
        lesson_media_id=studio.UUID(LESSON_MEDIA_ID),
        current={"id": TEACHER_ID},
    )

    payload = response.model_dump(mode="json")
    assert payload == {
        "lesson_media_id": LESSON_MEDIA_ID,
        "lesson_id": LESSON_ID,
        "media_asset_id": MEDIA_ASSET_ID,
        "position": 1,
        "media_type": "document",
        "asset_state": "ready",
        "media": {
            "media_id": MEDIA_ASSET_ID,
            "state": "ready",
            "resolved_url": "https://cdn.test/guide.pdf",
        },
    }
    assert "preview_ready" not in payload
    assert "original_name" not in payload


async def test_canonical_placement_reorder_updates_only_lesson_media_position(
    monkeypatch,
):
    reorder_calls: list[tuple[str, list[str]]] = []

    async def fake_authoring_context(*, lesson_id: str, current):
        assert lesson_id == LESSON_ID
        assert str(current["id"]) == TEACHER_ID
        return "55555555-5555-5555-5555-555555555555"

    async def fake_reorder_lesson_media(
        lesson_id: str,
        ordered_lesson_media_ids: list[str],
    ):
        reorder_calls.append((lesson_id, list(ordered_lesson_media_ids)))

    async def fail_delete_media_asset(*args, **kwargs):
        raise AssertionError("reorder must not delete media_assets")

    async def fail_lifecycle_request(*args, **kwargs):
        raise AssertionError("reorder must not request cleanup")

    monkeypatch.setattr(
        studio,
        "_require_canonical_lesson_media_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "reorder_lesson_media",
        fake_reorder_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "delete_media_asset",
        fail_delete_media_asset,
        raising=False,
    )
    monkeypatch.setattr(
        studio.media_cleanup,
        "request_lifecycle_evaluation",
        fail_lifecycle_request,
        raising=True,
    )

    response = await studio.canonical_reorder_lesson_media_placements(
        lesson_id=studio.UUID(LESSON_ID),
        payload=schemas.StudioLessonMediaReorder(
            lesson_media_ids=[
                studio.UUID(LESSON_MEDIA_ID_2),
                studio.UUID(LESSON_MEDIA_ID),
            ],
        ),
        current={"id": TEACHER_ID},
    )

    assert response == {"ok": True}
    assert reorder_calls == [
        (LESSON_ID, [LESSON_MEDIA_ID_2, LESSON_MEDIA_ID])
    ]


async def test_canonical_placement_delete_removes_only_target_link(
    monkeypatch,
):
    delete_calls: list[tuple[str, str]] = []
    lifecycle_calls: list[dict[str, object]] = []

    async def fake_get_lesson_media_by_id_for_studio(lesson_media_id: str):
        assert lesson_media_id == LESSON_MEDIA_ID
        return {
            "lesson_media_id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
            "media_type": "document",
            "state": "ready",
        }

    async def fake_authoring_context(*, lesson_id: str, current):
        assert lesson_id == LESSON_ID
        assert str(current["id"]) == TEACHER_ID
        return "55555555-5555-5555-5555-555555555555"

    async def fake_delete_lesson_media(lesson_id: str, lesson_media_id: str):
        delete_calls.append((lesson_id, lesson_media_id))
        return {
            "id": LESSON_MEDIA_ID,
            "lesson_id": LESSON_ID,
            "media_asset_id": MEDIA_ASSET_ID,
            "position": 1,
        }

    async def fake_lifecycle_request(**kwargs):
        lifecycle_calls.append(dict(kwargs))
        return 1

    async def fail_delete_media_asset(*args, **kwargs):
        raise AssertionError("placement delete must not delete media_assets")

    monkeypatch.setattr(
        studio.courses_repo,
        "get_lesson_media_by_id_for_studio",
        fake_get_lesson_media_by_id_for_studio,
        raising=True,
    )
    monkeypatch.setattr(
        studio,
        "_require_canonical_lesson_media_authoring_context",
        fake_authoring_context,
        raising=True,
    )
    monkeypatch.setattr(
        studio.courses_repo,
        "delete_lesson_media",
        fake_delete_lesson_media,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_cleanup,
        "request_lifecycle_evaluation",
        fake_lifecycle_request,
        raising=True,
    )
    monkeypatch.setattr(
        studio.media_assets_repo,
        "delete_media_asset",
        fail_delete_media_asset,
        raising=False,
    )

    response = await studio.canonical_delete_lesson_media_placement(
        lesson_media_id=studio.UUID(LESSON_MEDIA_ID),
        current={"id": TEACHER_ID},
    )

    assert response == {"deleted": True}
    assert delete_calls == [(LESSON_ID, LESSON_MEDIA_ID)]
    assert lifecycle_calls == [
        {
            "media_asset_ids": [MEDIA_ASSET_ID],
            "trigger_source": "placement_delete",
            "subject_type": "lesson_media",
            "subject_id": LESSON_MEDIA_ID,
        }
    ]
