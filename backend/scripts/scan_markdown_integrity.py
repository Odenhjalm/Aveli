#!/usr/bin/env python3
r"""Audit lesson Markdown for bold-formatting integrity issues.

This script scans `app.lessons.content_markdown` and reports legacy or malformed
bold formatting without modifying any database rows.

Reported issue types:
* `escaped_bold` for literal `\*\*` markers
* `html_bold` for `<strong>` / `<b>` tags
* `unbalanced_bold` for unmatched or nested Markdown `**` delimiters
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import psycopg


_ESCAPED_BOLD_PATTERN = re.compile(r"""\\\*\\\*""")
_HTML_BOLD_PATTERN = re.compile(r"""<\s*(?:strong|b)\b[^>]*>""", re.IGNORECASE)
_UNESCAPED_BOLD_PATTERN = re.compile(r"""(?<!\\)\*\*""")
_VALID_BOLD_PATTERN = re.compile(
    r"""(?<!\\)\*\*(?=\S)(.+?)(?<=\S)(?<!\\)\*\*""",
    re.DOTALL,
)
_FENCED_CODE_BLOCK_PATTERN = re.compile(
    r"""(^|\n)(?P<fence>`{3,}|~{3,})[^\n]*\n.*?\n(?P=fence)[^\n]*(?=\n|$)""",
    re.MULTILINE | re.DOTALL,
)
_INLINE_CODE_PATTERN = re.compile(r"""`[^`\n]*`""")


@dataclass(frozen=True)
class LessonRow:
    lesson_id: str
    title: str | None
    content_markdown: str


@dataclass(frozen=True)
class FormattingIssue:
    lesson_id: str
    title: str | None
    issue_type: str
    snippet: str


@dataclass(frozen=True)
class ScanSummary:
    total_lessons: int
    lessons_with_bold: int
    lessons_with_formatting_issues: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Example:
              python scripts/scan_markdown_integrity.py --db-url "$SUPABASE_DB_URL"
            """
        ),
    )
    parser.add_argument(
        "--db-url",
        default=os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL"),
        help="Postgres connection url (default: SUPABASE_DB_URL or DATABASE_URL)",
    )
    return parser.parse_args()


def _ensure_db_url(url: str | None) -> str:
    if not url:
        raise SystemExit("Missing database url (--db-url or SUPABASE_DB_URL / DATABASE_URL)")
    if "sslmode=" in url:
        return url
    if "localhost" in url or "127.0.0.1" in url:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}sslmode=require"


def _import_psycopg():
    try:
        import psycopg
    except ModuleNotFoundError as exc:  # pragma: no cover - environment-specific
        raise SystemExit(
            "Missing dependency: psycopg. Install backend dependencies before running this script."
        ) from exc
    return psycopg


def _fetch_lessons(conn: "psycopg.Connection") -> list[LessonRow]:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT id::text, title, COALESCE(content_markdown, '')
            FROM app.lessons
            ORDER BY id
            """
        )
        return [
            LessonRow(
                lesson_id=str(row[0]),
                title=row[1],
                content_markdown=row[2] or "",
            )
            for row in cur.fetchall()
        ]


def _mask_preserving_newlines(raw: str) -> str:
    return "".join("\n" if char == "\n" else " " for char in raw)


def _mask_markdown_code(markdown: str) -> str:
    masked = _FENCED_CODE_BLOCK_PATTERN.sub(
        lambda match: _mask_preserving_newlines(match.group(0) or ""),
        markdown,
    )
    return _INLINE_CODE_PATTERN.sub(
        lambda match: _mask_preserving_newlines(match.group(0) or ""),
        masked,
    )


def _extract_snippet(markdown: str, start: int, end: int | None = None, *, radius: int = 72) -> str:
    if not markdown:
        return "<empty>"
    resolved_end = end if end is not None else start + 2
    left = max(0, start - radius)
    right = min(len(markdown), resolved_end + radius)
    compact = " ".join(markdown[left:right].split())
    if not compact:
        return "<empty>"
    if left > 0:
        compact = f"…{compact}"
    if right < len(markdown):
        compact = f"{compact}…"
    return compact


def _find_unbalanced_bold_index(masked_markdown: str) -> int | None:
    valid_matches = list(_VALID_BOLD_PATTERN.finditer(masked_markdown))

    for match in valid_matches:
        content = match.group(1) or ""
        nested_match = _UNESCAPED_BOLD_PATTERN.search(content)
        if nested_match:
            return match.start(1) + nested_match.start()

    covered_indices = {
        index
        for match in valid_matches
        for index in (match.start(), match.end() - 2)
    }
    for token_match in _UNESCAPED_BOLD_PATTERN.finditer(masked_markdown):
        if token_match.start() not in covered_indices:
            return token_match.start()
    return None


def scan_markdown_content(markdown: str) -> tuple[bool, tuple[tuple[str, int], ...]]:
    masked = _mask_markdown_code(markdown or "")
    issues: list[tuple[str, int]] = []

    escaped_match = _ESCAPED_BOLD_PATTERN.search(masked)
    if escaped_match:
        issues.append(("escaped_bold", escaped_match.start()))

    html_match = _HTML_BOLD_PATTERN.search(masked)
    if html_match:
        issues.append(("html_bold", html_match.start()))

    unbalanced_index = _find_unbalanced_bold_index(masked)
    if unbalanced_index is not None:
        issues.append(("unbalanced_bold", unbalanced_index))

    has_bold = any(
        pattern.search(masked)
        for pattern in (
            _ESCAPED_BOLD_PATTERN,
            _HTML_BOLD_PATTERN,
            _UNESCAPED_BOLD_PATTERN,
        )
    )
    return has_bold, tuple(issues)


def audit_lessons(conn: "psycopg.Connection") -> tuple[list[FormattingIssue], ScanSummary]:
    issues: list[FormattingIssue] = []
    total_lessons = 0
    lessons_with_bold = 0
    lessons_with_formatting_issues = 0

    for lesson in _fetch_lessons(conn):
        total_lessons += 1
        has_bold, detected_issues = scan_markdown_content(lesson.content_markdown)
        if has_bold:
            lessons_with_bold += 1
        if detected_issues:
            lessons_with_formatting_issues += 1
            for issue_type, start in detected_issues:
                issues.append(
                    FormattingIssue(
                        lesson_id=lesson.lesson_id,
                        title=lesson.title,
                        issue_type=issue_type,
                        snippet=_extract_snippet(lesson.content_markdown, start),
                    )
                )

    return issues, ScanSummary(
        total_lessons=total_lessons,
        lessons_with_bold=lessons_with_bold,
        lessons_with_formatting_issues=lessons_with_formatting_issues,
    )


def _format_field(value: str | None, *, empty: str) -> str:
    compact = " ".join((value or "").split())
    return compact or empty


def print_report(issues: list[FormattingIssue], summary: ScanSummary) -> None:
    print("lesson_id\ttitle\tissue_type\tsnippet")
    for issue in issues:
        print(
            "\t".join(
                (
                    issue.lesson_id,
                    _format_field(issue.title, empty="<untitled>"),
                    issue.issue_type,
                    _format_field(issue.snippet, empty="<empty>"),
                )
            )
        )

    print()
    print(f"total lessons: {summary.total_lessons}")
    print(f"lessons with bold: {summary.lessons_with_bold}")
    print(f"lessons with formatting issues: {summary.lessons_with_formatting_issues}")


def main() -> int:
    args = parse_args()
    db_url = _ensure_db_url(args.db_url)
    psycopg = _import_psycopg()

    try:
        with psycopg.connect(db_url) as conn:
            issues, summary = audit_lessons(conn)
    except psycopg.Error as exc:
        print(f"Markdown integrity scan failed: {exc}", file=sys.stderr)
        return 2

    print_report(issues, summary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
