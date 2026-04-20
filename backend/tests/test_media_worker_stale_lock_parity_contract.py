from __future__ import annotations

from pathlib import Path

from app.repositories import media_assets as media_assets_repo
from backend.bootstrap import baseline_v2


def _compact(source: str) -> str:
    return " ".join(source.split())


def _v2_slot_text(filename: str) -> str:
    for path in baseline_v2._slot_paths():
        if path.name == filename:
            return path.read_text(encoding="utf-8")
    raise AssertionError(f"Baseline V2 lock does not contain {filename}")


def test_fetch_lock_and_stale_release_media_class_filters_are_aligned() -> None:
    fetch_source = _compact(
        Path(media_assets_repo.__file__).read_text(encoding="utf-8")
    )
    release_source = _compact(
        _v2_slot_text("V2_0019_media_worker_stale_lock_release_parity.sql")
    )

    required_fragments = [
        "media_type = 'audio'::app.media_type",
        "'course_cover'::app.media_purpose",
        "'profile_media'::app.media_purpose",
        "'lesson_media'::app.media_purpose",
        "'video'::app.media_type",
        "'document'::app.media_type",
        "and purpose = 'lesson_media'::app.media_purpose",
    ]

    for fragment in required_fragments:
        assert fragment in fetch_source
        assert fragment in release_source

    assert "'home_player_audio'::app.media_purpose" not in release_source


def test_stale_release_slot_does_not_introduce_states_or_format_rules() -> None:
    release_source = _compact(
        _v2_slot_text("V2_0019_media_worker_stale_lock_release_parity.sql")
    )

    assert "create type app.media_state" not in release_source.lower()
    assert "alter type app.media_state" not in release_source.lower()
    assert "'pending_upload'::app.media_state" not in release_source
    assert "'uploaded'::app.media_state" not in release_source
    assert "'ready'::app.media_state" not in release_source
    assert "'failed'::app.media_state" not in release_source
    assert release_source.count("'processing'::app.media_state") == 1
    assert "playback_format" not in release_source
    assert "ingest_format" not in release_source
