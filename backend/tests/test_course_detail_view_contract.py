from __future__ import annotations

from uuid import UUID

import pytest

from app import schemas
from app.routes import courses as course_routes
from app.services import courses_read_service, courses_service

pytestmark = pytest.mark.anyio("asyncio")


COURSE_ID = "11111111-1111-1111-1111-111111111111"
COURSE_GROUP_ID = "22222222-2222-2222-2222-222222222222"
COVER_MEDIA_ID = "33333333-3333-3333-3333-333333333333"
LESSON_ID = "44444444-4444-4444-4444-444444444444"


def _course_payload(*, cover: dict | None) -> dict:
    return {
        "id": COURSE_ID,
        "slug": "course-1",
        "title": "Course 1",
        "course_group_id": COURSE_GROUP_ID,
        "group_position": 0,
        "cover_media_id": COVER_MEDIA_ID,
        "cover": cover,
        "price_amount_cents": None,
        "drip_enabled": False,
        "drip_interval_days": None,
    }


def _cover_payload() -> dict[str, str | None]:
    return {
        "media_id": COVER_MEDIA_ID,
        "state": "ready",
        "resolved_url": "https://cdn.test/course-cover.jpg",
    }


def _detail_response(
    *,
    cover: dict | None,
    lessons: list[dict] | None = None,
    short_description: str | None = None,
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
        short_description=short_description,
    )


async def test_course_detail_http_shape_contains_cover_and_null_sibling_content(
    async_client,
    monkeypatch,
):
    async def fake_read_course_detail(*, course_id: str | None = None, slug: str | None = None):
        assert course_id is None
        assert slug == "course-1"
        return _detail_response(cover=_cover_payload(), short_description=None)

    monkeypatch.setattr(
        course_routes.courses_read_service,
        "read_course_detail",
        fake_read_course_detail,
        raising=True,
    )

    response = await async_client.get("/courses/by-slug/course-1")
    assert response.status_code == 200, response.text
    body = response.json()

    assert set(body.keys()) == {"course", "lessons", "short_description"}
    assert body["short_description"] is None
    assert body["course"]["cover"] == _cover_payload()
    assert set(body["course"].keys()) == {
        "id",
        "slug",
        "title",
        "course_group_id",
        "group_position",
        "cover_media_id",
        "cover",
        "price_amount_cents",
        "drip_enabled",
        "drip_interval_days",
    }
    assert body["lessons"] == [
        {
            "id": LESSON_ID,
            "lesson_title": "Lesson 1",
            "position": 1,
        }
    ]
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
        return _detail_response(cover=None, lessons=[], short_description=None)

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
    assert body["short_description"] is None


async def test_course_detail_route_is_identity_independent(monkeypatch):
    detail = _detail_response(cover=_cover_payload(), short_description="Short")
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
    detail = _detail_response(cover=_cover_payload(), short_description="Short")
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
    ):
        assert search == "course"
        assert limit == 5
        return [_course_payload(cover=None)]

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

    assert rows == [_course_payload(cover=None)]


async def test_read_course_detail_composes_cover_and_null_short_description(monkeypatch):
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
                "short_description": None,
                "lesson_id": LESSON_ID,
                "lesson_title": "Lesson 1",
                "lesson_position": 1,
            },
            {
                **_course_payload(cover=None),
                "short_description": None,
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
    assert payload["short_description"] is None
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
            "short_description": "Short description",
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
        "short_description": "Short description",
    }
