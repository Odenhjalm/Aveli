from __future__ import annotations

import inspect
from pathlib import Path

from app.config import settings
from app.services import media_cleanup


def _compact_sql(source: str) -> str:
    return " ".join(source.split())


def _profile_media_placement_guard(source: str) -> str:
    compact = _compact_sql(source)
    return (
        "SELECT 1 FROM app.profile_media_placements pmp "
        "WHERE pmp.media_asset_id = ma.id"
    ) in compact


def test_course_cover_prune_deletes_only_unreferenced_cover_assets() -> None:
    source = inspect.getsource(media_cleanup.prune_course_cover_assets)

    assert "DELETE FROM app.media_assets" in source
    assert "ma.purpose = 'course_cover'" in source
    assert "ma.original_object_path LIKE" in source
    assert "SELECT 1 FROM app.lesson_media lm WHERE lm.media_asset_id = ma.id" in source
    assert "SELECT 1 FROM app.courses c WHERE c.cover_media_id = ma.id" in source
    assert _profile_media_placement_guard(source)
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
    assert _profile_media_placement_guard(source)
    assert source.index("if not row:") < source.index("_delete_storage_targets")


def test_media_asset_orphan_cleanup_treats_profile_placements_as_references() -> None:
    cleanup_functions = [
        media_cleanup._delete_unreferenced_lesson_audio_assets,
        media_cleanup._delete_orphan_course_cover_assets_for_deleted_courses,
        media_cleanup.prune_course_cover_assets,
        media_cleanup.delete_course_cover_assets_for_course,
    ]

    for cleanup_function in cleanup_functions:
        source = inspect.getsource(cleanup_function)

        assert "DELETE FROM app.media_assets" in source
        assert _profile_media_placement_guard(source)
        assert source.index("profile_media_placements") < source.index(
            "DELETE FROM app.media_assets"
        )


def test_unreferenced_profile_media_asset_remains_cleanup_eligible() -> None:
    source = inspect.getsource(media_cleanup.delete_media_asset_and_objects)
    compact = _compact_sql(source)

    assert "DELETE FROM app.media_assets ma WHERE ma.id = %s" in compact
    assert "ma.purpose <> 'profile_media'" not in compact
    assert "ma.purpose != 'profile_media'" not in compact
    assert "RETURNING ma.id" in compact
    assert source.index("if not row:") < source.index("_delete_storage_targets")


def test_profile_media_cleanup_uses_source_table_not_projection_authority() -> None:
    source = inspect.getsource(media_cleanup.delete_media_asset_and_objects)

    assert _profile_media_placement_guard(source)
    assert "runtime_media" not in source
    assert "avatar_media_id" not in source
    assert "resolved_url" not in source
    assert "photo_url" not in source
    assert "profile_media_item_from_row" not in source


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
    source = (
        Path(__file__).resolve().parents[1] / "app" / "routes" / "studio.py"
    ).read_text(encoding="utf-8")

    assert "delete_media_asset_and_objects(" not in source
    assert "request_lifecycle_evaluation(" in source


def test_profile_media_delete_requests_lifecycle_after_binding_removal() -> None:
    source = (
        Path(__file__).resolve().parents[1] / "app" / "routes" / "studio.py"
    ).read_text(encoding="utf-8").replace("\r\n", "\n")
    start = source.index("async def studio_delete_profile_media")
    end = source.index('@router.post(\n    "/home-player/uploads"', start)
    function_source = source[start:end]

    assert "profile_media_repo.delete_teacher_profile_media" in function_source
    assert "media_cleanup.request_lifecycle_evaluation(" in function_source
    assert function_source.index(
        "profile_media_repo.delete_teacher_profile_media"
    ) < function_source.index("media_cleanup.request_lifecycle_evaluation(")
    assert (
        'media_asset_id = str(existing.get("media_asset_id") or "").strip()'
        in function_source
    )
    assert 'trigger_source="profile_media_delete"' in function_source
    assert 'subject_type="profile_media"' in function_source
    assert "profile_media_item_from_row" not in function_source
