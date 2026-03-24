import pytest
from fastapi import HTTPException

from app.routes import api_media
from app.routes import upload as upload_routes
from app.services import media_resolver
from app.utils import media_paths


def test_audio_ingest_format_allows_mp3_wav_and_m4a():
    assert api_media._audio_ingest_format("demo.mp3", "audio/mpeg") == "mp3"
    assert api_media._audio_ingest_format("demo.mp3", "audio/mp3") == "mp3"
    assert api_media._audio_ingest_format("demo.wav", "audio/wav") == "wav"
    assert api_media._audio_ingest_format("demo.wav", "audio/x-wav") == "wav"
    assert api_media._audio_ingest_format("demo.m4a", "audio/m4a") == "m4a"
    assert api_media._audio_ingest_format("demo.m4a", "audio/mp4") == "m4a"


@pytest.mark.parametrize(
    ("filename", "mime_type"),
    [
        ("demo.mp3", "audio/wav"),
        ("demo.wav", "audio/mp4"),
        ("demo.m4a", "audio/wav"),
    ],
)
def test_audio_ingest_format_rejects_invalid_files(filename, mime_type):
    with pytest.raises(HTTPException) as exc_info:
        api_media._audio_ingest_format(filename, mime_type)

    assert exc_info.value.status_code == 415
    assert (
        exc_info.value.detail == "Only MP3, WAV, or M4A audio files are supported"
    )


def test_default_audio_content_type_prefers_mp3_metadata():
    assert (
        api_media._default_audio_content_type(
            ingest_format="mp3",
            original_filename="demo.wav",
            original_object_path="media/source/audio/demo.wav",
        )
        == "audio/mpeg"
    )


def test_default_audio_content_type_prefers_m4a_metadata():
    assert (
        api_media._default_audio_content_type(
            ingest_format="m4a",
            original_filename="demo.wav",
            original_object_path="media/source/audio/demo.wav",
        )
        == "audio/m4a"
    )


def test_default_audio_content_type_falls_back_to_wav():
    assert (
        api_media._default_audio_content_type(
            ingest_format=None,
            original_filename=None,
            original_object_path="media/source/audio/demo.wav",
        )
        == "audio/wav"
    )


def test_canonical_lesson_audio_source_path_requires_course_and_lesson_prefix():
    assert api_media._is_canonical_lesson_audio_source_path(
        "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav",
        course_id="course-1",
        lesson_id="lesson-1",
    )
    assert not api_media._is_canonical_lesson_audio_source_path(
        "courses/course-1/audio/demo.wav",
        course_id="course-1",
        lesson_id="lesson-1",
    )


def test_media_resolver_allows_only_derived_audio_paths_for_lesson_playback():
    assert media_resolver.is_derived_audio_path(
        "media/derived/audio/courses/course-1/lessons/lesson-1/demo.mp3"
    )
    assert not media_resolver.is_derived_audio_path(
        "courses/course-1/lessons/lesson-1/demo.mp3"
    )


def test_media_resolver_detects_direct_home_mp3_paths():
    assert media_resolver.is_direct_home_mp3_path(
        "home-player/teacher-1/demo.mp3",
        content_type="audio/mpeg",
    )
    assert media_resolver.is_direct_home_mp3_path(
        "course-media/home-player/teacher-1/demo.mp3",
        storage_bucket="course-media",
        content_type="audio/mpeg",
    )
    assert not media_resolver.is_direct_home_mp3_path(
        "home-player/teacher-1/demo.mp3",
        content_type="audio/wav",
    )
    assert not media_resolver.is_direct_home_mp3_path(
        "media/derived/audio/home-player/teacher-1/demo.mp3",
        content_type="audio/mpeg",
    )


def test_media_paths_validate_new_upload_object_path_enforces_allowlist():
    assert (
        media_paths.validate_new_upload_object_path(
            "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav"
        )
        == "media/source/audio/courses/course-1/lessons/lesson-1/demo.wav"
    )
    with pytest.raises(ValueError):
        media_paths.validate_new_upload_object_path("avatars/teacher/demo.png")


def test_media_paths_build_lesson_passthrough_object_path_uses_allowed_prefixes():
    image_path = media_paths.build_lesson_passthrough_object_path(
        course_id="course-1",
        lesson_id="lesson-1",
        media_kind="image",
        filename="diagram.png",
    )
    assert image_path.startswith("lessons/lesson-1/images/")

    video_path = media_paths.build_lesson_passthrough_object_path(
        course_id="course-1",
        lesson_id="lesson-1",
        media_kind="video",
        filename="demo.mp4",
    )
    assert video_path.startswith("courses/course-1/lessons/lesson-1/video/")

    pdf_path = media_paths.build_lesson_passthrough_object_path(
        course_id="course-1",
        lesson_id="lesson-1",
        media_kind="pdf",
        filename="guide.pdf",
    )
    assert pdf_path.startswith("courses/course-1/lessons/lesson-1/documents/")


def test_upload_detect_kind_uses_pdf_for_application_pdf():
    assert upload_routes._detect_kind("application/pdf") == "pdf"


def test_asset_media_type_maps_pdf_kind_to_document_asset():
    assert upload_routes._asset_media_type("pdf") == "document"
