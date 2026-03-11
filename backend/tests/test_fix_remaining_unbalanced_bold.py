from scripts.fix_remaining_unbalanced_bold import normalize_remaining_unbalanced_bold
from scripts.scan_markdown_integrity import scan_markdown_content


def test_normalize_remaining_unbalanced_bold_repairs_trailing_repeated_stars():
    normalized = normalize_remaining_unbalanced_bold("text****")
    _, issues = scan_markdown_content(normalized)

    assert normalized == "**text**"
    assert "unbalanced_bold" not in {issue_type for issue_type, _ in issues}


def test_normalize_remaining_unbalanced_bold_caps_existing_bold_at_two_stars():
    normalized = normalize_remaining_unbalanced_bold("**text****")
    _, issues = scan_markdown_content(normalized)

    assert normalized == "**text**"
    assert "unbalanced_bold" not in {issue_type for issue_type, _ in issues}


def test_normalize_remaining_unbalanced_bold_removes_empty_whitespace_bold():
    normalized = normalize_remaining_unbalanced_bold("_** **")
    _, issues = scan_markdown_content(normalized)

    assert normalized == "_"
    assert "unbalanced_bold" not in {issue_type for issue_type, _ in issues}


def test_normalize_remaining_unbalanced_bold_is_idempotent():
    first_pass = normalize_remaining_unbalanced_bold("****text****")
    second_pass = normalize_remaining_unbalanced_bold(first_pass)

    assert first_pass == "**text**"
    assert second_pass == first_pass


def test_normalize_remaining_unbalanced_bold_ignores_protected_markdown():
    source = (
        "```\ntext****\n```\n"
        "`text****`\n"
        "[text****](https://example.com)\n"
        "![](https://example.com/image.png)\n"
        "!video(test123)\n"
        "!audio(test123)\n"
        "!image(test123)"
    )

    normalized = normalize_remaining_unbalanced_bold(source)

    assert normalized == source
