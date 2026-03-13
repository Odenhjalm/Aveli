import pytest
from fastapi import HTTPException

from app.routes import api_media


def test_audio_ingest_format_allows_wav_and_m4a():
    assert api_media._audio_ingest_format("demo.wav", "audio/wav") == "wav"
    assert api_media._audio_ingest_format("demo.wav", "audio/x-wav") == "wav"
    assert api_media._audio_ingest_format("demo.m4a", "audio/m4a") == "m4a"
    assert api_media._audio_ingest_format("demo.m4a", "audio/mp4") == "m4a"


@pytest.mark.parametrize(
    ("filename", "mime_type", "status_code"),
    [
        ("demo.mp3", "audio/mpeg", 400),
        ("demo.wav", "audio/mp4", 415),
        ("demo.m4a", "audio/wav", 415),
    ],
)
def test_audio_ingest_format_rejects_invalid_files(filename, mime_type, status_code):
    with pytest.raises(HTTPException) as exc_info:
        api_media._audio_ingest_format(filename, mime_type)

    assert exc_info.value.status_code == status_code
    assert exc_info.value.detail == "Only WAV or M4A audio files are supported"


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
