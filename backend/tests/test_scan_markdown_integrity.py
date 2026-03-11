from scripts.scan_markdown_integrity import scan_markdown_content


def test_scan_markdown_content_detects_escaped_bold():
    has_bold, issues = scan_markdown_content(r"Use \*\*bold\*\* markers later.")

    assert has_bold is True
    assert issues == (("escaped_bold", 4),)


def test_scan_markdown_content_detects_html_bold():
    has_bold, issues = scan_markdown_content("Intro <strong>bold</strong> outro")

    assert has_bold is True
    assert issues == (("html_bold", 6),)


def test_scan_markdown_content_detects_unbalanced_bold():
    has_bold, issues = scan_markdown_content("Broken **bold marker")

    assert has_bold is True
    assert issues == (("unbalanced_bold", 7),)


def test_scan_markdown_content_flags_nested_bold_as_unbalanced():
    has_bold, issues = scan_markdown_content("Broken **outer **inner** text** marker")

    assert has_bold is True
    assert issues == (("unbalanced_bold", 15),)


def test_scan_markdown_content_ignores_valid_bold_inside_code():
    has_bold, issues = scan_markdown_content("`**not bold**` and **real bold**")

    assert has_bold is True
    assert issues == ()
