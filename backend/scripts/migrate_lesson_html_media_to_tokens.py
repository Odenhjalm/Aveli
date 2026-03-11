#!/usr/bin/env python3
"""Migrate legacy lesson HTML media embeds to canonical Markdown tokens.

This script rewrites legacy lesson `content_markdown` stored in `app.lessons`
from HTML media tags to canonical Markdown media tokens:

* `<img src="/studio/media/{id}">` -> `!image({id})`
* `<audio src="/studio/media/{id}"></audio>` -> `!audio({id})`
* `<video src="/studio/media/{id}"></video>` -> `!video({id})`

Safety:

* Defaults to dry-run unless `--apply` is passed.
* Only rows whose normalized content changes are updated.
* Media HTML that cannot be mapped to a valid lesson media id is removed and
  logged; invalid tokens are never written.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import textwrap
from dataclasses import dataclass, field
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    import psycopg


MEDIA_ID_FRAGMENT = r"[A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*"

_AUDIO_HTML_ELEMENT_PATTERN = re.compile(
    r"<audio\b[^>]*?(?:\/>|>.*?<\/audio>)",
    re.IGNORECASE | re.DOTALL,
)
_VIDEO_HTML_ELEMENT_PATTERN = re.compile(
    r"<video\b[^>]*?(?:\/>|>.*?<\/video>)",
    re.IGNORECASE | re.DOTALL,
)
_IMG_HTML_TAG_PATTERN = re.compile(
    r"<img\b[^>]*?>",
    re.IGNORECASE,
)
_AUDIO_HTML_TAG_PATTERN = re.compile(r"</?audio\b[^>]*>", re.IGNORECASE)
_VIDEO_HTML_TAG_PATTERN = re.compile(r"</?video\b[^>]*>", re.IGNORECASE)
_FORBIDDEN_HTML_MEDIA_PATTERN = re.compile(r"<\s*(video|audio|img)\b", re.IGNORECASE)
_HTML_ATTRIBUTE_PATTERN = re.compile(
    r"""([a-zA-Z_:][a-zA-Z0-9_\-:.]*)\s*=\s*("([^"]*)"|'([^']*)')"""
)
_STUDIO_MEDIA_URL_PATTERN = re.compile(
    rf"""(?:https?:\/\/[^\s"'()]+)?\/studio\/media\/({MEDIA_ID_FRAGMENT})\b""",
    re.IGNORECASE,
)
_MEDIA_STREAM_URL_PATTERN = re.compile(
    r"""(?:https?:\/\/[^\s"'()]+)?\/media\/stream\/([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)""",
    re.IGNORECASE,
)
_MARKDOWN_IMAGE_PATTERN = re.compile(
    r"""!\[[^\]]*]\((?:<)?([^)>\s]+)(?:>)?(?:\s+"[^"]*")?\)""",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class LessonRow:
    lesson_id: str
    title: str | None
    content_markdown: str


@dataclass(frozen=True)
class LessonMigration:
    lesson_id: str
    title: str | None
    before: str
    after: str
    warnings: tuple[str, ...] = field(default_factory=tuple)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            """
            Examples:
              python scripts/migrate_lesson_html_media_to_tokens.py --dry-run
              python scripts/migrate_lesson_html_media_to_tokens.py --apply \
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


def _parse_html_attributes(raw_html: str) -> dict[str, str]:
    attrs: dict[str, str] = {}
    for match in _HTML_ATTRIBUTE_PATTERN.finditer(raw_html):
        key = match.group(1)
        if not key:
            continue
        value = match.group(3) or match.group(4) or ""
        attrs[key.lower()] = value
    return attrs


def _normalize_media_source_attribute(attrs: dict[str, str]) -> str:
    for key in ("src", "data-src", "data-url", "data-download-url"):
        value = attrs.get(key)
        if value and value.strip():
            return value.strip()
    return ""


def _extract_media_id_from_token(token: str) -> str | None:
    parts = token.split(".")
    if len(parts) != 3:
        return None
    payload = parts[1]
    payload += "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        parsed = json.loads(decoded.decode("utf-8"))
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(parsed, dict):
        return None
    subject = parsed.get("sub")
    if isinstance(subject, str) and subject.strip():
        return subject.strip()
    return None


def _lesson_media_id_from_src(src: str) -> str | None:
    if not src:
        return None
    studio_match = _STUDIO_MEDIA_URL_PATTERN.search(src)
    if studio_match:
        lesson_media_id = studio_match.group(1)
        if lesson_media_id:
            return lesson_media_id
    stream_match = _MEDIA_STREAM_URL_PATTERN.search(src)
    if not stream_match:
        return None
    token = stream_match.group(1)
    if not token:
        return None
    return _extract_media_id_from_token(token)


def _lesson_media_id_from_media_attributes(attrs: dict[str, str], src: str) -> str | None:
    explicit_id = attrs.get("data-lesson-media-id") or attrs.get("data-lesson_media_id")
    if explicit_id and explicit_id.strip():
        return explicit_id.strip()
    return _lesson_media_id_from_src(src)


def _lesson_media_token(kind: str, lesson_media_id: str) -> str:
    return f"!{kind}({lesson_media_id})"


def _warning_preview(raw: str, limit: int = 120) -> str:
    compact = " ".join(raw.split())
    if not compact:
        return "<empty>"
    if len(compact) <= limit:
        return compact
    return f"{compact[: limit - 1]}…"


def _replace_html_media(
    markdown: str,
    *,
    pattern: re.Pattern[str],
    kind: str,
    warnings: list[str],
) -> str:
    def _replacement(match: re.Match[str]) -> str:
        raw = match.group(0) or ""
        attrs = _parse_html_attributes(raw)
        src = _normalize_media_source_attribute(attrs)
        lesson_media_id = _lesson_media_id_from_media_attributes(attrs, src)
        if lesson_media_id:
            return _lesson_media_token(kind, lesson_media_id)
        warnings.append(
            f"Removed unresolved <{kind}> HTML media tag: {_warning_preview(raw)}"
        )
        return ""

    return pattern.sub(_replacement, markdown)


def _normalize_markdown_image(match: re.Match[str]) -> str:
    url = (match.group(1) or "").strip()
    if not url:
        return match.group(0) or ""
    lesson_media_id = _lesson_media_id_from_src(url)
    if not lesson_media_id:
        return match.group(0) or ""
    return _lesson_media_token("image", lesson_media_id)


def _strip_remaining_html_media_tags(markdown: str, warnings: list[str]) -> str:
    def _strip_with_warning(
        raw_markdown: str,
        *,
        pattern: re.Pattern[str],
        label: str,
    ) -> str:
        def _replacement(match: re.Match[str]) -> str:
            raw = match.group(0) or ""
            warnings.append(
                f"Removed remaining <{label}> HTML media tag: {_warning_preview(raw)}"
            )
            return ""

        return pattern.sub(_replacement, raw_markdown)

    stripped = markdown
    stripped = _strip_with_warning(
        stripped,
        pattern=_AUDIO_HTML_TAG_PATTERN,
        label="audio",
    )
    stripped = _strip_with_warning(
        stripped,
        pattern=_VIDEO_HTML_TAG_PATTERN,
        label="video",
    )
    stripped = _strip_with_warning(
        stripped,
        pattern=_IMG_HTML_TAG_PATTERN,
        label="img",
    )
    return stripped


def assert_no_html_media(markdown: str) -> None:
    if markdown and _FORBIDDEN_HTML_MEDIA_PATTERN.search(markdown):
        raise ValueError(
            "Canonical text contract violation: HTML media tags are forbidden. "
            "Use !video(id), !audio(id), or !image(id)."
        )


def normalize_lesson_markdown(markdown: str) -> tuple[str, tuple[str, ...]]:
    if not markdown:
        return markdown, ()

    warnings: list[str] = []
    normalized = markdown
    normalized = _replace_html_media(
        normalized,
        pattern=_AUDIO_HTML_ELEMENT_PATTERN,
        kind="audio",
        warnings=warnings,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_VIDEO_HTML_ELEMENT_PATTERN,
        kind="video",
        warnings=warnings,
    )
    normalized = _replace_html_media(
        normalized,
        pattern=_IMG_HTML_TAG_PATTERN,
        kind="image",
        warnings=warnings,
    )
    normalized = _MEDIA_STREAM_URL_PATTERN.sub(
        lambda match: (
            f"/studio/media/{lesson_media_id}"
            if (lesson_media_id := _extract_media_id_from_token(match.group(1) or ""))
            else match.group(0) or ""
        ),
        normalized,
    )
    normalized = _STUDIO_MEDIA_URL_PATTERN.sub(
        lambda match: f"/studio/media/{match.group(1)}",
        normalized,
    )
    normalized = _MARKDOWN_IMAGE_PATTERN.sub(_normalize_markdown_image, normalized)
    normalized = _strip_remaining_html_media_tags(normalized, warnings)
    assert_no_html_media(normalized)
    return normalized, tuple(warnings)


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


def plan_lesson_migrations(conn: "psycopg.Connection") -> list[LessonMigration]:
    migrations: list[LessonMigration] = []
    for lesson in _fetch_lessons(conn):
        normalized, warnings = normalize_lesson_markdown(lesson.content_markdown)
        if normalized == lesson.content_markdown:
            continue
        migrations.append(
            LessonMigration(
                lesson_id=lesson.lesson_id,
                title=lesson.title,
                before=lesson.content_markdown,
                after=normalized,
                warnings=warnings,
            )
        )
    return migrations


def _print_plan(migrations: list[LessonMigration], *, dry_run: bool) -> None:
    if not migrations:
        print("No lesson rows require migration.")
        return

    mode_label = "Dry-run" if dry_run else "Apply"
    print(f"{mode_label}: {len(migrations)} lesson rows will change.\n")

    for migration in migrations:
        title = migration.title or "<untitled>"
        print(f"- lesson_id={migration.lesson_id} title={title}")
        print(f"  before: {_warning_preview(migration.before, limit=180)}")
        print(f"  after : {_warning_preview(migration.after, limit=180)}")
        for warning in migration.warnings:
            print(f"  warning: {warning}")
        print()


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
            migrations = plan_lesson_migrations(conn)
            _print_plan(migrations, dry_run=dry_run)
            if dry_run:
                if migrations:
                    print("Dry-run complete. Re-run with --apply to persist changes.")
                return 0

            updated = apply_lesson_migrations(conn, migrations)
    except (psycopg.Error, ValueError) as exc:
        print(f"Migration failed: {exc}", file=sys.stderr)
        return 2

    print(f"Updated {updated} lesson rows.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
