from __future__ import annotations

import pytest

from app.services import verification_observability


pytestmark = pytest.mark.anyio("asyncio")


async def test_verify_course_cover_truth_flags_legacy_fallback(monkeypatch):
    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == "course-1"
        assert slug is None
        return {
            "id": "course-1",
            "slug": "course-1",
            "title": "Course 1",
            "cover_media_id": "asset-1",
            "cover_url": "/api/files/public-media/courses/legacy-cover.jpg",
        }

    async def fake_resolve_course_cover(*, course_id: str, cover_media_id: str | None, cover_url: str | None):
        assert course_id == "course-1"
        assert cover_media_id == "asset-1"
        assert cover_url == "/api/files/public-media/courses/legacy-cover.jpg"
        return {
            "media_id": "asset-1",
            "state": "legacy_fallback",
            "resolved_url": "/api/files/public-media/courses/legacy-cover.jpg",
            "source": "legacy_cover_url",
        }

    async def fake_get_asset(asset_id: str):
        assert asset_id == "asset-1"
        return {
            "asset_id": asset_id,
            "state_classification": "asset_failed",
            "detected_inconsistencies": [
                {
                    "code": "asset_processing_failed",
                    "severity": "error",
                    "message": "asset failed processing",
                    "asset_id": asset_id,
                    "lesson_id": None,
                    "lesson_media_id": None,
                    "runtime_media_id": None,
                    "details": {},
                }
            ],
        }

    async def fake_get_media_failures(*, asset_id: str | None = None):
        assert asset_id == "asset-1"
        return {
            "asset_id": asset_id,
            "summary": {"asset_processing": 1},
            "media_failures": [{"event": "media_asset_failed"}],
        }

    async def fake_get_worker_health():
        return {
            "worker_health": {
                "media_transcode": {
                    "status": "ok",
                    "worker_running": True,
                    "queue_summary": {},
                }
            }
        }

    monkeypatch.setattr(
        verification_observability.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.courses_service,
        "resolve_course_cover",
        fake_resolve_course_cover,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.media_control_plane_observability,
        "get_asset",
        fake_get_asset,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_media_failures",
        fake_get_media_failures,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_worker_health",
        fake_get_worker_health,
        raising=True,
    )

    result = await verification_observability.verify_course_cover_truth("course-1")

    assert result["verdict"] == "fail"
    assert result["confidence"] == "high"
    assert result["summary"]["resolved_source"] == "legacy_cover_url"
    assert {item["code"] for item in result["violations"]} == {
        "course_cover_not_control_plane_ready",
        "asset_processing_failed",
        "recent_media_failures_detected",
    }


async def test_verify_course_cover_truth_accepts_null_cover_control_state(monkeypatch):
    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == "course-1"
        assert slug is None
        return {
            "id": "course-1",
            "slug": "course-1",
            "title": "Course 1",
            "cover_media_id": None,
            "cover_url": None,
        }

    async def fake_get_worker_health():
        return {
            "worker_health": {
                "media_transcode": {
                    "status": "ok",
                    "worker_running": True,
                    "queue_summary": {},
                }
            }
        }

    monkeypatch.setattr(
        verification_observability.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_worker_health",
        fake_get_worker_health,
        raising=True,
    )

    result = await verification_observability.verify_course_cover_truth("course-1")

    assert result["verdict"] == "pass"
    assert result["summary"]["resolved_state"] == "no_cover_control_state"
    assert result["summary"]["resolved_source"] == "no_cover_control_state"
    assert result["summary"]["asset_state_classification"] == "no_cover_control_state"
    assert result["violations"] == []


async def test_verify_course_cover_truth_passes_with_degraded_worker(monkeypatch):
    async def fake_get_course(*, course_id: str | None = None, slug: str | None = None):
        assert course_id == "course-1"
        assert slug is None
        return {
            "id": "course-1",
            "slug": "course-1",
            "title": "Course 1",
            "cover_media_id": "asset-1",
            "cover_url": None,
        }

    async def fake_resolve_course_cover(*, course_id: str, cover_media_id: str | None, cover_url: str | None):
        assert course_id == "course-1"
        assert cover_media_id == "asset-1"
        assert cover_url is None
        return {
            "media_id": "asset-1",
            "state": "ready",
            "resolved_url": "https://cdn.test/course-cover.jpg",
            "source": "control_plane",
        }

    async def fake_get_asset(asset_id: str):
        assert asset_id == "asset-1"
        return {
            "asset_id": asset_id,
            "state_classification": "ready",
            "detected_inconsistencies": [],
        }

    async def fake_get_media_failures(*, asset_id: str | None = None):
        assert asset_id == "asset-1"
        return {
            "asset_id": asset_id,
            "summary": {},
            "media_failures": [],
        }

    async def fake_get_worker_health():
        return {
            "worker_health": {
                "media_transcode": {
                    "status": "degraded",
                    "worker_running": True,
                    "queue_summary": {"uploaded": 48, "failed": 0},
                    "last_error": {
                        "message": "Historical worker error",
                        "timestamp": "2026-03-23T20:33:12Z",
                    },
                }
            }
        }

    monkeypatch.setattr(
        verification_observability.courses_repo,
        "get_course",
        fake_get_course,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.courses_service,
        "resolve_course_cover",
        fake_resolve_course_cover,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.media_control_plane_observability,
        "get_asset",
        fake_get_asset,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_media_failures",
        fake_get_media_failures,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_worker_health",
        fake_get_worker_health,
        raising=True,
    )

    result = await verification_observability.verify_course_cover_truth("course-1")

    assert result["verdict"] == "pass"
    assert result["violations"] == []
    assert result["subject_violations"] == []
    assert result["environment_signals"]["worker_status"] == "degraded"
    assert result["environment_signals"]["queue_summary"] == {"uploaded": 48, "failed": 0}
    assert result["summary"]["media_transcode_worker_status"] == "degraded"


async def test_get_test_cases_discovers_bounded_candidates(monkeypatch):
    async def fake_list_courses(*, teacher_id=None, status=None, limit=None, published_only=None, free_intro=None, search=None):
        assert limit == 12
        return [
            {
                "id": "course-1",
                "slug": "course-1",
                "title": "Course 1",
                "cover_media_id": "cover-1",
                "cover_url": None,
            },
            {
                "id": "course-2",
                "slug": "course-2",
                "title": "Course 2",
                "cover_media_id": None,
                "cover_url": None,
            },
        ]

    async def fake_list_course_lessons(course_id: str):
        if course_id == "course-1":
            return [{"id": "lesson-1", "title": "Lesson 1"}]
        return [{"id": "lesson-2", "title": "Lesson 2"}]

    async def fake_list_lesson_media(lesson_id: str, limit: int | None = None):
        assert limit == 1
        if lesson_id == "lesson-1":
            return [{"id": "lesson-media-1", "kind": "audio"}]
        return []

    monkeypatch.setattr(
        verification_observability.courses_repo,
        "list_courses",
        fake_list_courses,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.courses_repo,
        "list_course_lessons",
        fake_list_course_lessons,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.courses_repo,
        "list_lesson_media",
        fake_list_lesson_media,
        raising=True,
    )

    result = await verification_observability.get_test_cases()

    assert result["verdict"] == "pass"
    assert result["summary"]["course_cover_case_count"] == 1
    assert result["summary"]["lesson_media_case_count"] == 1
    assert result["course_cover_cases"][0]["course_id"] == "course-1"
    assert result["lesson_media_cases"][0]["lesson_id"] == "lesson-1"


async def test_verify_phase2_truth_alignment_aggregates_failed_samples(monkeypatch):
    async def fake_get_test_cases():
        return {
            "course_cover_cases": [{"course_id": "course-1"}],
            "lesson_media_cases": [{"lesson_id": "lesson-1"}],
        }

    async def fake_get_worker_health():
        return {
            "worker_health": {
                "media_transcode": {
                    "status": "ok",
                    "worker_running": True,
                    "queue_summary": {},
                }
            }
        }

    async def fake_get_recent_errors(*, limit: int | None = None):
        assert limit == 10
        return {"limit_applied": 10, "recent_errors": []}

    async def fake_verify_lesson_media_truth(lesson_id: str):
        assert lesson_id == "lesson-1"
        return {
            "lesson_id": lesson_id,
            "verdict": "fail",
            "confidence": "high",
            "violations": [{"code": "runtime_media_missing"}],
        }

    async def fake_verify_course_cover_truth(course_id: str):
        assert course_id == "course-1"
        return {
            "course_id": course_id,
            "verdict": "pass",
            "confidence": "high",
            "violations": [],
        }

    monkeypatch.setattr(
        verification_observability,
        "get_test_cases",
        fake_get_test_cases,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_worker_health",
        fake_get_worker_health,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_recent_errors",
        fake_get_recent_errors,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability,
        "verify_lesson_media_truth",
        fake_verify_lesson_media_truth,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability,
        "verify_course_cover_truth",
        fake_verify_course_cover_truth,
        raising=True,
    )

    result = await verification_observability.verify_phase2_truth_alignment()

    assert result["verdict"] == "fail"
    assert result["confidence"] == "high"
    assert result["summary"]["lesson_samples_checked"] == 1
    assert result["summary"]["course_cover_samples_checked"] == 1
    assert {item["code"] for item in result["violations"]} == {
        "lesson_truth_sample_failed",
    }


async def test_verify_phase2_truth_alignment_separates_environment_signals(monkeypatch):
    async def fake_get_test_cases():
        return {
            "course_cover_cases": [{"course_id": "course-1"}],
            "lesson_media_cases": [{"lesson_id": "lesson-1"}],
        }

    async def fake_get_worker_health():
        return {
            "worker_health": {
                "media_transcode": {
                    "status": "degraded",
                    "worker_running": True,
                    "queue_summary": {"uploaded": 12, "failed": 0},
                    "last_error": {"message": "Historical worker error"},
                }
            }
        }

    async def fake_get_recent_errors(*, limit: int | None = None):
        assert limit == 10
        return {
            "limit_applied": 10,
            "recent_errors": [{"message": "Historical backend error"}],
        }

    async def fake_verify_lesson_media_truth(lesson_id: str):
        assert lesson_id == "lesson-1"
        return {
            "lesson_id": lesson_id,
            "verdict": "pass",
            "confidence": "high",
            "violations": [],
        }

    async def fake_verify_course_cover_truth(course_id: str):
        assert course_id == "course-1"
        return {
            "course_id": course_id,
            "verdict": "pass",
            "confidence": "high",
            "violations": [],
        }

    monkeypatch.setattr(
        verification_observability,
        "get_test_cases",
        fake_get_test_cases,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_worker_health",
        fake_get_worker_health,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability.logs_observability,
        "get_recent_errors",
        fake_get_recent_errors,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability,
        "verify_lesson_media_truth",
        fake_verify_lesson_media_truth,
        raising=True,
    )
    monkeypatch.setattr(
        verification_observability,
        "verify_course_cover_truth",
        fake_verify_course_cover_truth,
        raising=True,
    )

    result = await verification_observability.verify_phase2_truth_alignment()

    assert result["verdict"] == "pass"
    assert result["violations"] == []
    assert result["environment_signals"]["worker_status"] == "degraded"
    assert result["environment_signals"]["recent_error_count"] == 1
