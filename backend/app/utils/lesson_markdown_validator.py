from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

_BACKEND_DIR = Path(__file__).resolve().parents[2]
_FRONTEND_DIR = _BACKEND_DIR.parent / "frontend"
_ROUNDTRIP_HARNESS = _FRONTEND_DIR / "tool" / "lesson_markdown_roundtrip_harness_test.dart"
_ROUNDTRIP_TEST_NAME = "lesson markdown roundtrip harness"
_ROUNDTRIP_TIMEOUT_SECONDS = 30.0

_HEADING_BLANK_LINES_PATTERN = re.compile(r"(?m)^(#{1,6}[^\n]*)\n{2,}(?=\S)")
_LIST_BLANK_LINES_PATTERN = re.compile(r"\n{2,}(?=(?:[-*+] |\d+\. ))")
_NON_EMPHASIS_ESCAPE_PATTERN = re.compile(r"\\([!().\-\[\]])")


class LessonMarkdownValidationRuntimeError(RuntimeError):
    def __init__(self, message: str, *, reason: str = "runtime_error") -> None:
        super().__init__(message)
        self.reason = str(reason or "runtime_error")


@dataclass(frozen=True)
class LessonMarkdownValidationResult:
    ok: bool
    canonical_markdown: str
    failure_reason: str | None
    error: str | None = None


def validate_lesson_markdown(markdown: str) -> LessonMarkdownValidationResult:
    return _validate_lesson_markdown_cached(str(markdown or ""))


@lru_cache(maxsize=256)
def _validate_lesson_markdown_cached(markdown: str) -> LessonMarkdownValidationResult:
    canonical_markdown = _normalize_roundtrip_markdown(_run_roundtrip(markdown))
    ok = _normalize_markdown_for_comparison(
        markdown,
    ) == _normalize_markdown_for_comparison(canonical_markdown)
    return LessonMarkdownValidationResult(
        ok=ok,
        canonical_markdown=canonical_markdown,
        failure_reason=None if ok else "markdownRoundTripMismatch",
    )


def _normalize_markdown_for_comparison(markdown: str) -> str:
    normalized = markdown.replace("\r\n", "\n").replace("\r", "\n")
    normalized = "\n".join(line.rstrip() for line in normalized.split("\n"))
    normalized = _normalize_roundtrip_markdown(normalized)
    normalized = normalized.rstrip("\n")
    normalized = re.sub(r"\n{3,}", "\n\n", normalized)
    normalized = _HEADING_BLANK_LINES_PATTERN.sub(r"\1\n", normalized)
    normalized = _LIST_BLANK_LINES_PATTERN.sub("\n", normalized)
    return normalized


def _normalize_roundtrip_markdown(markdown: str) -> str:
    return _NON_EMPHASIS_ESCAPE_PATTERN.sub(r"\1", markdown)


def _run_roundtrip(markdown: str) -> str:
    executable = shutil.which("flutter")
    if not executable:
        raise LessonMarkdownValidationRuntimeError(
            "Flutter executable not found for lesson markdown validation",
            reason="missing_runtime",
        )
    if not _FRONTEND_DIR.exists():
        raise LessonMarkdownValidationRuntimeError(
            f"Frontend directory not found: {_FRONTEND_DIR}",
            reason="missing_runtime",
        )
    if not _ROUNDTRIP_HARNESS.exists():
        raise LessonMarkdownValidationRuntimeError(
            f"Round-trip harness not found: {_ROUNDTRIP_HARNESS}",
            reason="missing_runtime",
        )

    payload = json.dumps(
        {"items": [{"lesson_id": "server-validator", "markdown": markdown}]},
    )
    input_handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="\n",
        suffix=".json",
        delete=False,
    )
    output_handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="\n",
        suffix=".json",
        delete=False,
    )
    input_path = Path(input_handle.name)
    output_path = Path(output_handle.name)

    try:
        with input_handle:
            input_handle.write(payload)
        with output_handle:
            output_handle.write("")

        env = os.environ.copy()
        env["LESSON_MARKDOWN_INPUT_PATH"] = str(input_path)
        env["LESSON_MARKDOWN_OUTPUT_PATH"] = str(output_path)

        try:
            completed = subprocess.run(
                [
                    executable,
                    "test",
                    "tool/lesson_markdown_roundtrip_harness_test.dart",
                    "--plain-name",
                    _ROUNDTRIP_TEST_NAME,
                ],
                cwd=_FRONTEND_DIR,
                env=env,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
                timeout=_ROUNDTRIP_TIMEOUT_SECONDS,
            )
        except subprocess.TimeoutExpired as exc:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper timed out "
                f"after {_ROUNDTRIP_TIMEOUT_SECONDS:g}s",
                reason="timeout",
            ) from exc
        except OSError as exc:
            raise LessonMarkdownValidationRuntimeError(
                f"Lesson markdown round-trip helper could not start: {exc}",
                reason="subprocess_error",
            ) from exc
        if completed.returncode != 0:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper failed.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}",
                reason="subprocess_error",
            )

        raw_output = output_path.read_text(encoding="utf-8")
        if not raw_output.strip():
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper produced no output.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}",
                reason="subprocess_error",
            )

        decoded = json.loads(raw_output)
        raw_results = decoded.get("results")
        if not isinstance(raw_results, list) or len(raw_results) != 1:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned invalid JSON",
                reason="subprocess_error",
            )
        result = raw_results[0]
        if not isinstance(result, dict):
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned invalid item payload",
                reason="subprocess_error",
            )
        error = result.get("error")
        if error is not None:
            raise LessonMarkdownValidationRuntimeError(
                f"Lesson markdown round-trip helper failed to parse markdown: {error}",
                reason="subprocess_error",
            )
        canonical_markdown = result.get("canonical_markdown")
        if canonical_markdown is None:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned no canonical markdown",
                reason="subprocess_error",
            )
        return str(canonical_markdown)
    finally:
        input_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)
