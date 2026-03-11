#!/usr/bin/env python3
r"""Resolve remaining unbalanced Markdown bold markers in lesson content.

This script scans `app.lessons.content_markdown` for rows still flagged with
`unbalanced_bold` and normalizes the remaining malformed bold markers.

Safety:

* Defaults to dry-run unless `--apply` is passed.
* Only `app.lessons.content_markdown` is updated.
* Media tokens, Markdown images, Markdown links, fenced code blocks, and
  inline code are protected and never rewritten.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import textwrap
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import psycopg


ROOT_DIR = Path(__file__).resolve().parents[1]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.scan_markdown_integrity import (  # noqa: E402
    _FENCED_CODE_BLOCK_PATTERN,
    _INLINE_CODE_PATTERN,
    scan_markdown_content,
)


_UNESCAPED_BOLD_PATTERN = re.compile(r"""(?<!\\)\*\*""")
_REPEATED_STAR_PATTERN = re.compile(r"""(?<!\\)\*{3,}""")
_WHITESPACE_ONLY_BOLD_PATTERN = re.compile(r"""(?<!\\)\*\*\s+\*\*""")
_MEDIA_TOKEN_PATTERN = re.compile(r"""!(?:video|audio|image)\([^)]+\)""")
_MARKDOWN_IMAGE_PATTERN = re.compile(
    r"""!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)"""
)
_MARKDOWN_LINK_PATTERN = re.compile(
    r"""(?<!!)\[[^\]]+]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)"""
)
_BLANK_LINE_SPLIT_PATTERN = re.compile(r"""(\n\s*\n)""")


@dataclass(frozen=True)
class LessonRow:
    lesson_id: str
    title: str | None
    content_markdown: str


@dataclass(frozen=True)
class LessonFix:
    lesson_id: str
    title: str | None
    before: str
    after: str
    before_snippet: str
    after_snippet: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Examples:
              python scripts/fix_remaining_unbalanced_bold.py --dry-run
              python scripts/fix_remaining_unbalanced_bold.py --apply \
                --db-url "$SUPABASE_DB_URL"
            """
        ),
    )
    parser.add_argument(
        "--db-url",
        default=os.environ.get("SUPABASE_DB_URL") or os.environ.get("DATABASE_URL"),
        help="Postgres connection url (default: SUPABASE_DB_URL or DATABASE_URL)",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without writing to the database (default)",
    )
    mode.add_argument(
        "--apply",
        action="store_true",
        help="Persist normalized Markdown back to app.lessons",
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


def _merge_spans(spans: list[tuple[int, int]]) -> tuple[tuple[int, int], ...]:
    if not spans:
        return ()
    merged: list[list[int]] = []
    for start, end in sorted(spans):
        if not merged or start > merged[-1][1]:
            merged.append([start, end])
            continue
        merged[-1][1] = max(merged[-1][1], end)
    return tuple((start, end) for start, end in merged)


def _protected_spans(markdown: str) -> tuple[tuple[int, int], ...]:
    spans: list[tuple[int, int]] = []
    for pattern in (
        _FENCED_CODE_BLOCK_PATTERN,
        _INLINE_CODE_PATTERN,
        _MEDIA_TOKEN_PATTERN,
        _MARKDOWN_IMAGE_PATTERN,
        _MARKDOWN_LINK_PATTERN,
    ):
        spans.extend((match.start(), match.end()) for match in pattern.finditer(markdown))
    return _merge_spans(spans)


def _collapse_repeated_stars(text: str) -> str:
    return _REPEATED_STAR_PATTERN.sub("**", text)


def _remove_empty_bold_pairs(text: str) -> str:
    return _WHITESPACE_ONLY_BOLD_PATTERN.sub("", text)


def _repair_unbalanced_block(block: str) -> str:
    token_positions = [match.start() for match in _UNESCAPED_BOLD_PATTERN.finditer(block)]
    if not token_positions or len(token_positions) % 2 == 0:
        return block

    content_start = len(block) - len(block.lstrip())
    content_end = len(block.rstrip())
    if content_end <= content_start:
        return block

    first_token = token_positions[0]
    last_token = token_positions[-1]
    if last_token >= content_end - 2 and first_token > content_start:
        return block[:content_start] + "**" + block[content_start:]
    return block[:content_end] + "**" + block[content_end:]


def _normalize_unprotected_segment(segment: str) -> str:
    updated = segment
    for _ in range(6):
        previous = updated
        updated = _collapse_repeated_stars(updated)
        updated = _remove_empty_bold_pairs(updated)

        parts = _BLANK_LINE_SPLIT_PATTERN.split(updated)
        rebuilt: list[str] = []
        for index, part in enumerate(parts):
            if index % 2 == 1:
                rebuilt.append(part)
                continue
            rebuilt.append(_repair_unbalanced_block(part))
        updated = "".join(rebuilt)

        if updated == previous:
            break
    return updated


def normalize_remaining_unbalanced_bold(markdown: str) -> str:
    if not markdown:
        return markdown

    spans = _protected_spans(markdown)
    parts: list[str] = []
    cursor = 0

    for start, end in spans:
        parts.append(_normalize_unprotected_segment(markdown[cursor:start]))
        parts.append(markdown[start:end])
        cursor = end

    parts.append(_normalize_unprotected_segment(markdown[cursor:]))
    return "".join(parts)


def plan_lesson_fixes(lessons: list[LessonRow]) -> list[LessonFix]:
    fixes: list[LessonFix] = []

    for lesson in lessons:
        _, issues = scan_markdown_content(lesson.content_markdown)
        issue_types = {issue_type for issue_type, _ in issues}
        if "unbalanced_bold" not in issue_types:
            continue

        before_index = next(
            (start for issue_type, start in issues if issue_type == "unbalanced_bold"),
            0,
        )
        normalized = normalize_remaining_unbalanced_bold(lesson.content_markdown)
        if normalized == lesson.content_markdown:
            continue

        fixes.append(
            LessonFix(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                before=lesson.content_markdown,
                after=normalized,
                before_snippet=_extract_snippet(lesson.content_markdown, before_index),
                after_snippet=_extract_snippet(normalized, before_index),
            )
        )

    return fixes


def _format_field(value: str | None, *, empty: str) -> str:
    compact = " ".join((value or "").split())
    return compact or empty


def _print_report(total_lessons_scanned: int, fixes: list[LessonFix], *, dry_run: bool) -> None:
    mode_label = "Dry-run" if dry_run else "Apply"
    if not fixes:
        print(f"{mode_label}: no remaining unbalanced bold rows require fixes.\n")
        print(f"total_lessons_scanned: {total_lessons_scanned}")
        print("rows_fixed: 0")
        return

    print(f"{mode_label}: {len(fixes)} lesson rows will change.\n")
    print("lesson_id\ttitle\tbefore_snippet\tafter_snippet")
    for fix in fixes:
        print(
            "\t".join(
                (
                    fix.lesson_id,
                    _format_field(fix.title, empty="<untitled>"),
                    _format_field(fix.before_snippet, empty="<empty>"),
                    _format_field(fix.after_snippet, empty="<empty>"),
                )
            )
        )

    print()
    print(f"total_lessons_scanned: {total_lessons_scanned}")
    print(f"rows_fixed: {len(fixes)}")


def apply_lesson_fixes(conn: "psycopg.Connection", fixes: list[LessonFix]) -> int:
    if not fixes:
        return 0

    with conn.cursor() as cur:
        for fix in fixes:
            cur.execute(
                """
                UPDATE app.lessons
                SET content_markdown = %s
                WHERE id = %s
                  AND COALESCE(content_markdown, '') <> %s
                """,
                (fix.after, fix.lesson_id, fix.after),
            )
    conn.commit()
    return len(fixes)


def main() -> int:
    args = parse_args()
    dry_run = not args.apply
    db_url = _ensure_db_url(args.db_url)
    psycopg = _import_psycopg()

    try:
        with psycopg.connect(db_url, autocommit=False) as conn:
            lessons = _fetch_lessons(conn)
            fixes = plan_lesson_fixes(lessons)
            _print_report(len(lessons), fixes, dry_run=dry_run)
            if dry_run:
                if fixes:
                    print("Dry-run complete. Re-run with --apply to persist changes.")
                return 0

            updated = apply_lesson_fixes(conn, fixes)
    except psycopg.Error as exc:
        print(f"Remaining unbalanced bold migration failed: {exc}", file=sys.stderr)
        return 2

    print(f"Updated {updated} lesson rows.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
