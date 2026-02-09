from app.routes import media as media_routes
from app.services import courses_service


def test_storage_candidates_strips_bucket_prefix_first():
    candidates = media_routes._storage_candidates(
        storage_bucket="course-media",
        storage_path="course-media/lessons/demo.mp4",
    )
    assert candidates[0] == ("course-media", "lessons/demo.mp4")
    assert ("course-media", "course-media/lessons/demo.mp4") in candidates


def test_storage_candidates_adds_bucket_mismatch_candidates():
    candidates = media_routes._storage_candidates(
        storage_bucket="course-media",
        storage_path="public-media/courses/demo.png",
    )
    assert ("public-media", "courses/demo.png") in candidates


def test_failure_reason_classifies_drift_and_mismatch():
    assert media_routes._failure_reason(
        storage_bucket="course-media",
        storage_path="course-media/lessons/demo.mp4",
    ) == "key_format_drift"
    assert media_routes._failure_reason(
        storage_bucket="course-media",
        storage_path="public-media/courses/demo.png",
    ) == "bucket_mismatch"
    assert media_routes._failure_reason(
        storage_bucket="course-media",
        storage_path="courses/demo.png",
    ) == "missing_object"


def test_courses_service_best_storage_candidate_detects_key_format_drift():
    existence = {("course-media", "lessons/demo.mp4"): True}
    bucket, key, reason, bytes_exist = courses_service._best_storage_candidate(
        storage_bucket="course-media",
        storage_path="course-media/lessons/demo.mp4",
        existence=existence,
        storage_table_available=True,
    )
    assert (bucket, key, reason, bytes_exist) == (
        "course-media",
        "lessons/demo.mp4",
        "key_format_drift",
        True,
    )


def test_courses_service_best_storage_candidate_detects_bucket_mismatch():
    existence = {("public-media", "courses/demo.png"): True}
    bucket, key, reason, bytes_exist = courses_service._best_storage_candidate(
        storage_bucket="course-media",
        storage_path="public-media/courses/demo.png",
        existence=existence,
        storage_table_available=True,
    )
    assert (bucket, key, reason, bytes_exist) == (
        "public-media",
        "courses/demo.png",
        "bucket_mismatch",
        True,
    )
