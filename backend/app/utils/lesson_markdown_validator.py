from __future__ import annotations

import json
import os
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


def _clean_subprocess_output(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = str(value).replace("\r\n", "\n").replace("\r", "\n").strip()
    return cleaned or None


class LessonMarkdownValidationRuntimeError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        reason: str = "runtime_error",
        subprocess_error: str | None = None,
        stdout_output: str | None = None,
        stderr_output: str | None = None,
    ) -> None:
        super().__init__(message)
        self.reason = str(reason or "runtime_error")
        self.subprocess_error = _clean_subprocess_output(subprocess_error)
        self.stdout_output = _clean_subprocess_output(stdout_output)
        self.stderr_output = _clean_subprocess_output(stderr_output)


@dataclass(frozen=True)
class LessonMarkdownValidationResult:
    ok: bool
    canonical_markdown: str
    failure_reason: str | None
    error: str | None = None


@dataclass(frozen=True)
class LessonMarkdownRoundTripResult:
    canonical_markdown: str
    input_comparison_markdown: str
    canonical_comparison_markdown: str
    plain_text: str | None


def validate_lesson_markdown(markdown: str) -> LessonMarkdownValidationResult:
    return _validate_lesson_markdown_cached(str(markdown or ""))


@lru_cache(maxsize=256)
def _validate_lesson_markdown_cached(markdown: str) -> LessonMarkdownValidationResult:
    roundtrip = _run_roundtrip(markdown)
    ok = roundtrip.input_comparison_markdown == roundtrip.canonical_comparison_markdown
    return LessonMarkdownValidationResult(
        ok=ok,
        canonical_markdown=roundtrip.canonical_comparison_markdown,
        failure_reason=None if ok else "markdownRoundTripMismatch",
    )


def _run_roundtrip(markdown: str) -> LessonMarkdownRoundTripResult:
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
                subprocess_error=f"timed out after {_ROUNDTRIP_TIMEOUT_SECONDS:g}s",
                stdout_output=getattr(exc, "stdout", None),
                stderr_output=getattr(exc, "stderr", None),
            ) from exc
        except OSError as exc:
            raise LessonMarkdownValidationRuntimeError(
                f"Lesson markdown round-trip helper could not start: {exc}",
                reason="subprocess_error",
                subprocess_error=str(exc),
            ) from exc
        if completed.returncode != 0:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper failed.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}",
                reason="subprocess_error",
                subprocess_error=f"returncode={completed.returncode}",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )

        raw_output = output_path.read_text(encoding="utf-8")
        if not raw_output.strip():
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper produced no output.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}",
                reason="subprocess_error",
                subprocess_error="empty_output",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )

        decoded = json.loads(raw_output)
        raw_results = decoded.get("results")
        if not isinstance(raw_results, list) or len(raw_results) != 1:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned invalid JSON",
                reason="subprocess_error",
                subprocess_error="invalid_json",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        result = raw_results[0]
        if not isinstance(result, dict):
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned invalid item payload",
                reason="subprocess_error",
                subprocess_error="invalid_item_payload",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        error = result.get("error")
        if error is not None:
            raise LessonMarkdownValidationRuntimeError(
                f"Lesson markdown round-trip helper failed to parse markdown: {error}",
                reason="subprocess_error",
                subprocess_error=str(error),
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        canonical_markdown = result.get("canonical_markdown")
        if canonical_markdown is None:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned no canonical markdown",
                reason="subprocess_error",
                subprocess_error="missing_canonical_markdown",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        input_comparison_markdown = result.get("input_comparison_markdown")
        if input_comparison_markdown is None:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned no input comparison markdown",
                reason="subprocess_error",
                subprocess_error="missing_input_comparison_markdown",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        canonical_comparison_markdown = result.get("canonical_comparison_markdown")
        if canonical_comparison_markdown is None:
            raise LessonMarkdownValidationRuntimeError(
                "Lesson markdown round-trip helper returned no canonical comparison markdown",
                reason="subprocess_error",
                subprocess_error="missing_canonical_comparison_markdown",
                stdout_output=completed.stdout,
                stderr_output=completed.stderr,
            )
        plain_text = result.get("plain_text")
        return LessonMarkdownRoundTripResult(
            canonical_markdown=str(canonical_markdown),
            input_comparison_markdown=str(input_comparison_markdown),
            canonical_comparison_markdown=str(canonical_comparison_markdown),
            plain_text=None if plain_text is None else str(plain_text),
        )
    finally:
        input_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)
