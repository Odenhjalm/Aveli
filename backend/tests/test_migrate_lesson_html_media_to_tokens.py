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


def test_normalize_lesson_markdown_removes_unresolved_html_media():
    normalized, warnings = normalize_lesson_markdown(
        '<video src="https://cdn.test/legacy.mp4"></video>'
    )

    assert normalized == ""
    assert warnings
