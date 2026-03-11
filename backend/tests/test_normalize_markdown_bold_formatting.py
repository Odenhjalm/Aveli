from scripts.normalize_markdown_bold_formatting import normalize_lesson_markdown


def test_normalize_lesson_markdown_fixes_escaped_bold():
    normalized, issues = normalize_lesson_markdown(r"Use \*\*text\*\* here.")

    assert normalized == "Use **text** here."
    assert {issue.issue_type for issue in issues} == {"escaped_bold"}


def test_normalize_lesson_markdown_fixes_nested_escaped_bold():
    normalized, issues = normalize_lesson_markdown("****text****")

    assert normalized == "**text**"
    assert {issue.issue_type for issue in issues} == {"escaped_bold"}


def test_normalize_lesson_markdown_fixes_unbalanced_bold():
    opening_fixed, opening_issues = normalize_lesson_markdown("**text")
    closing_fixed, closing_issues = normalize_lesson_markdown("text**")

    assert opening_fixed == "**text**"
    assert closing_fixed == "**text**"
    assert {issue.issue_type for issue in opening_issues} == {"unbalanced_bold"}
    assert {issue.issue_type for issue in closing_issues} == {"unbalanced_bold"}


def test_normalize_lesson_markdown_fixes_whitespace_bold():
    normalized, issues = normalize_lesson_markdown("**Tips: **")

    assert normalized == "**Tips:**"
    assert {issue.issue_type for issue in issues} == {"whitespace_bold"}


def test_normalize_lesson_markdown_is_idempotent():
    first_pass, first_issues = normalize_lesson_markdown(r"\*\*\*\* text \*\*\*\*")
    second_pass, second_issues = normalize_lesson_markdown(first_pass)

    assert first_pass == "**text**"
    assert {issue.issue_type for issue in first_issues} == {"escaped_bold", "whitespace_bold"}
    assert second_pass == first_pass
    assert second_issues == ()


def test_normalize_lesson_markdown_collapses_escaped_bold_inside_existing_bold():
    normalized, issues = normalize_lesson_markdown(r"**\*\* Energi och symbolik\*\***")

    assert normalized == "**Energi och symbolik**"
    assert {issue.issue_type for issue in issues} == {"escaped_bold", "whitespace_bold"}
    escaped_issue = next(issue for issue in issues if issue.issue_type == "escaped_bold")
    assert escaped_issue.after_snippet == "** Energi och symbolik**"


def test_normalize_lesson_markdown_ignores_code_blocks():
    source = "```\n\\*\\*text\\*\\*\n**Tips: **\n```\n\n`\\*\\*inline\\*\\*`"

    normalized, issues = normalize_lesson_markdown(source)

    assert normalized == source
    assert issues == ()


def test_normalize_lesson_markdown_ignores_links_images_and_media_tokens():
    source = (
        "[**Tips: **](https://example.com)\n"
        "![](https://example.com/image.png)\n"
        "!video(test123)\n"
        "!audio(test123)\n"
        "!image(test123)"
    )

    normalized, issues = normalize_lesson_markdown(source)

    assert normalized == source
    assert issues == ()
