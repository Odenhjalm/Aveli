from app.utils import lesson_markdown_validator


def test_validator_accepts_canonical_emphasis_markdown():
    result = lesson_markdown_validator.validate_lesson_markdown(
        "This is plain, *italic*, and **bold**.",
    )

    assert result.ok is True
    assert result.failure_reason is None
    assert result.canonical_markdown == "This is plain, *italic*, and **bold**."


def test_validator_rejects_malformed_emphasis_markdown():
    result = lesson_markdown_validator.validate_lesson_markdown(
        r"This is plain, \*italic\*, and **bold**.",
    )

    assert result.ok is False
    assert result.failure_reason == "markdownRoundTripMismatch"
    assert result.canonical_markdown == "This is plain, *italic*, and **bold**."


def test_validator_accepts_canonical_two_paragraph_fixture():
    result = lesson_markdown_validator.validate_lesson_markdown(
        "Hello world\n\nThis is a lesson",
    )

    assert result.ok is True
    assert result.failure_reason is None
    assert result.canonical_markdown == "Hello world\n\nThis is a lesson"


def test_validator_accepts_block_spacing_normalization():
    result = lesson_markdown_validator.validate_lesson_markdown(
        "## Heading\n\n\nBody",
    )

    assert result.ok is True
    assert result.failure_reason is None
    assert result.canonical_markdown == "## Heading\nBody"


def test_validator_accepts_canonical_heading3_bold_italic_tail():
    result = lesson_markdown_validator.validate_lesson_markdown(
        "### Heading3\n**Bold** *Italic*",
    )

    assert result.ok is True
    assert result.failure_reason is None
    assert result.canonical_markdown == "### Heading3\n**Bold** *Italic*"


def test_validator_accepts_canonical_inline_document_fixture():
    result = lesson_markdown_validator.validate_lesson_markdown(
        "Intro\n\n!document(media-document-1)\n\nOutro",
    )

    assert result.ok is True
    assert result.failure_reason is None
    assert result.canonical_markdown == "Intro\n\n!document(media-document-1)\n\nOutro"
