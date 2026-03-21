from scripts.scan_legacy_markdown_media_refs import (
    ImportRecord,
    LessonImportResult,
    derive_public_storage_path_candidates,
    extract_legacy_markdown_image_refs,
    summarize_partial_salvage,
    _match_existing_lesson_media,
    _with_status,
    rewrite_markdown_with_image_tokens,
)


def test_derive_public_storage_path_candidates_handles_current_public_media_layout():
    candidates = derive_public_storage_path_candidates(
        "https://project.supabase.co/storage/v1/object/public/public-media/"
        "lessons/lesson-1/images/example.png"
    )

    assert candidates == ("lessons/lesson-1/images/example.png",)


def test_derive_public_storage_path_candidates_handles_legacy_uuid_lesson_variant():
    candidates = derive_public_storage_path_candidates(
        "https://project.supabase.co/storage/v1/object/public/public-media/"
        "teacher-123/lesson-1/image/example.png"
    )

    assert candidates == ("teacher-123/lesson-1/image/example.png",)


def test_derive_public_storage_path_candidates_handles_duplicated_public_bucket_prefix():
    candidates = derive_public_storage_path_candidates(
        "https://project.supabase.co/storage/v1/object/public/public-media/"
        "public-media/lessons/lesson-1/images/example.png"
    )

    assert candidates == (
        "lessons/lesson-1/images/example.png",
        "public-media/lessons/lesson-1/images/example.png",
    )


def test_rewrite_markdown_with_image_tokens_replaces_every_legacy_ref_in_order():
    markdown = (
        "Before\n"
        "![](https://project.supabase.co/storage/v1/object/public/public-media/lessons/"
        "lesson-1/images/first.png)\n"
        "Middle\n"
        "![](https://project.supabase.co/storage/v1/object/public/public-media/teacher-1/"
        "lesson-1/image/second.png)\n"
        "After"
    )
    refs = extract_legacy_markdown_image_refs(markdown)

    rewritten = rewrite_markdown_with_image_tokens(
        markdown,
        [
            (refs[0], "!image(media-1)"),
            (refs[1], "!image(media-2)"),
        ],
    )

    assert rewritten == "Before\n!image(media-1)\nMiddle\n!image(media-2)\nAfter"


def test_match_existing_lesson_media_prefers_media_asset_id_match():
    row = {
        "lesson_media_id": "lesson-media-1",
        "kind": "image",
        "media_asset_id": "asset-1",
        "lesson_storage_path": None,
        "lesson_storage_bucket": "public-media",
        "effective_storage_path": "lessons/lesson-1/images/current.png",
        "effective_storage_bucket": "public-media",
    }

    matched = _match_existing_lesson_media(
        [row],
        media_asset_id="asset-1",
        bucket="public-media",
        storage_path="lessons/lesson-1/images/other.png",
    )

    assert matched == row


def test_summarize_partial_salvage_counts_resolvable_and_missing_refs():
    results = [
        LessonImportResult(
            lesson_id="lesson-1",
            title="Lesson 1",
            status="planned",
            legacy_ref_count=2,
            converted_ref_count=2,
            created_media_assets=0,
            reused_media_assets=1,
            updated_media_assets=0,
            created_lesson_media=1,
            reused_lesson_media=0,
            records=(
                ImportRecord(
                    lesson_id="lesson-1",
                    title="Lesson 1",
                    raw_url="https://cdn.test/1.png",
                    storage_bucket="public-media",
                    storage_path="lessons/lesson-1/images/1.png",
                    media_asset_id="asset-1",
                    lesson_media_id="lm-1",
                    media_asset_action="reused_existing",
                    lesson_media_action="created_new",
                    replacement="!image(lm-1)",
                    status="planned",
                    classification="resolvable",
                ),
                ImportRecord(
                    lesson_id="lesson-1",
                    title="Lesson 1",
                    raw_url="https://cdn.test/2.png",
                    storage_bucket="public-media",
                    storage_path="lessons/lesson-1/images/2.png",
                    media_asset_id="asset-2",
                    lesson_media_id="lm-2",
                    media_asset_action="reused_existing",
                    lesson_media_action="created_new",
                    replacement="!image(lm-2)",
                    status="planned",
                    classification="resolvable",
                ),
            ),
        ),
        LessonImportResult(
            lesson_id="lesson-2",
            title="Lesson 2",
            status="planned",
            legacy_ref_count=2,
            converted_ref_count=1,
            created_media_assets=0,
            reused_media_assets=1,
            updated_media_assets=0,
            created_lesson_media=0,
            reused_lesson_media=1,
            records=(
                ImportRecord(
                    lesson_id="lesson-2",
                    title="Lesson 2",
                    raw_url="https://cdn.test/3.png",
                    storage_bucket="public-media",
                    storage_path="lessons/lesson-2/images/3.png",
                    media_asset_id="asset-3",
                    lesson_media_id="lm-3",
                    media_asset_action="reused_existing",
                    lesson_media_action="reused_existing",
                    replacement="!image(lm-3)",
                    status="planned",
                    classification="resolvable",
                ),
                ImportRecord(
                    lesson_id="lesson-2",
                    title="Lesson 2",
                    raw_url="https://cdn.test/missing.png",
                    storage_bucket=None,
                    storage_path=None,
                    media_asset_id=None,
                    lesson_media_id=None,
                    media_asset_action=None,
                    lesson_media_action=None,
                    replacement=None,
                    status="planned",
                    classification="missing",
                    error="media_asset_missing",
                ),
            ),
        ),
    ]

    assert summarize_partial_salvage(results) == {
        "lessons_processed": 2,
        "refs_total": 4,
        "resolvable_refs": 3,
        "missing_refs": 1,
        "would_convert": 3,
        "would_leave_untouched": 1,
        "lessons_fully_cleaned": 1,
        "lessons_still_blocked": 1,
        "remaining_raw_refs": 1,
    }


def test_with_status_preserves_record_error_when_not_overridden():
    pending = LessonImportResult(
        lesson_id="lesson-1",
        title="Lesson 1",
        status="pending",
        legacy_ref_count=1,
        converted_ref_count=0,
        created_media_assets=0,
        reused_media_assets=0,
        updated_media_assets=0,
        created_lesson_media=0,
        reused_lesson_media=0,
        records=(
            ImportRecord(
                lesson_id="lesson-1",
                title="Lesson 1",
                raw_url="https://cdn.test/missing.png",
                storage_bucket=None,
                storage_path=None,
                media_asset_id=None,
                lesson_media_id=None,
                media_asset_action=None,
                lesson_media_action=None,
                replacement=None,
                status="pending",
                classification="missing",
                error="media_asset_missing",
            ),
        ),
    )

    updated = _with_status(pending, status="planned")

    assert updated.status == "planned"
    assert updated.records[0].status == "planned"
    assert updated.records[0].classification == "missing"
    assert updated.records[0].error == "media_asset_missing"
