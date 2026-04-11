from __future__ import annotations

import inspect
from pathlib import Path

from app.config import settings
from app.services import media_cleanup


def test_course_cover_prune_deletes_only_unreferenced_cover_assets() -> None:
    source = inspect.getsource(media_cleanup.prune_course_cover_assets)

    assert "DELETE FROM app.media_assets" in source
    assert "ma.purpose = 'course_cover'" in source
    assert "ma.original_object_path LIKE" in source
    assert "SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id" in source
    assert "SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id" in source
    assert "FOR UPDATE SKIP LOCKED" in source


def test_media_asset_cleanup_uses_canonical_media_asset_columns() -> None:
    source = Path(media_cleanup.__file__).read_text(encoding="utf-8")

    assert "streaming_" not in source
    assert "ma.storage_bucket" not in source
    assert "ma.course_id" not in source
    assert "ma.created_at" not in source
    assert "ma.original_object_path" in source
    assert "ma.ingest_format" in source
    assert "ma.playback_object_path" in source
    assert "ma.playback_format" in source
    assert "ma.state::text as state" in source


def test_media_asset_delete_targets_use_explicit_original_and_playback_identity() -> None:
    targets = media_cleanup._asset_delete_targets(
        {
            "media_type": "image",
            "purpose": "course_cover",
            "original_object_path": "media/source/cover/courses/course-1/source.png",
            "playback_object_path": "media/derived/cover/courses/course-1/cover.jpg",
        }
    )

    assert (
        settings.media_source_bucket,
        "media/source/cover/courses/course-1/source.png",
    ) in targets
    assert (
        settings.media_public_bucket,
        "media/derived/cover/courses/course-1/cover.jpg",
    ) in targets
    assert len(targets) == 2


def test_delete_media_asset_double_checks_references_before_storage_cleanup() -> None:
    source = inspect.getsource(media_cleanup.delete_media_asset_and_objects)

    assert "DELETE FROM app.media_assets" in source
    assert "SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id" in source
    assert "SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id" in source
    assert (
        "SELECT 1 FROM app.home_player_uploads hpu WHERE hpu.media_asset_id = ma.id"
        in source
    )
    assert source.index("if not row:") < source.index("_delete_storage_targets")


def test_storage_cleanup_preserves_shared_or_lesson_scoped_storage() -> None:
    source = inspect.getsource(media_cleanup._should_skip_storage_delete)

    assert "_shared_storage_reference_counts" in source
    assert "lesson_storage_prefix" in source
    assert 'reference_counts["media_objects"] > 0' in source
    assert 'reference_counts["lesson_media"] > 0' in source


def test_media_asset_deletion_sql_is_confined_to_lifecycle_layer() -> None:
    app_dir = Path(__file__).resolve().parents[1] / "app"
    offenders: list[str] = []

    for path in app_dir.rglob("*.py"):
        if path.name == "media_cleanup.py":
            continue
        source = path.read_text(encoding="utf-8")
        if "delete from app.media_assets" in source.lower():
            offenders.append(str(path.relative_to(app_dir)))

    assert offenders == []


def test_routes_do_not_run_synchronous_media_asset_cleanup() -> None:
    source = (Path(__file__).resolve().parents[1] / "app" / "routes" / "studio.py").read_text(
        encoding="utf-8"
    )

    assert "delete_media_asset_and_objects(" not in source
    assert "request_lifecycle_evaluation(" in source
