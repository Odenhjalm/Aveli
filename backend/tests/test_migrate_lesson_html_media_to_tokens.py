from scripts.migrate_lesson_html_media_to_tokens import normalize_lesson_markdown


def test_normalize_lesson_markdown_converts_video_html_to_token():
    normalized, warnings = normalize_lesson_markdown(
        '<video src="/studio/media/test123"></video>'
    )

    assert normalized == "!video(test123)"
    assert warnings == ()


def test_normalize_lesson_markdown_is_idempotent_for_existing_token():
    normalized, warnings = normalize_lesson_markdown("!video(test123)")

    assert normalized == "!video(test123)"
    assert warnings == ()


def test_normalize_lesson_markdown_converts_html_img_to_markdown_image():
    source = '<img src="https://project.supabase.co/storage/v1/object/public/course/image.png">'

    normalized, warnings = normalize_lesson_markdown(source)

    assert (
        normalized
        == "![](https://project.supabase.co/storage/v1/object/public/course/image.png)"
    )
    assert warnings == (
        "Converted HTML image → Markdown image: "
        'before: <img src="https://project.supabase.co/storage/v1/object/public/course/image.png"> '
        "after: ![](https://project.supabase.co/storage/v1/object/public/course/image.png)",
    )


def test_normalize_lesson_markdown_converts_lesson_media_html_img_to_token():
    normalized, warnings = normalize_lesson_markdown('<img src="/studio/media/abc123">')

    assert normalized == "!image(abc123)"
    assert warnings == (
        'Converted HTML image → Markdown image: before: <img src="/studio/media/abc123"> '
        "after: !image(abc123)",
    )


def test_normalize_lesson_markdown_is_idempotent_for_converted_markdown_image():
    source = '<img src="https://project.supabase.co/storage/v1/object/public/course/image.png">'

    normalized, warnings = normalize_lesson_markdown(source)
    rerun_normalized, rerun_warnings = normalize_lesson_markdown(normalized)

    assert (
        normalized
        == "![](https://project.supabase.co/storage/v1/object/public/course/image.png)"
    )
    assert warnings
    assert rerun_normalized == normalized
    assert rerun_warnings == ()


def test_normalize_lesson_markdown_removes_unresolved_html_video():
    normalized, warnings = normalize_lesson_markdown(
        '<video src="https://cdn.test/legacy.mp4"></video>'
    )

    assert normalized == ""
    assert warnings
