from __future__ import annotations

import copy

import pytest
from pydantic import ValidationError

from app import schemas


COURSE_ID = "11111111-1111-1111-1111-111111111111"
LESSON_ID = "22222222-2222-2222-2222-222222222222"


def _entry_view_payload() -> dict:
    return {
        "course": {
            "id": COURSE_ID,
            "slug": "intro-course",
            "title": "Intro Course",
            "description": "Backend-authored course description.",
            "cover": {
                "url": "https://cdn.test/course-cover.jpg",
                "alt": "Course cover",
            },
            "required_enrollment_source": "intro",
            "is_premium": False,
            "price_amount_cents": None,
            "price_currency": None,
            "formatted_price": None,
            "sellable": False,
        },
        "lessons": [
            {
                "id": LESSON_ID,
                "lesson_title": "Lesson 1",
                "position": 1,
                "availability": {
                    "state": "unlocked",
                    "can_open": True,
                    "reason_code": None,
                    "reason_text": None,
                    "next_unlock_at": None,
                },
                "progression": {
                    "state": "current",
                    "completed_at": None,
                    "is_next_recommended": True,
                },
            }
        ],
        "access": {
            "is_enrolled": False,
            "is_in_drip": False,
            "is_in_any_intro_drip": False,
            "can_enroll": True,
            "can_purchase": False,
        },
        "cta": {
            "type": "enroll",
            "label": "Enroll",
            "enabled": True,
            "reason_code": None,
            "reason_text": None,
            "price": None,
            "action": {"type": "enroll", "course_id": COURSE_ID},
        },
        "pricing": None,
        "next_recommended_lesson": {
            "id": LESSON_ID,
            "lesson_title": "Lesson 1",
            "position": 1,
        },
    }


def _mutated_payload(path: list[str | int], value) -> dict:
    payload = copy.deepcopy(_entry_view_payload())
    target = payload
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = value
    return payload


def test_valid_minimal_entry_view_response_validates():
    response = schemas.CourseEntryViewResponse(**_entry_view_payload())

    assert response.course.slug == "intro-course"
    assert response.course.cover is not None
    assert response.course.cover.url == "https://cdn.test/course-cover.jpg"
    assert response.lessons[0].availability.can_open is True
    assert response.cta.type == "enroll"


@pytest.mark.parametrize(
    "cta_type",
    ["enroll", "buy", "continue", "blocked", "unavailable"],
)
def test_existing_cta_literals_validate(cta_type: str):
    response = schemas.CourseEntryViewResponse(
        **_mutated_payload(["cta", "type"], cta_type)
    )

    assert response.cta.type == cta_type


def test_unknown_cta_literal_fails():
    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(
            **_mutated_payload(["cta", "type"], "purchase")
        )


@pytest.mark.parametrize("field", ["content_document", "content_markdown"])
def test_runtime_lesson_content_fields_are_rejected(field: str):
    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(
            **_mutated_payload(["lessons", 0, field], {"blocks": []})
        )


@pytest.mark.parametrize(
    "field",
    [
        "lesson_media_id",
        "media_asset_id",
        "media_id",
        "media",
        "media_type",
        "media_metadata",
        "media_placement_metadata",
    ],
)
def test_lesson_media_fields_are_rejected(field: str):
    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(
            **_mutated_payload(["lessons", 0, field], "forbidden")
        )


def test_lesson_resolved_url_is_rejected():
    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(
            **_mutated_payload(
                ["lessons", 0, "resolved_url"],
                "https://cdn.test/lesson-runtime.jpg",
            )
        )


def test_course_cover_resolved_url_is_rejected():
    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(
            **_mutated_payload(
                ["course", "cover", "resolved_url"],
                "https://cdn.test/resolved-cover.jpg",
            )
        )


@pytest.mark.parametrize(
    "path",
    [
        ["course", "unexpected"],
        ["course", "cover", "unexpected"],
        ["lessons", 0, "availability", "unexpected"],
        ["lessons", 0, "progression", "unexpected"],
        ["access", "unexpected"],
        ["cta", "unexpected"],
        ["pricing", "unexpected"],
        ["next_recommended_lesson", "unexpected"],
    ],
)
def test_extra_unknown_fields_are_rejected_at_nested_levels(path: list[str | int]):
    payload = _entry_view_payload()
    payload["pricing"] = {
        "price_amount_cents": 12000,
        "price_currency": "sek",
        "formatted_price": "120 SEK",
        "sellable": True,
    }
    target = payload
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = "unexpected"

    with pytest.raises(ValidationError):
        schemas.CourseEntryViewResponse(**payload)
