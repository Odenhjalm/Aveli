import pytest

from app import schemas
from app.routes import studio

pytestmark = pytest.mark.anyio("asyncio")

LESSON_ID = "22222222-2222-2222-2222-222222222222"
LESSON_MEDIA_ID = "11111111-1111-1111-1111-111111111111"
MEDIA_ASSET_ID = "33333333-3333-3333-3333-333333333333"
TEACHER_ID = "44444444-4444-4444-4444-444444444444"


def _row(*, state: str = "ready") -> dict[str, object]:
    return {
        "lesson_media_id": LESSON_MEDIA_ID,
        "lesson_id": LESSON_ID,
        "media_asset_id": MEDIA_ASSET_ID,
        "position": 1,
        "media_type": "document",
        "state": state,
    }


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
    assert len(asset_calls) == 1
    assert asset_calls[0]["purpose"] == "lesson_media"
    assert asset_calls[0]["state"] == "pending_upload"
    assert len(upload_calls) == 1


async def test_canonical_upload_completion_does_not_attach(monkeypatch):
    completed: list[str] = []

    async def fake_authorize_media_asset(**kwargs):
        assert kwargs["media_asset_id"] == MEDIA_ASSET_ID
        return {"id": MEDIA_ASSET_ID, "state": "pending_upload"}

    async def fake_mark_uploaded(*, media_id: str):
        completed.append(media_id)
        return {"id": media_id, "state": "uploaded"}

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
