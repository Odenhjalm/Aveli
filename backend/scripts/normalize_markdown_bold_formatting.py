#!/usr/bin/env python3
r"""Normalize legacy Markdown bold formatting in lesson content.

This script scans `app.lessons.content_markdown` and fixes a narrow set of
legacy bold-formatting issues:

* `\*\*text\*\*` -> `**text**`
* `**** Heading ****` -> `**Heading**`
* `**text` -> `**text**`
* `text**` -> `**text**`
* `**Tips: **` -> `**Tips:**`

Safety:

* Defaults to dry-run unless `--apply` is passed.
* Only `app.lessons.content_markdown` is updated.
* Fenced code, inline code, Markdown links, Markdown images, and media tokens
  are protected and never rewritten.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import textwrap
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import psycopg


_ESCAPED_BOLD_MARKER_PATTERN = re.compile(r"""\\\*\\\*""")
_UNESCAPED_BOLD_PATTERN = re.compile(r"""(?<!\\)\*\*""")
_REPEATED_BOLD_MARKER_PATTERN = re.compile(r"""(?<!\\)\*{3,}""")
_BOLD_PUNCTUATION_BOUNDARY_PATTERN = re.compile(r"""(\*\*[^*]+?[:!?]\*\*)(?=\S)""")
_BOLD_GENERAL_BOUNDARY_PATTERN = re.compile(
    r"""(^|[\s([{>•])(\*\*(?=\S)[^*]+?(?<=\S)\*\*)(?=[A-Za-zÅÄÖåäö0-9])""",
    re.MULTILINE,
)
_FENCED_CODE_BLOCK_PATTERN = re.compile(
    r"""(^|\n)(?P<fence>`{3,}|~{3,})[^\n]*\n.*?\n(?P=fence)[^\n]*(?=\n|$)""",
    re.MULTILINE | re.DOTALL,
)
_INLINE_CODE_PATTERN = re.compile(r"""`[^`\n]*`""")
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
class IssuePreview:
    issue_type: str
    before_snippet: str
    after_snippet: str


@dataclass(frozen=True)
class LessonMigration:
    lesson_id: str
    title: str | None
    before: str
    after: str
    issues: tuple[IssuePreview, ...] = field(default_factory=tuple)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Examples:
              python scripts/normalize_markdown_bold_formatting.py --dry-run
              python scripts/normalize_markdown_bold_formatting.py --apply \
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


def _preview(issue_type: str, before: str, after: str, start: int, end: int | None = None) -> IssuePreview:
    resolved_end = end if end is not None else start + 2
    return IssuePreview(
        issue_type=issue_type,
        before_snippet=_extract_snippet(before, start, resolved_end),
        after_snippet=_extract_snippet(after, start, start + max(2, resolved_end - start)),
    )


def _normalize_bold_markers(segment: str) -> tuple[str, IssuePreview | None]:
    first_match = _ESCAPED_BOLD_MARKER_PATTERN.search(segment) or _REPEATED_BOLD_MARKER_PATTERN.search(
        segment
    )
    if not first_match:
        return segment, None

    updated = _ESCAPED_BOLD_MARKER_PATTERN.sub("**", segment)
    updated = _REPEATED_BOLD_MARKER_PATTERN.sub("**", updated)
    if updated == segment:
        return segment, None
    return updated, _preview("escaped_bold", segment, updated, first_match.start(), first_match.end())


def _repair_unbalanced_bold(block: str) -> tuple[str, IssuePreview | None]:
    token_positions = [match.start() for match in _UNESCAPED_BOLD_PATTERN.finditer(block)]
    if not token_positions or len(token_positions) % 2 == 0:
        return block, None

    content_start = len(block) - len(block.lstrip())
    content_end = len(block.rstrip())
    if content_end <= content_start:
        return block, None

    first_token = token_positions[0]
    last_token = token_positions[-1]
    if last_token >= content_end - 2 and first_token > content_start:
        updated = block[:content_start] + "**" + block[content_start:]
        return updated, _preview("unbalanced_bold", block, updated, content_start, content_start + 2)

    updated = block[:content_end] + "**" + block[content_end:]
    return updated, _preview("unbalanced_bold", block, updated, content_end, content_end + 2)


def _trim_balanced_bold_whitespace(block: str) -> tuple[str, IssuePreview | None]:
    token_positions = [match.start() for match in _UNESCAPED_BOLD_PATTERN.finditer(block)]
    if not token_positions or len(token_positions) % 2 == 1:
        return block, None

    parts: list[str] = []
    last_index = 0
    output_length = 0
    first_changed_before_start: int | None = None
    first_changed_after_start: int | None = None
    first_changed_after_end: int | None = None

    for open_index, close_index in zip(token_positions[::2], token_positions[1::2], strict=True):
        prefix = block[last_index:open_index]
        parts.append(prefix)
        output_length += len(prefix)

        inner = block[open_index + 2 : close_index]
        replacement_inner = inner.strip()
        if not replacement_inner:
            replacement_inner = inner

        original = block[open_index : close_index + 2]
        replacement = f"**{replacement_inner}**"
        if original != replacement and first_changed_before_start is None:
            first_changed_before_start = open_index
            first_changed_after_start = output_length
            first_changed_after_end = output_length + len(replacement)

        parts.append(replacement)
        output_length += len(replacement)
        last_index = close_index + 2

    suffix = block[last_index:]
    parts.append(suffix)
    updated = "".join(parts)
    if updated == block or first_changed_before_start is None:
        return block, None
    return updated, IssuePreview(
        issue_type="whitespace_bold",
        before_snippet=_extract_snippet(block, first_changed_before_start, first_changed_before_start + 2),
        after_snippet=_extract_snippet(
            updated,
            first_changed_after_start or 0,
            first_changed_after_end,
        ),
    )


def fix_bold_colon_boundary(text: str) -> str:
    """
    Fix pattern:
    **Tips:**Om -> **Tips:** Om

    Only applies when:
    - bold segment ends with punctuation (:!?)
    - immediately followed by non-space character
    """

    return _BOLD_PUNCTUATION_BOUNDARY_PATTERN.sub(r"\1 ", text)


def _fix_bold_colon_boundary(block: str) -> tuple[str, IssuePreview | None]:
    first_match = _BOLD_PUNCTUATION_BOUNDARY_PATTERN.search(block)
    if not first_match:
        return block, None

    updated = fix_bold_colon_boundary(block)
    if updated == block:
        return block, None

    return updated, _preview(
        "bold_boundary",
        block,
        updated,
        first_match.start(),
        first_match.end(),
    )


def fix_bold_general_boundary(text: str) -> str:
    """
    Fix:
    **text**X -> **text** X

    Only when:
    - bold is immediately followed by alphanumeric character
    """

    return _BOLD_GENERAL_BOUNDARY_PATTERN.sub(r"\1\2 ", text)


def _fix_bold_general_boundary(block: str) -> tuple[str, IssuePreview | None]:
    first_match = _BOLD_GENERAL_BOUNDARY_PATTERN.search(block)
    if not first_match:
        return block, None

    updated = fix_bold_general_boundary(block)
    if updated == block:
        return block, None

    return updated, _preview(
        "bold_general_boundary",
        block,
        updated,
        first_match.start(),
        first_match.end(),
    )


def _normalize_text_block(block: str) -> tuple[str, tuple[IssuePreview, ...]]:
    issues: dict[str, IssuePreview] = {}
    updated = block

    updated, unbalanced_issue = _repair_unbalanced_bold(updated)
    if unbalanced_issue:
        issues[unbalanced_issue.issue_type] = unbalanced_issue

    updated, whitespace_issue = _trim_balanced_bold_whitespace(updated)
    if whitespace_issue:
        issues[whitespace_issue.issue_type] = whitespace_issue

    updated, boundary_issue = _fix_bold_colon_boundary(updated)
    if boundary_issue:
        issues[boundary_issue.issue_type] = boundary_issue

    updated, general_boundary_issue = _fix_bold_general_boundary(updated)
    if general_boundary_issue:
        issues[general_boundary_issue.issue_type] = general_boundary_issue

    return updated, tuple(issues.values())


def _normalize_text_segment(segment: str) -> tuple[str, tuple[IssuePreview, ...]]:
    issues: dict[str, IssuePreview] = {}
    updated = segment

    updated, escaped_issue = _normalize_bold_markers(updated)
    if escaped_issue:
        issues[escaped_issue.issue_type] = escaped_issue

    parts = _BLANK_LINE_SPLIT_PATTERN.split(updated)
    normalized_parts: list[str] = []
    for index, part in enumerate(parts):
        if index % 2 == 1:
            normalized_parts.append(part)
            continue
        normalized_part, part_issues = _normalize_text_block(part)
        normalized_parts.append(normalized_part)
        for issue in part_issues:
            if issue.issue_type not in issues:
                issues[issue.issue_type] = issue

    return "".join(normalized_parts), tuple(issues.values())


def normalize_lesson_markdown(markdown: str) -> tuple[str, tuple[IssuePreview, ...]]:
    if not markdown:
        return markdown, ()

    spans = _protected_spans(markdown)
    normalized_parts: list[str] = []
    issues: dict[str, IssuePreview] = {}
    cursor = 0

    for start, end in spans:
        plain_segment = markdown[cursor:start]
        normalized_segment, segment_issues = _normalize_text_segment(plain_segment)
        normalized_parts.append(normalized_segment)
        normalized_parts.append(markdown[start:end])
        for issue in segment_issues:
            if issue.issue_type not in issues:
                issues[issue.issue_type] = issue
        cursor = end

    remaining_segment = markdown[cursor:]
    normalized_segment, segment_issues = _normalize_text_segment(remaining_segment)
    normalized_parts.append(normalized_segment)
    for issue in segment_issues:
        if issue.issue_type not in issues:
            issues[issue.issue_type] = issue

    normalized = "".join(normalized_parts)
    return normalized, tuple(issues.values())


def plan_lesson_migrations(lessons: list[LessonRow]) -> list[LessonMigration]:
    migrations: list[LessonMigration] = []
    for lesson in lessons:
        normalized, issues = normalize_lesson_markdown(lesson.content_markdown)
        if normalized == lesson.content_markdown:
            continue
        migrations.append(
            LessonMigration(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                before=lesson.content_markdown,
                after=normalized,
                issues=issues,
            )
        )
    return migrations


def _format_field(value: str | None, *, empty: str) -> str:
    compact = " ".join((value or "").split())
    return compact or empty


def _print_report(total_lessons: int, migrations: list[LessonMigration], *, dry_run: bool) -> None:
    mode_label = "Dry-run" if dry_run else "Apply"
    if not migrations:
        print(f"{mode_label}: no lesson rows require normalization.\n")
        print(f"total_lessons: {total_lessons}")
        print("lessons_changed: 0")
        print("escaped_bold_fixed: 0")
        print("unbalanced_bold_fixed: 0")
        return

    print(f"{mode_label}: {len(migrations)} lesson rows will change.\n")
    print("lesson_id\ttitle\tissue_type\tbefore_snippet\tafter_snippet")

    escaped_fixed = 0
    unbalanced_fixed = 0
    for migration in migrations:
        for issue in migration.issues:
            print(
                "\t".join(
                    (
                        migration.lesson_id,
                        _format_field(migration.title, empty="<untitled>"),
                        issue.issue_type,
                        _format_field(issue.before_snippet, empty="<empty>"),
                        _format_field(issue.after_snippet, empty="<empty>"),
                    )
                )
            )
            if issue.issue_type == "escaped_bold":
                escaped_fixed += 1
            if issue.issue_type == "unbalanced_bold":
                unbalanced_fixed += 1

    print()
    print(f"total_lessons: {total_lessons}")
    print(f"lessons_changed: {len(migrations)}")
    print(f"escaped_bold_fixed: {escaped_fixed}")
    print(f"unbalanced_bold_fixed: {unbalanced_fixed}")


def apply_lesson_migrations(
    conn: "psycopg.Connection", migrations: list[LessonMigration]
) -> int:
    if not migrations:
        return 0

    with conn.cursor() as cur:
        for migration in migrations:
            cur.execute(
                """
                UPDATE app.lessons
                SET content_markdown = %s
                WHERE id = %s
                  AND COALESCE(content_markdown, '') <> %s
                """,
                (migration.after, migration.lesson_id, migration.after),
            )
    conn.commit()
    return len(migrations)


def main() -> int:
    args = parse_args()
    dry_run = not args.apply
    db_url = _ensure_db_url(args.db_url)
    psycopg = _import_psycopg()

    try:
        with psycopg.connect(db_url, autocommit=False) as conn:
            lessons = _fetch_lessons(conn)
            migrations = plan_lesson_migrations(lessons)
            _print_report(len(lessons), migrations, dry_run=dry_run)
            if dry_run:
                if migrations:
                    print("Dry-run complete. Re-run with --apply to persist changes.")
                return 0

            updated = apply_lesson_migrations(conn, migrations)
    except psycopg.Error as exc:
        print(f"Bold normalization failed: {exc}", file=sys.stderr)
        return 2

    print(f"Updated {updated} lesson rows.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
