from __future__ import annotations

import inspect
from uuid import uuid4

import pytest
from pydantic import ValidationError

from app import schemas
from app.repositories import courses as courses_repo
from app.services import courses_service
from app.utils import lesson_document_validator

pytestmark = pytest.mark.anyio("asyncio")


EMPTY_DOCUMENT = {"schema_version": "lesson_document_v1", "blocks": []}


def _document_with_text(text: str) -> dict[str, object]:
    return {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "paragraph",
                "children": [
                    {
                        "text": text,
                        "marks": ["bold"],
                    }
                ],
            }
        ],
    }


def test_studio_lesson_content_schema_accepts_document_not_markdown() -> None:
    payload = schemas.StudioLessonContentUpdate(
        content_document=_document_with_text("Hello")
    )

    assert payload.content_document["schema_version"] == "lesson_document_v1"

    with pytest.raises(ValidationError):
        schemas.StudioLessonContentUpdate(content_markdown="# Legacy markdown")


def test_lesson_document_etag_uses_canonical_json_bytes() -> None:
    lesson_id = str(uuid4())
    first = {
        "schema_version": "lesson_document_v1",
        "blocks": [{"type": "paragraph", "children": [{"text": "Same"}]}],
    }
    same_with_different_key_order = {
        "blocks": [{"children": [{"text": "Same"}], "type": "paragraph"}],
        "schema_version": "lesson_document_v1",
    }
    changed = _document_with_text("Changed")

    assert courses_service.build_lesson_content_etag(
        lesson_id,
        first,
    ) == courses_service.build_lesson_content_etag(
        lesson_id,
        same_with_different_key_order,
    )
    assert courses_service.build_lesson_content_etag(
        lesson_id,
        first,
    ) != courses_service.build_lesson_content_etag(
        lesson_id,
        changed,
    )


def test_lesson_document_validator_accepts_required_document_shapes() -> None:
    media_id = str(uuid4())
    document = {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "heading",
                "level": 2,
                "children": [{"text": "Heading", "marks": ["bold"]}],
            },
            {
                "type": "paragraph",
                "children": [
                    {
                        "text": "Linked text",
                        "marks": [{"type": "link", "href": "/courses/example"}],
                    }
                ],
            },
            {
                "type": "bullet_list",
                "items": [{"children": [{"text": "Bullet", "marks": []}]}],
            },
            {
                "type": "ordered_list",
                "start": 3,
                "items": [{"children": [{"text": "Ordered", "marks": []}]}],
            },
            {
                "type": "media",
                "media_type": "image",
                "lesson_media_id": media_id,
            },
            {
                "type": "cta",
                "label": "Open",
                "target_url": "https://example.com/start",
            },
        ],
    }

    assert lesson_document_validator.validate_lesson_document(
        document,
        media_rows=[
            {
                "lesson_media_id": media_id,
                "media_type": "image",
                "state": "ready",
            }
        ],
    ) == document


@pytest.mark.parametrize(
    "document",
    [
        {"schema_version": "v0", "blocks": []},
        {
            "schema_version": "lesson_document_v1",
            "blocks": [{"type": "paragraph", "children": [{"text": "x", "marks": ["strike"]}]}],
        },
        {
            "schema_version": "lesson_document_v1",
            "blocks": [{"type": "paragraph", "children": [{"text": "x", "marks": ["bold", "bold"]}]}],
        },
        {
            "schema_version": "lesson_document_v1",
            "blocks": [{"type": "quote", "children": [{"text": "x", "marks": []}]}],
        },
        {
            "schema_version": "lesson_document_v1",
            "blocks": [{"type": "cta", "label": "", "target_url": "https://example.com"}],
        },
        {
            "schema_version": "lesson_document_v1",
            "blocks": [{"type": "cta", "label": "Open", "target_url": "javascript:alert(1)"}],
        },
    ],
)
def test_lesson_document_validator_rejects_invalid_document_shapes(
    document: dict[str, object],
) -> None:
    with pytest.raises(lesson_document_validator.LessonDocumentValidationError):
        lesson_document_validator.validate_lesson_document(document)


def test_lesson_document_validator_rejects_invalid_media_references() -> None:
    media_id = str(uuid4())
    document = {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "media",
                "media_type": "audio",
                "lesson_media_id": media_id,
                "media_asset_id": str(uuid4()),
            }
        ],
    }

    with pytest.raises(lesson_document_validator.LessonDocumentValidationError):
        lesson_document_validator.validate_lesson_document(
            document,
            media_rows=[
                {
                    "lesson_media_id": media_id,
                    "media_type": "audio",
                    "state": "ready",
                }
            ],
        )

    valid_shape_with_unknown_media = {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "media",
                "media_type": "audio",
                "lesson_media_id": media_id,
            }
        ],
    }
    with pytest.raises(lesson_document_validator.LessonDocumentValidationError):
        lesson_document_validator.validate_lesson_document(
            valid_shape_with_unknown_media,
            media_rows=[],
        )

    with pytest.raises(lesson_document_validator.LessonDocumentValidationError):
        lesson_document_validator.validate_lesson_document(
            valid_shape_with_unknown_media,
            media_rows=[
                {
                    "lesson_media_id": media_id,
                    "media_type": "video",
                    "state": "ready",
                }
            ],
        )


async def test_studio_lesson_content_service_reads_and_writes_document_with_cas(
    monkeypatch,
) -> None:
    lesson_id = str(uuid4())
    course_id = str(uuid4())
    writes: list[dict[str, object]] = []

    async def fake_get_studio_lesson_content(
        requested_lesson_id: str,
    ) -> dict[str, object]:
        assert requested_lesson_id == lesson_id
        return {
            "lesson_id": lesson_id,
            "course_id": course_id,
            "content_document": EMPTY_DOCUMENT,
        }

    async def fake_is_course_owner(teacher_id: str, requested_course_id: str) -> bool:
        assert teacher_id == "teacher-1"
        assert requested_course_id == course_id
        return True

    async def fake_list_studio_lesson_media(
        requested_lesson_id: str,
    ) -> list[dict[str, object]]:
        assert requested_lesson_id == lesson_id
        return []

    async def fake_update_lesson_document_if_current(
        requested_lesson_id: str,
        content_document: dict[str, object],
        *,
        expected_content_document: dict[str, object],
    ) -> dict[str, object]:
        writes.append(
            {
                "lesson_id": requested_lesson_id,
                "content_document": content_document,
                "expected_content_document": expected_content_document,
            }
        )
        return {
            "lesson_id": requested_lesson_id,
            "content_document": content_document,
        }

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_studio_lesson_content",
        fake_get_studio_lesson_content,
    )
    monkeypatch.setattr(courses_service, "is_course_owner", fake_is_course_owner)
    monkeypatch.setattr(
        courses_service,
        "list_studio_lesson_media",
        fake_list_studio_lesson_media,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "update_lesson_document_if_current",
        fake_update_lesson_document_if_current,
    )

    current = await courses_service.read_studio_lesson_content(
        lesson_id,
        teacher_id="teacher-1",
    )
    assert current is not None
    assert set(current["body"]) == {"lesson_id", "content_document", "media"}
    assert current["body"]["content_document"] == EMPTY_DOCUMENT

    with pytest.raises(courses_service.LessonContentPreconditionRequired):
        await courses_service.update_lesson_content(
            lesson_id,
            content_document=_document_with_text("No precondition"),
            if_match=None,
            teacher_id="teacher-1",
        )

    with pytest.raises(courses_service.LessonContentPreconditionFailed):
        await courses_service.update_lesson_content(
            lesson_id,
            content_document=_document_with_text("Stale"),
            if_match='"lesson-content:stale"',
            teacher_id="teacher-1",
        )

    updated_document = _document_with_text("Persisted")
    updated = await courses_service.update_lesson_content(
        lesson_id,
        content_document=updated_document,
        if_match=current["etag"],
        teacher_id="teacher-1",
    )

    assert writes == [
        {
            "lesson_id": lesson_id,
            "content_document": updated_document,
            "expected_content_document": EMPTY_DOCUMENT,
        }
    ]
    assert updated is not None
    assert updated["body"] == {
        "lesson_id": lesson_id,
        "content_document": updated_document,
    }
    assert updated["etag"] != current["etag"]


async def test_studio_lesson_content_service_persists_media_and_cta_nodes(
    monkeypatch,
) -> None:
    lesson_id = str(uuid4())
    course_id = str(uuid4())
    media_id = str(uuid4())
    writes: list[dict[str, object]] = []

    async def fake_get_studio_lesson_content(
        requested_lesson_id: str,
    ) -> dict[str, object]:
        return {
            "lesson_id": requested_lesson_id,
            "course_id": course_id,
            "content_document": EMPTY_DOCUMENT,
        }

    async def fake_is_course_owner(teacher_id: str, requested_course_id: str) -> bool:
        return teacher_id == "teacher-1" and requested_course_id == course_id

    async def fake_list_studio_lesson_media(
        requested_lesson_id: str,
    ) -> list[dict[str, object]]:
        assert requested_lesson_id == lesson_id
        return [
            {
                "lesson_media_id": media_id,
                "media_asset_id": str(uuid4()),
                "position": 1,
                "media_type": "video",
                "state": "ready",
            }
        ]

    async def fake_update_lesson_document_if_current(
        requested_lesson_id: str,
        content_document: dict[str, object],
        *,
        expected_content_document: dict[str, object],
    ) -> dict[str, object]:
        writes.append(
            {
                "lesson_id": requested_lesson_id,
                "content_document": content_document,
                "expected_content_document": expected_content_document,
            }
        )
        return {
            "lesson_id": requested_lesson_id,
            "content_document": content_document,
        }

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_studio_lesson_content",
        fake_get_studio_lesson_content,
    )
    monkeypatch.setattr(courses_service, "is_course_owner", fake_is_course_owner)
    monkeypatch.setattr(
        courses_service,
        "list_studio_lesson_media",
        fake_list_studio_lesson_media,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "update_lesson_document_if_current",
        fake_update_lesson_document_if_current,
    )

    current = await courses_service.read_studio_lesson_content(
        lesson_id,
        teacher_id="teacher-1",
    )
    assert current is not None
    document = {
        "schema_version": "lesson_document_v1",
        "blocks": [
            {
                "type": "media",
                "media_type": "video",
                "lesson_media_id": media_id,
            },
            {
                "type": "cta",
                "label": "Book now",
                "target_url": "/book",
            },
        ],
    }

    updated = await courses_service.update_lesson_content(
        lesson_id,
        content_document=document,
        if_match=current["etag"],
        teacher_id="teacher-1",
    )

    assert writes == [
        {
            "lesson_id": lesson_id,
            "content_document": document,
            "expected_content_document": EMPTY_DOCUMENT,
        }
    ]
    assert updated is not None
    assert updated["body"]["content_document"] == document


async def test_studio_lesson_content_service_rejects_invalid_document_before_write(
    monkeypatch,
) -> None:
    lesson_id = str(uuid4())
    course_id = str(uuid4())

    async def fake_get_studio_lesson_content(
        requested_lesson_id: str,
    ) -> dict[str, object]:
        return {
            "lesson_id": requested_lesson_id,
            "course_id": course_id,
            "content_document": EMPTY_DOCUMENT,
        }

    async def fake_is_course_owner(teacher_id: str, requested_course_id: str) -> bool:
        return teacher_id == "teacher-1" and requested_course_id == course_id

    async def fake_list_studio_lesson_media(
        requested_lesson_id: str,
    ) -> list[dict[str, object]]:
        assert requested_lesson_id == lesson_id
        return []

    async def fail_update_lesson_document_if_current(*args, **kwargs):
        raise AssertionError("invalid documents must fail before persistence")

    monkeypatch.setattr(
        courses_service.courses_repo,
        "get_studio_lesson_content",
        fake_get_studio_lesson_content,
    )
    monkeypatch.setattr(courses_service, "is_course_owner", fake_is_course_owner)
    monkeypatch.setattr(
        courses_service,
        "list_studio_lesson_media",
        fake_list_studio_lesson_media,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "update_lesson_document_if_current",
        fail_update_lesson_document_if_current,
    )

    current = await courses_service.read_studio_lesson_content(
        lesson_id,
        teacher_id="teacher-1",
    )
    assert current is not None

    with pytest.raises(courses_service.HTTPException) as exc_info:
        await courses_service.update_lesson_content(
            lesson_id,
            content_document={"schema_version": "invalid", "blocks": []},
            if_match=current["etag"],
            teacher_id="teacher-1",
        )

    assert exc_info.value.status_code == 400


def test_repository_boundary_uses_content_document_jsonb_compare_and_set() -> None:
    read_source = inspect.getsource(courses_repo.get_studio_lesson_content)
    write_source = inspect.getsource(courses_repo.update_lesson_document_if_current)

    assert "content_document" in read_source
    assert "content_markdown, '') as content_markdown" not in read_source
    assert "expected_content_document" in write_source
    assert "Jsonb(content_document)" in write_source
    assert "Jsonb(expected_content_document)" in write_source
    assert "do update set content_document = excluded.content_document" in write_source
    assert "returning lesson_id, content_document" in write_source
