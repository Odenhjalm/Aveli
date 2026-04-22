#!/usr/bin/env python3
r"""Repair persisted lesson Markdown emphasis via the canonical editor pipeline.

This script audits `app.lesson_contents.content_markdown` for emphasis-related
corruption and repairs only rows whose Markdown changes when round-tripped
through the canonical frontend adapters:

1. Markdown -> Quill Delta / Document
2. Quill Delta -> canonical Markdown

Safety:

* Defaults to dry-run unless `--apply` is passed.
* Uses the app's real adapter pipeline via `frontend/tool/lesson_markdown_roundtrip.dart`.
* Updates only rows whose canonical Markdown differs from the stored value.
* Skips rows that fail round-trip parsing.
* Uses expected-current-content guards to avoid stale overwrites.
* Applies all writes inside a single SQL transaction.

Limit:

* If persisted Markdown already encodes `**bold**` where the original user
  intent was italic, that semantic intent is lost. This script will not guess.
"""

from __future__ import annotations

import argparse
import csv
import difflib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

ROOT_DIR = Path(__file__).resolve().parents[1]
FRONTEND_DIR = ROOT_DIR.parent / "frontend"
ROUNDTRIP_TOOL = FRONTEND_DIR / "tool" / "lesson_markdown_roundtrip.dart"
ROUNDTRIP_HARNESS = FRONTEND_DIR / "tool" / "lesson_markdown_roundtrip_harness_test.dart"
DEFAULT_ENV_FILES = (
    ROOT_DIR / ".env.local",
    ROOT_DIR / ".env",
)

_MEDIA_ID_FRAGMENT = r"([A-Za-z0-9_-]+(?:-[A-Za-z0-9_-]+)*)"

_ESCAPED_BOLD_ITALIC_PATTERN = re.compile(
    r"""\\\*\\\*\\\*(?=\S)([^\n]+?)(?<=\S)\\\*\\\*\\\*""",
    re.MULTILINE,
)
_ESCAPED_BOLD_PATTERN = re.compile(
    r"""\\\*\\\*(?=\S)([^\n]+?)(?<=\S)\\\*\\\*""",
    re.MULTILINE,
)
_ESCAPED_ITALIC_PATTERN = re.compile(
    r"""\\\*(?=\S)([^\n]+?)(?<=\S)\\\*""",
    re.MULTILINE,
)
_STRONG_HTML_PATTERN = re.compile(
    r"""<\s*(strong|b)\s*>(.*?)<\s*/\s*(strong|b)\s*>""",
    re.IGNORECASE | re.DOTALL,
)
_EMPHASIS_HTML_PATTERN = re.compile(
    r"""<\s*(em|i)\s*>(.*?)<\s*/\s*(em|i)\s*>""",
    re.IGNORECASE | re.DOTALL,
)
_BOLD_ITALIC_BOLD_WRAPPED_PATTERN = re.compile(
    r"""\*\*_\s*([^\n]+?)\s*_\*\*""",
    re.MULTILINE,
)
_BOLD_ITALIC_ITALIC_WRAPPED_PATTERN = re.compile(
    r"""_\*\*\s*([^\n]+?)\s*\*\*_""",
    re.MULTILINE,
)
_SPACED_BOLD_ITALIC_PATTERN = re.compile(
    r"""(^|[^*])\*\*\*\s+([^\n]+?)\s+\*\*\*(?=([^*]|$))""",
    re.MULTILINE,
)
_SPACED_BOLD_PATTERN = re.compile(
    r"""(^|[^*])\*\*\s+([^\n]+?)\s+\*\*(?=([^*]|$))""",
    re.MULTILINE,
)
_SPACED_ITALIC_PATTERN = re.compile(
    r"""(^|[^*])\*\s+([^\n]+?)\s+\*(?=([^*]|$))""",
    re.MULTILINE,
)
_DOUBLE_UNDERSCORE_PATTERN = re.compile(
    r"""(^|[^\w*])__([^\n]+?)__(?=([^\w*]|$))""",
    re.MULTILINE,
)
_SINGLE_UNDERSCORE_PATTERN = re.compile(
    r"""(^|[^\w*])_([^\n]+?)_(?=([^\w*]|$))""",
    re.MULTILINE,
)
_CANONICAL_BOLD_ITALIC_PATTERN = re.compile(
    r"""(?<!\\)\*\*\*(?=\S)([^\n]+?)(?<=\S)(?<!\\)\*\*\*""",
    re.MULTILINE,
)
_CANONICAL_BOLD_PATTERN = re.compile(
    r"""(?<!\\)\*\*(?=\S)([^\n]+?)(?<=\S)(?<!\\)\*\*""",
    re.MULTILINE,
)
_CANONICAL_ITALIC_PATTERN = re.compile(
    r"""(?<!\\)(?<!\*)\*(?=\S)([^\n]+?)(?<=\S)(?<!\\)\*(?!\*)""",
    re.MULTILINE,
)
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
class PatternSpec:
    name: str
    pattern: re.Pattern[str]
    description: str
    repairable: bool = True


PATTERN_SPECS = (
    PatternSpec(
        "escaped_bold_italic",
        _ESCAPED_BOLD_ITALIC_PATTERN,
        r"literal \*\*\*text\*\*\* markers leak instead of formatting",
    ),
    PatternSpec(
        "escaped_bold",
        _ESCAPED_BOLD_PATTERN,
        r"literal \*\*text\*\* markers leak instead of formatting",
    ),
    PatternSpec(
        "escaped_italic",
        _ESCAPED_ITALIC_PATTERN,
        r"literal \*text\* markers leak instead of formatting",
    ),
    PatternSpec(
        "html_bold",
        _STRONG_HTML_PATTERN,
        "legacy <strong>/<b> emphasis remains in stored markdown",
    ),
    PatternSpec(
        "html_italic",
        _EMPHASIS_HTML_PATTERN,
        "legacy <em>/<i> emphasis remains in stored markdown",
    ),
    PatternSpec(
        "bold_italic_bold_wrapped",
        _BOLD_ITALIC_BOLD_WRAPPED_PATTERN,
        "mixed **_text_** wrapper needs canonical ***text*** output",
    ),
    PatternSpec(
        "bold_italic_italic_wrapped",
        _BOLD_ITALIC_ITALIC_WRAPPED_PATTERN,
        "mixed _**text**_ wrapper needs canonical ***text*** output",
    ),
    PatternSpec(
        "spaced_bold_italic",
        _SPACED_BOLD_ITALIC_PATTERN,
        "spaced *** text *** delimiter usage",
    ),
    PatternSpec(
        "spaced_bold",
        _SPACED_BOLD_PATTERN,
        "spaced ** text ** delimiter usage",
    ),
    PatternSpec(
        "spaced_italic",
        _SPACED_ITALIC_PATTERN,
        "spaced * text * delimiter usage",
    ),
    PatternSpec(
        "double_underscore_bold",
        _DOUBLE_UNDERSCORE_PATTERN,
        "legacy __bold__ delimiter usage",
    ),
    PatternSpec(
        "single_underscore_italic",
        _SINGLE_UNDERSCORE_PATTERN,
        "legacy _italic_ delimiter usage",
    ),
)

REPAIRABLE_PATTERN_NAMES = {spec.name for spec in PATTERN_SPECS if spec.repairable}


@dataclass(frozen=True)
class LessonRow:
    lesson_id: str
    lesson_title: str | None
    content_markdown: str


@dataclass(frozen=True)
class RoundTripResult:
    lesson_id: str
    canonical_markdown: str | None
    plain_text: str | None
    error: str | None


@dataclass(frozen=True)
class RepairCandidate:
    lesson_id: str
    lesson_title: str | None
    patterns: tuple[str, ...]
    before: str
    after: str
    plain_text: str
    diff: str


@dataclass(frozen=True)
class SkippedRow:
    lesson_id: str
    lesson_title: str | None
    patterns: tuple[str, ...]
    reason: str
    detail: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent(
            f"""
            Examples:
              python scripts/repair_lesson_markdown.py --dry-run
              python scripts/repair_lesson_markdown.py --apply --db-url "$DATABASE_URL"

            Canonical round-trip helper:
              {ROUNDTRIP_TOOL}
              {ROUNDTRIP_HARNESS}
            """
        ),
    )
    parser.add_argument(
        "--db-url",
        default=None,
        help="Postgres connection url (default: DATABASE_URL or SUPABASE_DB_URL from env files)",
    )
    parser.add_argument(
        "--env-file",
        action="append",
        default=[],
        help="Optional env file(s) to search for DATABASE_URL / SUPABASE_DB_URL",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limit the number of lesson rows audited",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=100,
        help="Rows per canonical round-trip batch",
    )
    parser.add_argument(
        "--frontend-dir",
        default=str(FRONTEND_DIR),
        help="Frontend package directory containing the round-trip tool",
    )
    parser.add_argument(
        "--roundtrip-command",
        nargs="+",
        default=[
            "flutter",
            "test",
            "tool/lesson_markdown_roundtrip_harness_test.dart",
            "--plain-name",
            "lesson markdown roundtrip harness",
        ],
        help="Command used to run the canonical round-trip helper",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview repairs without writing changes (default)",
    )
    mode.add_argument(
        "--apply",
        action="store_true",
        help="Persist repaired markdown back to app.lesson_contents",
    )
    return parser.parse_args()


def _load_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def _resolve_db_url(args: argparse.Namespace) -> str:
    if args.db_url:
        return _ensure_db_url(args.db_url)

    env_candidates = [Path(path) for path in args.env_file]
    if not env_candidates:
        env_candidates = list(DEFAULT_ENV_FILES)

    for env_path in env_candidates:
        env_values = _load_env_file(env_path)
        for key in ("DATABASE_URL", "SUPABASE_DB_URL"):
            value = env_values.get(key)
            if value:
                return _ensure_db_url(value)

    for key in ("DATABASE_URL", "SUPABASE_DB_URL"):
        value = os.environ.get(key)
        if value:
            return _ensure_db_url(value)

    raise SystemExit(
        "Missing database url. Pass --db-url or provide DATABASE_URL / SUPABASE_DB_URL "
        "in backend/.env.local, backend/.env, or the process environment."
    )


def _ensure_db_url(url: str) -> str:
    if "sslmode=" in url:
        return url
    hostname = urlparse(url).hostname or ""
    if hostname in {"127.0.0.1", "localhost"}:
        return url
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}sslmode=require"


def _ensure_tooling(frontend_dir: Path, roundtrip_command: list[str]) -> None:
    if not frontend_dir.exists():
        raise SystemExit(f"Frontend directory not found: {frontend_dir}")
    if not ROUNDTRIP_TOOL.exists():
        raise SystemExit(f"Round-trip helper not found: {ROUNDTRIP_TOOL}")
    if not ROUNDTRIP_HARNESS.exists():
        raise SystemExit(f"Round-trip harness not found: {ROUNDTRIP_HARNESS}")
    if shutil.which("psql") is None:
        raise SystemExit("psql is required for this script.")
    executable = roundtrip_command[0]
    if shutil.which(executable) is None:
        raise SystemExit(f"Required executable not found: {executable}")


def _sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _run_psql(db_url: str, sql: str, *, cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql, db_url],
        cwd=cwd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )


def _fetch_lessons(db_url: str, *, limit: int | None) -> list[LessonRow]:
    limit_clause = f"\n        limit {limit}" if limit is not None else ""
    sql = f"""
copy (
    select
        lc.lesson_id::text as lesson_id,
        l.lesson_title,
        coalesce(lc.content_markdown, '') as content_markdown
    from app.lesson_contents as lc
    join app.lessons as l
      on l.id = lc.lesson_id
    order by lc.lesson_id{limit_clause}
) to stdout with csv header
"""
    completed = _run_psql(db_url, sql)
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "psql lesson fetch failed")
    reader = csv.DictReader(io.StringIO(completed.stdout))
    return [
        LessonRow(
            lesson_id=row["lesson_id"],
            lesson_title=row.get("lesson_title"),
            content_markdown=row.get("content_markdown", ""),
        )
        for row in reader
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


def detect_corruption_patterns(markdown: str) -> tuple[str, ...]:
    patterns = {
        spec.name for spec in PATTERN_SPECS if spec.pattern.search(markdown or "")
    }
    masked = _mask_markdown_code(markdown or "")
    if _find_unbalanced_bold_index(masked) is not None:
        patterns.add("unbalanced_bold")
    return tuple(sorted(patterns))


def _strip_emphasis_markup_for_comparison(markdown: str) -> str:
    normalized = markdown or ""

    normalized = _ESCAPED_BOLD_ITALIC_PATTERN.sub(lambda match: match.group(1), normalized)
    normalized = _ESCAPED_BOLD_PATTERN.sub(lambda match: match.group(1), normalized)
    normalized = _ESCAPED_ITALIC_PATTERN.sub(lambda match: match.group(1), normalized)
    normalized = _STRONG_HTML_PATTERN.sub(lambda match: match.group(2), normalized)
    normalized = _EMPHASIS_HTML_PATTERN.sub(lambda match: match.group(2), normalized)
    normalized = _BOLD_ITALIC_BOLD_WRAPPED_PATTERN.sub(
        lambda match: match.group(1).strip(),
        normalized,
    )
    normalized = _BOLD_ITALIC_ITALIC_WRAPPED_PATTERN.sub(
        lambda match: match.group(1).strip(),
        normalized,
    )
    normalized = _SPACED_BOLD_ITALIC_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2).strip()}{match.group(3)}",
        normalized,
    )
    normalized = _SPACED_BOLD_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2).strip()}{match.group(3)}",
        normalized,
    )
    normalized = _SPACED_ITALIC_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2).strip()}{match.group(3)}",
        normalized,
    )
    normalized = _CANONICAL_BOLD_ITALIC_PATTERN.sub(
        lambda match: match.group(1),
        normalized,
    )
    normalized = _CANONICAL_BOLD_PATTERN.sub(lambda match: match.group(1), normalized)
    normalized = _CANONICAL_ITALIC_PATTERN.sub(lambda match: match.group(1), normalized)
    normalized = _DOUBLE_UNDERSCORE_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2)}{match.group(3)}",
        normalized,
    )
    normalized = _SINGLE_UNDERSCORE_PATTERN.sub(
        lambda match: f"{match.group(1)}{match.group(2)}{match.group(3)}",
        normalized,
    )
    return normalized


def _format_title(value: str | None) -> str:
    compact = " ".join((value or "").split())
    return compact or "<untitled>"


def _render_diff(before: str, after: str) -> str:
    lines = list(
        difflib.unified_diff(
            before.splitlines(),
            after.splitlines(),
            fromfile="stored",
            tofile="repaired",
            lineterm="",
        )
    )
    return "\n".join(lines) if lines else "<no diff>"


def _run_roundtrip_batch(
    frontend_dir: Path,
    roundtrip_command: list[str],
    rows: list[LessonRow],
) -> list[RoundTripResult]:
    payload = json.dumps(
        {
            "items": [
                {"lesson_id": row.lesson_id, "markdown": row.content_markdown}
                for row in rows
            ]
        }
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

        completed = subprocess.run(
            roundtrip_command,
            cwd=frontend_dir,
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                "Canonical round-trip helper failed.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}"
            )

        raw_output = output_path.read_text(encoding="utf-8")
        if not raw_output.strip():
            raise RuntimeError(
                "Canonical round-trip helper produced no output.\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}"
            )

        decoded = json.loads(raw_output)
    finally:
        input_path.unlink(missing_ok=True)
        output_path.unlink(missing_ok=True)

    raw_results = decoded.get("results")
    if not isinstance(raw_results, list):
        raise RuntimeError("Canonical round-trip helper returned invalid JSON")
    results = [
        RoundTripResult(
            lesson_id=str(item.get("lesson_id") or ""),
            canonical_markdown=(
                None
                if item.get("canonical_markdown") is None
                else str(item.get("canonical_markdown"))
            ),
            plain_text=(
                None if item.get("plain_text") is None else str(item.get("plain_text"))
            ),
            error=None if item.get("error") is None else str(item.get("error")),
        )
        for item in raw_results
        if isinstance(item, dict)
    ]
    if len(results) != len(rows):
        raise RuntimeError(
            f"Canonical round-trip helper returned {len(results)} results for {len(rows)} rows"
        )
    return results


def roundtrip_lessons(
    frontend_dir: Path,
    roundtrip_command: list[str],
    rows: list[LessonRow],
    *,
    batch_size: int,
) -> dict[str, RoundTripResult]:
    results_by_id: dict[str, RoundTripResult] = {}
    for start in range(0, len(rows), batch_size):
        batch = rows[start : start + batch_size]
        for result in _run_roundtrip_batch(frontend_dir, roundtrip_command, batch):
            results_by_id[result.lesson_id] = result
    return results_by_id


def build_repair_plan(
    rows: list[LessonRow],
    roundtrip_results: dict[str, RoundTripResult],
) -> tuple[list[RepairCandidate], list[SkippedRow], Counter[str]]:
    repairs: list[RepairCandidate] = []
    skipped: list[SkippedRow] = []
    pattern_counts: Counter[str] = Counter()

    for row in rows:
        patterns = detect_corruption_patterns(row.content_markdown)
        pattern_counts.update(patterns)
        result = roundtrip_results[row.lesson_id]

        if result.error:
            skipped.append(
                SkippedRow(
                    lesson_id=row.lesson_id,
                    lesson_title=row.lesson_title,
                    patterns=patterns,
                    reason="parse_failed",
                    detail=result.error,
                )
            )
            continue

        repaired = result.canonical_markdown
        if repaired is None:
            skipped.append(
                SkippedRow(
                    lesson_id=row.lesson_id,
                    lesson_title=row.lesson_title,
                    patterns=patterns,
                    reason="roundtrip_missing_output",
                    detail="canonical markdown missing",
                )
            )
            continue

        if repaired == row.content_markdown:
            continue

        repairable_patterns = tuple(
            pattern for pattern in patterns if pattern in REPAIRABLE_PATTERN_NAMES or pattern == "unbalanced_bold"
        )
        if not repairable_patterns:
            skipped.append(
                SkippedRow(
                    lesson_id=row.lesson_id,
                    lesson_title=row.lesson_title,
                    patterns=patterns,
                    reason="manual_review_required",
                    detail=(
                        "round-trip changed markdown, but no known auto-repairable "
                        "emphasis corruption pattern matched"
                    ),
                )
            )
            continue

        if _strip_emphasis_markup_for_comparison(row.content_markdown) != _strip_emphasis_markup_for_comparison(repaired):
            skipped.append(
                SkippedRow(
                    lesson_id=row.lesson_id,
                    lesson_title=row.lesson_title,
                    patterns=patterns,
                    reason="non_emphasis_change",
                    detail=(
                        "canonical round-trip changed markdown structure beyond "
                        "emphasis markers; row requires manual review"
                    ),
                )
            )
            continue

        repairs.append(
            RepairCandidate(
                lesson_id=row.lesson_id,
                lesson_title=row.lesson_title,
                patterns=repairable_patterns,
                before=row.content_markdown,
                after=repaired,
                plain_text=result.plain_text or "",
                diff=_render_diff(row.content_markdown, repaired),
            )
        )

    return repairs, skipped, pattern_counts


def print_pattern_summary(pattern_counts: Counter[str]) -> None:
    print("CORRUPTION PATTERNS")
    if not pattern_counts:
        print("- none detected in scanned rows")
    else:
        for spec in PATTERN_SPECS:
            count = pattern_counts.get(spec.name, 0)
            print(f"- {spec.name}: {count} ({spec.description})")
        print(
            f"- unbalanced_bold: {pattern_counts.get('unbalanced_bold', 0)} "
            "(unmatched or nested ** delimiters)"
        )
    print(
        "- bold_used_where_italic_intended: not deterministically machine-detectable "
        "from stored markdown alone; auto-repair intentionally skipped"
    )
    print()


def print_repair_report(repairs: list[RepairCandidate], skipped: list[SkippedRow]) -> None:
    print("REPAIR CANDIDATES")
    if not repairs:
        print("- no deterministic auto-repair candidates found")
    for repair in repairs:
        print(f"\nlesson_id: {repair.lesson_id}")
        print(f"title: {_format_title(repair.lesson_title)}")
        print(f"patterns: {', '.join(repair.patterns)}")
        print("original markdown:")
        print(repair.before or "<empty>")
        print("repaired markdown:")
        print(repair.after or "<empty>")
        print("diff:")
        print(repair.diff)

    if skipped:
        print("\nSKIPPED ROWS")
        for row in skipped:
            patterns = ", ".join(row.patterns) if row.patterns else "<none>"
            print(
                f"- {row.lesson_id} ({_format_title(row.lesson_title)}): "
                f"{row.reason}; patterns={patterns}; detail={row.detail}"
            )
    print()


def _write_updates_csv(repairs: list[RepairCandidate]) -> Path:
    handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        suffix=".csv",
        delete=False,
    )
    with handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=("lesson_id", "expected_content_markdown", "new_content_markdown"),
        )
        writer.writeheader()
        for repair in repairs:
            writer.writerow(
                {
                    "lesson_id": repair.lesson_id,
                    "expected_content_markdown": repair.before,
                    "new_content_markdown": repair.after,
                }
            )
    return Path(handle.name)


def apply_repairs(db_url: str, repairs: list[RepairCandidate]) -> None:
    if not repairs:
        print("No repairs to apply.")
        return

    csv_path = _write_updates_csv(repairs)
    sql_path = None
    try:
        csv_sql_path = csv_path.as_posix().replace("'", "''")
        sql_handle = tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            newline="\n",
            suffix=".sql",
            delete=False,
        )
        sql_path = Path(sql_handle.name)
        with sql_handle:
            sql_handle.write("\\set ON_ERROR_STOP on\n")
            sql_handle.write("begin;\n")
            sql_handle.write(
                "create temp table repair_updates (\n"
                "  lesson_id uuid not null,\n"
                "  expected_content_markdown text not null,\n"
                "  new_content_markdown text not null\n"
                ") on commit drop;\n"
            )
            sql_handle.write(
                "\\copy repair_updates (lesson_id, expected_content_markdown, new_content_markdown) "
                f"from '{csv_sql_path}' with (format csv, header true)\n"
            )
            sql_handle.write(
                "do $$\n"
                "declare\n"
                "  expected_count integer;\n"
                "  updated_count integer;\n"
                "begin\n"
                "  select count(*) into expected_count from repair_updates;\n"
                "  with updated as (\n"
                "    update app.lesson_contents as lc\n"
                "    set content_markdown = ru.new_content_markdown\n"
                "    from repair_updates as ru\n"
                "    where lc.lesson_id = ru.lesson_id\n"
                "      and coalesce(lc.content_markdown, '') = ru.expected_content_markdown\n"
                "      and coalesce(lc.content_markdown, '') <> ru.new_content_markdown\n"
                "    returning 1\n"
                "  )\n"
                "  select count(*) into updated_count from updated;\n"
                "  if updated_count <> expected_count then\n"
                "    raise exception 'repair_lesson_markdown stale mismatch: updated %, expected %', "
                "updated_count, expected_count;\n"
                "  end if;\n"
                "end $$;\n"
            )
            sql_handle.write("commit;\n")

        completed = subprocess.run(
            ["psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-f", str(sql_path), db_url],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if completed.returncode != 0:
            raise RuntimeError(completed.stderr.strip() or "psql apply failed")
    finally:
        csv_path.unlink(missing_ok=True)
        if sql_path is not None:
            sql_path.unlink(missing_ok=True)


def main() -> int:
    args = parse_args()
    frontend_dir = Path(args.frontend_dir).resolve()
    roundtrip_command = [str(part) for part in args.roundtrip_command]
    db_url = _resolve_db_url(args)
    _ensure_tooling(frontend_dir, roundtrip_command)
    resolved_executable = shutil.which(roundtrip_command[0])
    if resolved_executable:
        roundtrip_command[0] = resolved_executable

    rows = _fetch_lessons(db_url, limit=args.limit)
    roundtrip_results = roundtrip_lessons(
        frontend_dir,
        roundtrip_command,
        rows,
        batch_size=max(1, args.batch_size),
    )
    repairs, skipped, pattern_counts = build_repair_plan(rows, roundtrip_results)

    print_pattern_summary(pattern_counts)
    print("REPAIR STRATEGY")
    print("- Markdown -> Delta/Document via frontend adapter")
    print("- Delta/Document -> canonical Markdown via frontend adapter")
    print("- update only when canonical Markdown differs from stored Markdown")
    print("- skip parse failures and rows with no deterministic repairable pattern")
    print()
    print_repair_report(repairs, skipped)

    print("SUMMARY")
    print(f"- scanned rows: {len(rows)}")
    print(f"- repair candidates: {len(repairs)}")
    print(f"- skipped rows: {len(skipped)}")
    print(
        f"- execution mode: {'apply' if args.apply else 'dry-run'} "
        f"(db host: {urlparse(db_url).hostname or '<unknown>'})"
    )
    print()

    if args.apply:
        apply_repairs(db_url, repairs)
        print(f"Applied {len(repairs)} repair(s).")
    else:
        print("Dry-run only. No database writes were made.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
