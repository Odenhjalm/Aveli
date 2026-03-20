from scripts.scan_legacy_markdown_media_refs import (
    derive_public_storage_path_candidates,
    extract_legacy_markdown_image_refs,
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
