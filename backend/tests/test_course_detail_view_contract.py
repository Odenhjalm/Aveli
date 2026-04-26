from __future__ import annotations

from pathlib import Path
from uuid import UUID

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app import schemas
from app.routes import courses as course_routes
from app.routes import landing as landing_routes
from app.services import courses_read_service, courses_service

pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "11111111-1111-1111-1111-111111111111"
COURSE_GROUP_ID = "22222222-2222-2222-2222-222222222222"
COVER_MEDIA_ID = "33333333-3333-3333-3333-333333333333"
LESSON_ID = "44444444-4444-4444-4444-444444444444"
TEACHER_ID = "66666666-6666-6666-6666-666666666666"


def _course_payload(*, cover: dict | None) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "teacher": {
            "user_id": TEACHER_ID,
            "display_name": "Aveli Teacher",
        },
        "course_group_id": COURSE_GROUP_ID,
        "group_position": 0,
        "cover_media_id": COVER_MEDIA_ID,
        "cover": cover,
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
        "required_enrollment_source": "intro",
        "enrollable": True,
        "purchasable": False,
    }


def _cover_payload() -> dict[str, str | None]:
    return {
        "media_id": COVER_MEDIA_ID,
        "state": "ready",
        "resolved_url": "https://cdn.test/course-cover.jpg",
    }


def test_course_progression_authority_documents_use_group_position():
    root = Path(__file__).resolve().parents[1].parent
    paths = [
        root / "actual_truth/Aveli_System_Decisions.md",
        root / "actual_truth/aveli_system_manifest.json",
        root / "actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md",
        root / "actual_truth/contracts/course_public_surface_contract.md",
        root / "actual_truth/contracts/course_lesson_editor_contract.md",
        root / "actual_truth/contracts/learner_public_edge_contract.md",
    ]
    text = "\n".join(path.read_text(encoding="utf-8") for path in paths)

    assert "group_position" in text
    assert "`course.step` is the only canonical progression field" not in text
    assert "`app.courses.step`" not in text
    assert '"course_progression_field": "step"' not in text
    assert '"progression_set_ordered_by_step"' not in text
    assert '"step": "intro | step1 | step2 | step3"' not in text


def _detail_response(
    *,
    cover: dict | None,
    lessons: list[dict] | None = None,
    description: str | None = None,
) -> schemas.CourseDetailResponse:
    return schemas.CourseDetailResponse(
        course=schemas.Course(**_course_payload(cover=cover)),
        lessons=[
            schemas.LessonStructureItem(**row)
            for row in (
                lessons
                if lessons is not None
                else [
                    {
                        "id": LESSON_ID,
                        "lesson_title": "Lesson 1",
                        "position": 1,
                    }
                ]
            )
        ],
        description=description,
    )


async def test_course_detail_http_shape_contains_cover_and_null_sibling_content(
    async_client,
    monkeypatch,
):
    async def fake_read_course_detail(*, course_id: str | None = None, slug: str | None = None):
        assert course_id is None
        assert slug == "course-1"
        return _detail_response(cover=_cover_payload(), description=None)

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    response = await async_client.get("/courses/by-slug/course-1")
    assert response.status_code == 200, response.text
    body = response.json()

    assert set(body.keys()) == {"course", "lessons", "description"}
    assert body["description"] is None
    assert body["course"]["cover"] == _cover_payload()
    assert set(body["course"].keys()) == {
        "id",
        "slug",
        "title",
        "teacher",
        "course_group_id",
        "group_position",
        "cover_media_id",
        "cover",
        "price_amount_cents",
        "drip_enabled",
        "drip_interval_days",
        "required_enrollment_source",
        "enrollable",
        "purchasable",
    }
    assert body["lessons"] == [
        {
            "id": LESSON_ID,
            "lesson_title": "Lesson 1",
            "position": 1,
        }
    ]
    assert body["course"]["teacher"] == {
        "user_id": TEACHER_ID,
        "display_name": "Aveli Teacher",
    }
    assert "step" not in body["course"]
    assert set(body["lessons"][0].keys()) == {"id", "lesson_title", "position"}
    for forbidden_key in (
        "lesson_content",
        "lesson_media",
        "runtime_media",
        "course_enrollments",
    ):
        assert forbidden_key not in body
        assert forbidden_key not in body["course"]


async def test_course_detail_http_shape_preserves_empty_lessons_and_null_cover(
    async_client,
    monkeypatch,
):
    async def fake_read_course_detail(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == COURSE_ID
        assert slug is None
        return _detail_response(cover=None, lessons=[], description=None)

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    response = await async_client.get(f"/courses/{COURSE_ID}")
    assert response.status_code == 200, response.text
    body = response.json()

    assert body["course"]["cover"] is None
    assert body["lessons"] == []
    assert body["description"] is None


async def test_course_detail_route_is_identity_independent(monkeypatch):
    detail = _detail_response(cover=_cover_payload(), description="Description")
    calls: list[tuple[str | None, str | None]] = []

    async def fake_read_course_detail(*, course_id: str | None = None, slug: str | None = None):
        calls.append((course_id, slug))
        return detail

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    anonymous = await course_routes.course_detail_by_slug("course-1", None)
    authenticated = await course_routes.course_detail_by_slug(
        "course-1",
        {"id": UUID(COURSE_ID)},
    )

    assert anonymous.model_dump(mode="json") == authenticated.model_dump(mode="json")
    assert calls == [(None, "course-1"), (None, "course-1")]


async def test_course_detail_by_id_route_is_identity_independent(monkeypatch):
    detail = _detail_response(cover=_cover_payload(), description="Description")
    calls: list[tuple[str | None, str | None]] = []

    async def fake_read_course_detail(*, course_id: str | None = None, slug: str | None = None):
        calls.append((course_id, slug))
        return detail

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    anonymous = await course_routes.course_detail(UUID(COURSE_ID), None)
    authenticated = await course_routes.course_detail(
        UUID(COURSE_ID),
        {"id": UUID(COURSE_ID)},
    )

    assert anonymous.model_dump(mode="json") == authenticated.model_dump(mode="json")
    assert calls == [(COURSE_ID, None), (COURSE_ID, None)]


async def test_list_public_courses_reads_public_discovery_surface(monkeypatch):
    async def fail_list_public_courses(*, search: str | None = None, limit: int | None = None):
        raise AssertionError("raw course list must not back public discovery")

    async def fake_list_public_course_discovery(
        *,
        search: str | None = None,
        limit: int | None = None,
        group_position: int | None = None,
    ):
        assert search == "course"
        assert limit == 5
        assert group_position is None
        return [{**_course_payload(cover=None), "sellable": False}]

    async def fake_attach_course_cover_read_contract(courses):
        rows = [courses] if isinstance(courses, dict) else list(courses)
        for row in rows:
            row["cover"] = None

    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_public_courses",
        fail_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service.courses_repo,
        "list_public_course_discovery",
        fake_list_public_course_discovery,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "attach_course_cover_read_contract",
        fake_attach_course_cover_read_contract,
        raising=True,
    )

    rows = await courses_service.list_public_courses(search="course", limit=5)

    assert len(rows) == 1
    assert rows[0]["id"] == COURSE_ID
    assert rows[0]["enrollable"] is True
    assert rows[0]["purchasable"] is False


async def test_course_route_rejects_legacy_step_field(monkeypatch):
    async def fake_list_public_courses(*, search: str | None = None, limit: int | None = None):
        del search, limit
        return [{**_course_payload(cover=None), "step": "intro"}]

    async def fake_attach_course_cover_read_contract(courses):
        rows = [courses] if isinstance(courses, dict) else list(courses)
        for row in rows:
            row["cover"] = None

    monkeypatch.setattr(
        course_routes.courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "attach_course_cover_read_contract",
        fake_attach_course_cover_read_contract,
        raising=True,
    )

    with pytest.raises(ValueError, match="legacy course progression"):
        await course_routes.list_courses()


async def test_course_list_http_shape_uses_description(async_client, monkeypatch):
    async def fake_list_public_courses(*, search: str | None = None, limit: int | None = None):
        assert search is None
        assert limit is None
        return [
            {
                **_course_payload(cover=None),
                "description": "Backend-authored list description",
            }
        ]

    async def fake_attach_course_cover_read_contract(courses):
        rows = [courses] if isinstance(courses, dict) else list(courses)
        for row in rows:
            row["cover"] = None

    monkeypatch.setattr(
        course_routes.courses_service,
        "list_public_courses",
        fake_list_public_courses,
        raising=True,
    )
    monkeypatch.setattr(
        course_routes.courses_service,
        "attach_course_cover_read_contract",
        fake_attach_course_cover_read_contract,
        raising=True,
    )

    response = await async_client.get("/courses")
    assert response.status_code == 200, response.text
    item = response.json()["items"][0]
    assert item["description"] == "Backend-authored list description"


async def test_landing_course_http_shape_uses_description(async_client, monkeypatch):
    async def fake_list_intro_courses():
        return [
            {
                **_course_payload(cover=None),
                "description": "Backend-authored landing description",
            }
        ]

    monkeypatch.setattr(
        landing_routes.models,
        "list_intro_courses",
        fake_list_intro_courses,
        raising=True,
    )

    response = await async_client.get("/landing/intro-courses")
    assert response.status_code == 200, response.text
    item = response.json()["items"][0]
    assert item["description"] == "Backend-authored landing description"


def test_course_schemas_reject_legacy_step_field():
    with pytest.raises(ValidationError):
        schemas.Course(**{**_course_payload(cover=None), "step": "intro"})

    with pytest.raises(ValidationError):
        schemas.CourseAccessStateResponse(
            course_id=COURSE_ID,
            group_position=0,
            step="intro",
            required_enrollment_source="intro",
            is_intro_course=True,
            selection_locked=False,
            enrollable=True,
            purchasable=False,
            can_access=False,
            enrollment=None,
        )


async def test_read_course_detail_composes_teacher_cover_and_description(monkeypatch):
    async def fail_fetch_course(*, course_id: str | None = None, slug: str | None = None):
        raise AssertionError("raw course reads must not back public course detail")

    async def fake_attach_course_cover_read_contract(course):
        assert course["cover_media_id"] == COVER_MEDIA_ID
        course["cover"] = _cover_payload()

    async def fake_fetch_public_course_detail_rows(
        *,
        course_id: str | None = None,
        slug: str | None = None,
    ):
        assert course_id == COURSE_ID
        assert slug is None
        return [
            {
                **_course_payload(cover=None),
                "sellable": False,
                "teacher_id": TEACHER_ID,
                "teacher_display_name": "Aveli Teacher",
                "description": "Backend-authored course description",
                "lesson_id": LESSON_ID,
                "lesson_title": "Lesson 1",
                "lesson_position": 1,
            },
            {
                **_course_payload(cover=None),
                "sellable": False,
                "teacher_id": TEACHER_ID,
                "teacher_display_name": "Aveli Teacher",
                "description": "Backend-authored course description",
                "lesson_id": "55555555-5555-5555-5555-555555555555",
                "lesson_title": "Lesson 2",
                "lesson_position": 2,
            },
        ]

    monkeypatch.setattr(
        courses_service,
        "fetch_course",
        fail_fetch_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "attach_course_cover_read_contract",
        fake_attach_course_cover_read_contract,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "fetch_public_course_detail_rows",
        fake_fetch_public_course_detail_rows,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "list_course_lessons",
        fail_fetch_course,
        raising=True,
    )
    monkeypatch.setattr(
        courses_service,
        "fetch_course_public_content",
        fail_fetch_course,
        raising=True,
    )

    detail = await courses_read_service.read_course_detail(course_id=COURSE_ID)

    assert detail is not None
    payload = detail.model_dump(mode="json")
    assert payload["description"] == "Backend-authored course description"
    assert payload["course"]["teacher"] == {
        "user_id": TEACHER_ID,
        "display_name": "Aveli Teacher",
    }
    assert payload["course"]["cover"] == _cover_payload()
    assert payload["lessons"] == [
        {"id": LESSON_ID, "lesson_title": "Lesson 1", "position": 1},
        {
            "id": "55555555-5555-5555-5555-555555555555",
            "lesson_title": "Lesson 2",
            "position": 2,
        },
    ]


async def test_course_public_content_route_reads_through_public_detail_surface(
    async_client,
    monkeypatch,
):
    async def fake_read_public_course_content(course_id: str):
        assert course_id == COURSE_ID
        return {
            "course_id": COURSE_ID,
            "description": "Course description",
        }

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_public_course_content",
        fake_read_public_course_content,
        raising=True,
    )

    response = await async_client.get(f"/courses/{COURSE_ID}/public")
    assert response.status_code == 200, response.text
    assert response.json() == {
        "course_id": COURSE_ID,
        "description": "Course description",
    }


async def test_course_detail_missing_course_uses_swedish_safe_error(
    monkeypatch,
) -> None:
    async def fake_read_course_detail(
        *,
        course_id: str | None = None,
        slug: str | None = None,
    ):
        del course_id, slug
        return None

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    with pytest.raises(HTTPException) as excinfo:
        await course_routes.course_detail_by_slug("missing-course", None)

    assert excinfo.value.status_code == 404
    assert excinfo.value.detail == "Kursen kunde inte hittas."
    assert "course not found" not in str(excinfo.value.detail).lower()
