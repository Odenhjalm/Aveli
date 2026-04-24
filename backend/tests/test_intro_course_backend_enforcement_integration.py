from __future__ import annotations

from datetime import timedelta
import uuid

import pytest

from app import db
from app.repositories import lesson_completions
from app.services import course_drip_worker
from tests.test_courses_enroll import (
    _cleanup_courses,
    _cleanup_user,
    _grant_app_entry,
    _insert_intro_course,
    _insert_lessons,
    _insert_teacher,
)


pytestmark = pytest.mark.anyio("asyncio")


async def _ordered_lesson_ids(course_id: str) -> list[str]:
    async with db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT id::text
                FROM app.lessons
                WHERE course_id = %s::uuid
                ORDER BY position, id
                """,
                (course_id,),
            )
            rows = await cur.fetchall()
    return [row[0] for row in rows]


@pytest.mark.anyio("asyncio")
async def test_intro_selection_unlocks_after_progression_and_completion_and_allows_next_intro_enrollment(
    async_client,
):
    email = f"intro_lifecycle_{uuid.uuid4().hex[:8]}@example.com"
    register_resp = await async_client.post(
        "/auth/register",
        json={
            "email": email,
            "password": "Intro123!",
        },
    )
    assert register_resp.status_code == 201, register_resp.text
    access_token = register_resp.json()["access_token"]
    headers = {"Authorization": f"Bearer {access_token}"}

    profile_resp = await async_client.get("/profiles/me", headers=headers)
    assert profile_resp.status_code == 200, profile_resp.text
    user_id = str(profile_resp.json()["user_id"])
    await _grant_app_entry(async_client, headers, user_id)
    teacher_id = await _insert_teacher(
        f"intro_lifecycle_teacher_{uuid.uuid4().hex[:8]}@example.com"
    )
    first_course = await _insert_intro_course(
        teacher_id,
        title="Lifecycle Intro One",
        drip_enabled=True,
        drip_interval_days=2,
    )
    second_course = await _insert_intro_course(
        teacher_id,
        title="Lifecycle Intro Two",
        drip_enabled=False,
        drip_interval_days=None,
    )
    await _insert_lessons(first_course["id"], count=3)
    await _insert_lessons(second_course["id"], count=2)

    try:
        initial_selection_resp = await async_client.get(
            "/courses/intro-selection",
            headers=headers,
        )
        assert initial_selection_resp.status_code == 200, initial_selection_resp.text
        initial_selection_payload = initial_selection_resp.json()
        assert initial_selection_payload["selection_locked"] is False
        assert initial_selection_payload["selection_lock_reason"] is None
        initial_eligible_ids = {
            item["id"] for item in initial_selection_payload["eligible_courses"]
        }
        assert first_course["id"] in initial_eligible_ids
        assert second_course["id"] in initial_eligible_ids

        first_enroll_resp = await async_client.post(
            f"/courses/{first_course['id']}/enroll",
            headers=headers,
        )
        assert first_enroll_resp.status_code == 200, first_enroll_resp.text
        first_enroll_payload = first_enroll_resp.json()
        assert first_enroll_payload["required_enrollment_source"] == "intro_enrollment"
        assert first_enroll_payload["enrollment"] is not None
        enrollment_id = first_enroll_payload["enrollment"]["id"]
        auto_completion_candidate = (
            await lesson_completions.get_intro_final_lesson_auto_completion_candidate(
                enrollment_id=enrollment_id,
            )
        )
        assert auto_completion_candidate is not None
        assert auto_completion_candidate["final_unlock_at"] is not None
        auto_completion_at = auto_completion_candidate["final_unlock_at"] + timedelta(
            days=7
        )
        before_auto_completion_at = auto_completion_at - timedelta(seconds=1)

        drip_locked_resp = await async_client.get(
            "/courses/intro-selection",
            headers=headers,
        )
        assert drip_locked_resp.status_code == 200, drip_locked_resp.text
        assert drip_locked_resp.json() == {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_drip",
            "eligible_courses": [],
        }

        await course_drip_worker.run_once(now=before_auto_completion_at)

        completion_locked_resp = await async_client.get(
            "/courses/intro-selection",
            headers=headers,
        )
        assert completion_locked_resp.status_code == 200, completion_locked_resp.text
        assert completion_locked_resp.json() == {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_lesson_completion",
            "eligible_courses": [],
        }

        lesson_ids = await _ordered_lesson_ids(first_course["id"])
        assert len(lesson_ids) == 3

        for lesson_id in lesson_ids[:-1]:
            complete_resp = await async_client.post(
                f"/courses/lessons/{lesson_id}/complete",
                headers=headers,
            )
            assert complete_resp.status_code == 200, complete_resp.text
            completion_payload = complete_resp.json()
            assert completion_payload["status"] == "completed"
            assert completion_payload["completion"]["lesson_id"] == lesson_id
            assert completion_payload["completion"]["completion_source"] == "manual"

        still_locked_resp = await async_client.get(
            "/courses/intro-selection",
            headers=headers,
        )
        assert still_locked_resp.status_code == 200, still_locked_resp.text
        assert still_locked_resp.json() == {
            "selection_locked": True,
            "selection_lock_reason": "incomplete_lesson_completion",
            "eligible_courses": [],
        }

        await course_drip_worker.run_once(now=auto_completion_at)

        completion_rows = await lesson_completions.list_course_lesson_completions(
            user_id=user_id,
            course_id=first_course["id"],
        )
        assert len(completion_rows) == 3
        final_completion = next(
            row for row in completion_rows if str(row["lesson_id"]) == lesson_ids[-1]
        )
        assert final_completion["completion_source"] == "auto_final_lesson"

        unlocked_selection_resp = await async_client.get(
            "/courses/intro-selection",
            headers=headers,
        )
        assert (
            unlocked_selection_resp.status_code == 200
        ), unlocked_selection_resp.text
        unlocked_selection_payload = unlocked_selection_resp.json()
        assert unlocked_selection_payload["selection_locked"] is False
        assert unlocked_selection_payload["selection_lock_reason"] is None
        unlocked_eligible_ids = {
            item["id"] for item in unlocked_selection_payload["eligible_courses"]
        }
        assert first_course["id"] not in unlocked_eligible_ids
        assert second_course["id"] in unlocked_eligible_ids

        second_enroll_resp = await async_client.post(
            f"/courses/{second_course['id']}/enroll",
            headers=headers,
        )
        assert second_enroll_resp.status_code == 200, second_enroll_resp.text
        second_enroll_payload = second_enroll_resp.json()
        assert second_enroll_payload["required_enrollment_source"] == "intro_enrollment"
        assert second_enroll_payload["enrollment"] is not None

        first_access_resp = await async_client.get(
            f"/courses/{first_course['id']}/access",
            headers=headers,
        )
        assert first_access_resp.status_code == 200, first_access_resp.text
        first_access_payload = first_access_resp.json()
        assert first_access_payload["is_intro_course"] is True
        assert first_access_payload["can_access"] is True
        assert first_access_payload["enrollment"] is not None
        assert first_access_payload["enrollment"]["course_id"] == first_course["id"]
    finally:
        await _cleanup_courses([first_course["id"], second_course["id"]])
        await _cleanup_user(teacher_id)
        await _cleanup_user(user_id)
