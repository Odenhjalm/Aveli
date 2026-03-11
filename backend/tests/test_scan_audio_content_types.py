from __future__ import annotations

from scripts import scan_audio_content_types as scan
from app.utils.audio_content_types import (
    audio_content_type_from_path,
    resolve_runtime_audio_content_type,
)


class _FakeCursor:
    def __init__(self) -> None:
        self.executed: list[tuple[str, tuple[object, ...]]] = []
        self.rowcount = 0

    def __enter__(self) -> _FakeCursor:
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        return False

    def execute(self, query: str, params: tuple[object, ...]) -> None:
        self.executed.append((" ".join(query.split()), params))
        self.rowcount = 1


class _FakeConnection:
    def __init__(self) -> None:
        self.cursor_instance = _FakeCursor()
        self.commit_calls = 0

    def cursor(self) -> _FakeCursor:
        return self.cursor_instance

    def commit(self) -> None:
        self.commit_calls += 1


def _row(
    *,
    source_table: str,
    media_row_id: str,
    content_type: str | None,
    storage_path: str | None,
    lesson_id: str | None = "lesson-1",
    title: str | None = "Audio title",
    kind: str | None = "audio",
    storage_bucket: str | None = "course-media",
) -> scan.AudioContentRow:
    return scan.AudioContentRow(
        source_table=source_table,
        media_row_id=media_row_id,
        lesson_id=lesson_id,
        title=title,
        kind=kind,
        content_type=content_type,
        storage_bucket=storage_bucket,
        storage_path=storage_path,
    )


def test_audio_content_type_mapping_from_extension():
    assert audio_content_type_from_path("lesson/demo.MP3") == "audio/mpeg"
    assert audio_content_type_from_path("lesson/demo.wave") == "audio/wav"
    assert audio_content_type_from_path("lesson/demo.opus") == "audio/ogg"
    assert audio_content_type_from_path("lesson/demo.txt") is None


def test_build_scan_report_dry_run_flags_expected_issues():
    report = scan.build_scan_report(
        [
            _row(
                source_table="app.media_objects",
                media_row_id="obj-missing",
                content_type=None,
                storage_path="lesson/demo.mp3",
            ),
            _row(
                source_table="app.media_objects",
                media_row_id="obj-binary",
                content_type="application/octet-stream",
                storage_path="lesson/demo.ogg",
            ),
            _row(
                source_table="app.media_assets",
                media_row_id="asset-unsupported",
                content_type="audio/x-wav",
                storage_path="media/source/audio/demo.wav",
            ),
            _row(
                source_table="app.media_objects",
                media_row_id="obj-mismatch",
                content_type="audio/wav",
                storage_path="lesson/demo.mp3",
            ),
            _row(
                source_table="app.lesson_media",
                media_row_id="lm-direct",
                content_type=None,
                storage_path="lesson/direct.mp3",
            ),
        ]
    )

    issues_by_id = {issue.media_row_id: issue for issue in report.issues}

    assert report.summary == {
        "total_audio_rows": 5,
        "rows_with_issues": 5,
        "missing_content_type": 2,
        "non_audio_content_type": 1,
        "suspicious_extension_mismatch": 1,
        "unsupported_audio_content_type": 1,
        "safe_auto_fix_rows": 2,
        "manual_review_rows": 3,
    }
    assert issues_by_id["obj-missing"].issue_type == "missing_content_type"
    assert issues_by_id["obj-missing"].proposed_content_type == "audio/mpeg"
    assert issues_by_id["obj-missing"].can_apply is True
    assert issues_by_id["obj-binary"].issue_type == "non_audio_content_type"
    assert issues_by_id["obj-binary"].proposed_content_type == "audio/ogg"
    assert issues_by_id["asset-unsupported"].issue_type == "unsupported_audio_content_type"
    assert issues_by_id["asset-unsupported"].can_apply is False
    assert issues_by_id["obj-mismatch"].issue_type == "suspicious_extension_mismatch"
    assert issues_by_id["obj-mismatch"].can_apply is False
    assert issues_by_id["lm-direct"].issue_type == "missing_content_type"
    assert issues_by_id["lm-direct"].can_apply is False


def test_apply_updates_only_changes_safe_cases():
    report = scan.build_scan_report(
        [
            _row(
                source_table="app.media_objects",
                media_row_id="obj-safe",
                content_type="application/octet-stream",
                storage_path="lesson/demo.mp3",
            ),
            _row(
                source_table="app.media_assets",
                media_row_id="asset-safe",
                content_type=None,
                storage_path="media/source/audio/demo.m4a",
            ),
            _row(
                source_table="app.media_objects",
                media_row_id="obj-unsafe",
                content_type="audio/wav",
                storage_path="lesson/demo.mp3",
            ),
        ]
    )
    conn = _FakeConnection()

    updated = scan.apply_updates(conn, report.updates)

    assert updated == 2
    assert conn.commit_calls == 1
    assert conn.cursor_instance.executed == [
        (
            "UPDATE app.media_objects SET content_type = %s, updated_at = now() WHERE id = %s",
            ("audio/mpeg", "obj-safe"),
        ),
        (
            "UPDATE app.media_assets SET original_content_type = %s, updated_at = now() WHERE id = %s",
            ("audio/mp4", "asset-safe"),
        ),
    ]


def test_conflicting_audio_rows_are_not_auto_updated():
    report = scan.build_scan_report(
        [
            _row(
                source_table="app.media_objects",
                media_row_id="obj-contradiction",
                content_type="audio/wav",
                storage_path="lesson/demo.mp3",
            ),
            _row(
                source_table="app.media_assets",
                media_row_id="asset-unsupported",
                content_type="audio/x-wav",
                storage_path="media/source/audio/demo.wav",
            ),
            _row(
                source_table="app.media_objects",
                media_row_id="obj-unclear",
                content_type="application/octet-stream",
                storage_path="lesson/demo",
            ),
        ]
    )

    assert report.updates == []
    assert report.summary["safe_auto_fix_rows"] == 0
    assert report.summary["manual_review_rows"] == 3


def test_runtime_audio_fallback_only_applies_to_missing_or_generic_audio_types():
    assert (
        resolve_runtime_audio_content_type(
            kind="audio",
            content_type=None,
            storage_path="lesson/demo.mp3",
        )
        == "audio/mpeg"
    )
    assert (
        resolve_runtime_audio_content_type(
            kind="audio",
            content_type="application/octet-stream",
            storage_path="lesson/demo.ogg",
        )
        == "audio/ogg"
    )
    assert (
        resolve_runtime_audio_content_type(
            kind="audio",
            content_type="image/png",
            storage_path="lesson/demo.mp3",
        )
        == "image/png"
    )
    assert (
        resolve_runtime_audio_content_type(
            kind="video",
            content_type=None,
            storage_path="lesson/demo.mp3",
        )
        is None
    )
