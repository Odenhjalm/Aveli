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
