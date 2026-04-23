from __future__ import annotations

import re
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class AuthorityFinding:
    scope: str
    token: str
    detail: str


def read_repo_text(repo_root: Path, relative_path: str) -> str:
    return (repo_root / relative_path).read_text(encoding="utf-8")


def forbidden_token_findings(
    source: str,
    *,
    scope: str,
    tokens: Iterable[str],
) -> list[AuthorityFinding]:
    stripped = _strip_comments(source)
    return [
        AuthorityFinding(scope=scope, token=token, detail="forbidden token present")
        for token in tokens
        if token in stripped
    ]


def forbidden_regex_findings(
    source: str,
    *,
    scope: str,
    patterns: Iterable[str],
) -> list[AuthorityFinding]:
    stripped = _strip_comments(source)
    findings: list[AuthorityFinding] = []
    for pattern in patterns:
        if re.search(pattern, stripped, flags=re.IGNORECASE | re.MULTILINE):
            findings.append(
                AuthorityFinding(
                    scope=scope,
                    token=pattern,
                    detail="forbidden pattern present",
                )
            )
    return findings


def missing_token_findings(
    source: str,
    *,
    scope: str,
    tokens: Iterable[str],
) -> list[AuthorityFinding]:
    stripped = _strip_comments(source)
    return [
        AuthorityFinding(scope=scope, token=token, detail="required token missing")
        for token in tokens
        if token not in stripped
    ]


def dart_source_block(source: str, needle: str) -> str:
    try:
        start = source.index(needle)
    except ValueError as exc:
        raise AssertionError(f"Missing source block: {needle}") from exc

    body_match = re.search(r"\)\s*(?:async\s*)?\{", source[start:])
    if body_match is None:
        raise AssertionError(f"Missing opening brace for source block: {needle}")
    opening = start + body_match.end() - 1

    depth = 0
    for index in range(opening, len(source)):
        char = source[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[opening : index + 1]

    raise AssertionError(f"Unterminated source block: {needle}")


def python_decorated_function_block(source: str, function_name: str) -> str:
    match = re.search(
        rf"(?:^@\w[^\n]*\n)*^async def {re.escape(function_name)}\(",
        source,
        flags=re.MULTILINE,
    )
    if match is None:
        raise AssertionError(f"Missing async function block: {function_name}")
    start = match.start()
    next_match = re.search(r"\n\n(?:@\w|async def |def |class )", source[match.end() :])
    if next_match is None:
        return source[start:]
    return source[start : match.end() + next_match.start()]


def assert_no_findings(findings: Iterable[AuthorityFinding]) -> None:
    finding_list = list(findings)
    if not finding_list:
        return
    rendered = "\n".join(
        f"{finding.scope}: {finding.token} ({finding.detail})"
        for finding in finding_list
    )
    raise AssertionError(rendered)


def _strip_comments(source: str) -> str:
    without_block_comments = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    lines: list[str] = []
    for line in without_block_comments.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//") or stripped.startswith("#"):
            lines.append("")
            continue
        lines.append(line)
    return "\n".join(lines)
