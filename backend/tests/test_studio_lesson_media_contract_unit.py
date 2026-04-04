import pytest

from app.routes import studio

pytestmark = pytest.mark.anyio("asyncio")


def _row(*, state: str = "ready") -> dict[str, object]:
    return {
        "lesson_media_id": "11111111-1111-1111-1111-111111111111",
        "lesson_id": "22222222-2222-2222-2222-222222222222",
        "media_asset_id": "33333333-3333-3333-3333-333333333333",
        "position": 1,
        "media_type": "document",
        "state": state,
        "preview_ready": state in {"uploaded", "ready"},
        "original_name": "guide.pdf",
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
