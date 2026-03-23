#!/usr/bin/env python3
"""Phase 5 historical remediation for unrecoverable missing-source assets.

This command is conservative by default:
- reads candidate scope via SQL only
- validates each candidate through local MCP read surfaces before mutation
- mutates only through repository contracts
- writes a session ledger after each mutation before any further reads
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Sequence
from uuid import uuid4

import psycopg
from psycopg.rows import dict_row


ROOT_DIR = Path(__file__).resolve().parents[1]
REPO_DIR = ROOT_DIR.parent
DEFAULT_BACKEND_URL = "http://127.0.0.1:8080"
DEFAULT_OUTPUT_DIR = REPO_DIR / "reports" / "phase5-remediation"
MCP_PROTOCOL_VERSION = "2025-03-26"
MAX_BATCH_SIZE = 5
SAFE_PURPOSES = ("lesson_audio", "lesson_media", "home_player_audio")

if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from app.db import pool  # noqa: E402
from app.repositories import media_assets as media_assets_repo  # noqa: E402


@dataclass(slots=True)
class CandidateRow:
    asset_id: str
    course_id: str | None
    lesson_id: str | None
    purpose: str
    media_type: str
    state: str
    storage_bucket: str | None
    original_object_path: str | None
    streaming_storage_bucket: str | None
    streaming_object_path: str | None
    error_message: str | None
    created_at: str
    updated_at: str
    source_exists: bool
    playback_exists: bool
    lesson_media_ref_count: int
    active_runtime_ref_count: int
    active_home_upload_ref_count: int
    remediation_bucket: str


def now_iso() -> str:
    return datetime.now(UTC).isoformat()


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Safely transition unrecoverable missing-source uploaded assets to failed.",
    )
    parser.add_argument(
        "--backend-url",
        default=os.getenv("BACKEND_BASE_URL", DEFAULT_BACKEND_URL),
        help=f"Backend base URL (default: {DEFAULT_BACKEND_URL}).",
    )
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL") or os.getenv("SUPABASE_DB_URL"),
        help="Database URL (default: $DATABASE_URL or $SUPABASE_DB_URL).",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help=f"Report output directory (default: {DEFAULT_OUTPUT_DIR}).",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=5,
        help=f"Batch size per verified batch (max {MAX_BATCH_SIZE}).",
    )
    parser.add_argument(
        "--max-batches",
        type=int,
        default=None,
        help="Optional cap on number of verified batches to process.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Persist mutations. Default is dry-run.",
    )
    return parser.parse_args(argv)


def ensure_database_url(args: argparse.Namespace) -> str:
    if not args.database_url:
        raise SystemExit("DATABASE_URL or SUPABASE_DB_URL is required")
    return str(args.database_url).strip()


def normalize_violation_signature(item: dict[str, Any]) -> tuple[str, str, str, str, str, str, str]:
    return (
        str(item.get("code") or ""),
        str(item.get("severity") or ""),
        str(item.get("source") or ""),
        str(item.get("course_id") or ""),
        str(item.get("lesson_id") or ""),
        str(item.get("asset_id") or ""),
        str(item.get("runtime_media_id") or ""),
    )


def verification_signatures(payload: dict[str, Any]) -> list[tuple[str, str, str, str, str, str, str]]:
    return sorted(
        normalize_violation_signature(item)
        for item in payload.get("violations") or []
    )


def write_json(path: Path, payload: Any) -> None:
    def _default(value: Any) -> Any:
        if isinstance(value, datetime):
            if value.tzinfo is None:
                value = value.replace(tzinfo=UTC)
            return value.isoformat()
        return str(value)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            payload,
            indent=2,
            ensure_ascii=False,
            sort_keys=True,
            default=_default,
        )
        + "\n",
        encoding="utf-8",
    )


def hpu_visibility_sql(db_url: str) -> str:
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select column_name
                from information_schema.columns
                where table_schema = 'app'
                  and table_name = 'home_player_uploads'
                """
            )
            columns = {str(row["column_name"]) for row in cur.fetchall()}
    if {"is_test", "test_session_id"} <= columns:
        return "app.is_test_row_visible(hpu.is_test, hpu.test_session_id)"
    return "true"


def candidate_sql(*, hpu_visibility: str, where_clause: str) -> str:
    purposes = ", ".join(f"'{value}'" for value in SAFE_PURPOSES)
    return f"""
        with asset_refs as (
          select
            ma.id::text as asset_id,
            ma.course_id::text as course_id,
            ma.lesson_id::text as lesson_id,
            lower(coalesce(ma.purpose, '')) as purpose,
            lower(coalesce(ma.media_type, '')) as media_type,
            lower(coalesce(ma.state, '')) as state,
            ma.storage_bucket,
            ma.original_object_path,
            ma.streaming_storage_bucket,
            ma.streaming_object_path,
            ma.error_message,
            ma.created_at,
            ma.updated_at,
            exists (
              select 1
              from storage.objects so
              where so.bucket_id = ma.storage_bucket
                and so.name = ma.original_object_path
            ) as source_exists,
            exists (
              select 1
              from storage.objects so
              where so.bucket_id = coalesce(ma.streaming_storage_bucket, ma.storage_bucket)
                and so.name = ma.streaming_object_path
            ) as playback_exists,
            count(distinct lm.id) as lesson_media_ref_count,
            count(distinct rm.id) filter (where coalesce(rm.active, true)) as active_runtime_ref_count,
            count(distinct hpu.id) filter (where coalesce(hpu.active, true)) as active_home_upload_ref_count
          from app.media_assets ma
          left join app.lesson_media lm
            on lm.media_asset_id = ma.id
           and app.is_test_row_visible(lm.is_test, lm.test_session_id)
          left join app.runtime_media rm
            on rm.media_asset_id = ma.id
           and app.is_test_row_visible(rm.is_test, rm.test_session_id)
          left join app.home_player_uploads hpu
            on hpu.media_asset_id = ma.id
           and {hpu_visibility}
          where lower(coalesce(ma.state, '')) = 'uploaded'
            and lower(coalesce(ma.purpose, '')) in ({purposes})
            and app.is_test_row_visible(ma.is_test, ma.test_session_id)
          group by
            ma.id,
            ma.course_id,
            ma.lesson_id,
            ma.purpose,
            ma.media_type,
            ma.state,
            ma.storage_bucket,
            ma.original_object_path,
            ma.streaming_storage_bucket,
            ma.streaming_object_path,
            ma.error_message,
            ma.created_at,
            ma.updated_at
        ),
        classified as (
          select
            *,
            case
              when source_exists or playback_exists then 'recoverable'
              when lesson_media_ref_count > 0 or active_runtime_ref_count > 0 or active_home_upload_ref_count > 0 then 'blocked_contract_risk'
              else 'unrecoverable_missing_source'
            end as remediation_bucket
          from asset_refs
          where not source_exists
        )
        {where_clause}
    """


def load_scope_summary(db_url: str, *, hpu_visibility: str) -> list[dict[str, Any]]:
    query = candidate_sql(
        hpu_visibility=hpu_visibility,
        where_clause="""
            select
              remediation_bucket,
              count(*) as asset_count,
              min(created_at) as oldest_created_at,
              max(updated_at) as newest_updated_at
            from classified
            group by remediation_bucket
            order by remediation_bucket
        """,
    )
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            rows = cur.fetchall()
    return [dict(row) for row in rows]


def load_candidates(db_url: str, *, hpu_visibility: str, limit: int) -> list[CandidateRow]:
    query = candidate_sql(
        hpu_visibility=hpu_visibility,
        where_clause="""
            select *
            from classified
            where remediation_bucket = 'unrecoverable_missing_source'
            order by created_at asc, asset_id asc
            limit %s
        """,
    )
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (limit,))
            rows = cur.fetchall()
    return [CandidateRow(**dict(row)) for row in rows]


def count_remaining_unrecoverable(db_url: str, *, hpu_visibility: str) -> int:
    query = candidate_sql(
        hpu_visibility=hpu_visibility,
        where_clause="""
            select count(*) as remaining_count
            from classified
            where remediation_bucket = 'unrecoverable_missing_source'
        """,
    )
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            row = cur.fetchone()
    return int(row["remaining_count"] or 0) if row else 0


def count_processed_still_uploaded_missing(db_url: str, asset_ids: list[str]) -> int:
    if not asset_ids:
        return 0
    query = """
        select count(*) as remaining_count
        from app.media_assets ma
        where ma.id = any(%s::uuid[])
          and lower(coalesce(ma.state, '')) = 'uploaded'
          and not exists (
            select 1
            from storage.objects so
            where so.bucket_id = ma.storage_bucket
              and so.name = ma.original_object_path
          )
    """
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query, (asset_ids,))
            row = cur.fetchone()
    return int(row["remaining_count"] or 0) if row else 0


def load_verification_subjects(db_url: str) -> dict[str, list[str]]:
    query = """
        with lesson_cases as (
          select l.id::text as lesson_id
          from app.lessons l
          join app.lesson_media lm on lm.lesson_id = l.id
          where app.is_test_row_visible(l.is_test, l.test_session_id)
            and app.is_test_row_visible(lm.is_test, lm.test_session_id)
          group by l.id, l.created_at
          order by l.created_at asc, l.id asc
          limit 2
        ),
        course_cases as (
          select c.id::text as course_id
          from app.courses c
          where c.cover_media_id is not null
            and app.is_test_row_visible(c.is_test, c.test_session_id)
          order by c.created_at asc, c.id asc
          limit 2
        )
        select json_build_object(
          'lesson_ids', (select json_agg(lesson_id order by lesson_id) from lesson_cases),
          'course_ids', (select json_agg(course_id order by course_id) from course_cases)
        ) as payload
    """
    with psycopg.connect(db_url, row_factory=dict_row) as conn:
        with conn.cursor() as cur:
            cur.execute(query)
            row = cur.fetchone()
    payload = dict(row["payload"] or {}) if row else {}
    return {
        "lesson_ids": [str(value) for value in payload.get("lesson_ids") or []],
        "course_ids": [str(value) for value in payload.get("course_ids") or []],
    }


class MCPClient:
    def __init__(self, backend_url: str) -> None:
        self._backend_url = backend_url.rstrip("/")

    async def close(self) -> None:
        return None

    def _call_tool_sync(self, route: str, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        payload = json.dumps(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": {
                    "name": tool_name,
                    "arguments": arguments,
                },
            }
        ).encode("utf-8")
        completed = subprocess.run(
            [
                "curl",
                "-sS",
                "--max-time",
                "240",
                f"{self._backend_url}{route}",
                "-H",
                "Content-Type: application/json",
                "-H",
                f"MCP-Protocol-Version: {MCP_PROTOCOL_VERSION}",
                "-H",
                "Connection: close",
                "--data-binary",
                payload.decode("utf-8"),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        body = completed.stdout
        parsed_payload = json.loads(body)
        if "error" in parsed_payload:
            raise RuntimeError(f"{route}:{tool_name} JSON-RPC error: {parsed_payload['error']}")
        result = parsed_payload.get("result") or {}
        content = result.get("content") or []
        text_payload = content[0].get("text") if content else None
        parsed = json.loads(text_payload) if text_payload else {}
        if result.get("isError"):
            raise RuntimeError(f"{route}:{tool_name} tool error: {parsed}")
        return parsed

    async def call_tool(self, route: str, tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        return await asyncio.to_thread(
            self._call_tool_sync,
            route,
            tool_name,
            arguments,
        )


def storage_check_map(payload: dict[str, Any]) -> dict[str, dict[str, Any]]:
    checks = payload.get("storage_verification", {}).get("checks") or []
    return {
        str(item.get("label")): dict(item)
        for item in checks
        if item.get("label")
    }


def summarize_asset_state(row: dict[str, Any] | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {
        "asset_id": str(row.get("id") or ""),
        "state": row.get("state"),
        "error_message": row.get("error_message"),
        "updated_at": row.get("updated_at").isoformat() if row.get("updated_at") else None,
    }


async def preverify_candidate(
    mcp: MCPClient,
    candidate: CandidateRow,
) -> dict[str, Any]:
    media_payload = await mcp.call_tool(
        "/mcp/media-control-plane",
        "get_asset",
        {"asset_id": candidate.asset_id},
    )
    domain_payload = await mcp.call_tool(
        "/mcp/domain-observability",
        "inspect_media",
        {"asset_id": candidate.asset_id},
    )
    checks = storage_check_map(media_payload)
    source_check = checks.get("source") or {}
    playback_check = checks.get("playback") or {}

    failures: list[str] = []
    if candidate.state != "uploaded":
        failures.append(f"sql state is {candidate.state!r}, expected 'uploaded'")
    if candidate.source_exists:
        failures.append("SQL reported source_exists=true")
    if candidate.playback_exists:
        failures.append("SQL reported playback_exists=true")
    if candidate.lesson_media_ref_count != 0:
        failures.append("SQL reported lesson_media references")
    if candidate.active_runtime_ref_count != 0:
        failures.append("SQL reported active runtime_media references")
    if candidate.active_home_upload_ref_count != 0:
        failures.append("SQL reported active home_player_upload references")
    if (media_payload.get("asset") or {}).get("state") != "uploaded":
        failures.append("Media MCP asset.state is not 'uploaded'")
    if bool(source_check.get("exists")):
        failures.append("Media MCP source check exists=true")
    if bool(playback_check.get("exists")):
        failures.append("Media MCP playback check exists=true")
    if media_payload.get("lesson_media_references"):
        failures.append("Media MCP reported lesson_media references")
    if media_payload.get("runtime_projection"):
        failures.append("Media MCP reported runtime projections")
    if (domain_payload.get("state_summary") or {}).get("lesson_media_count") != 0:
        failures.append("Domain MCP reported lesson_media_count != 0")
    if (domain_payload.get("state_summary") or {}).get("runtime_media_count") != 0:
        failures.append("Domain MCP reported runtime_media_count != 0")
    if domain_payload.get("status") not in {"ok", "warning"}:
        failures.append(f"Domain MCP status was {domain_payload.get('status')!r}")

    return {
        "asset_id": candidate.asset_id,
        "preverified_at": now_iso(),
        "sql": asdict(candidate),
        "media_mcp": {
            "state_classification": media_payload.get("state_classification"),
            "asset_state": (media_payload.get("asset") or {}).get("state"),
            "lesson_media_reference_count": len(media_payload.get("lesson_media_references") or []),
            "runtime_projection_count": len(media_payload.get("runtime_projection") or []),
            "storage_verification": media_payload.get("storage_verification"),
        },
        "domain_mcp": {
            "status": domain_payload.get("status"),
            "state_summary": domain_payload.get("state_summary"),
            "violations": domain_payload.get("violations"),
        },
        "recovery_candidate_inference": {
            "inference": (
                "No recovery candidate at the asset-contract layer is inferred from "
                "SQL source/playback absence plus Media MCP storage checks."
            ),
            "source_exists": candidate.source_exists,
            "playback_exists": candidate.playback_exists,
        },
        "failures": failures,
    }


async def verify_sampled_truth(mcp: MCPClient, db_url: str) -> dict[str, Any]:
    subjects = load_verification_subjects(db_url)
    lesson_ids = subjects["lesson_ids"]
    course_ids = subjects["course_ids"]

    lesson_results: list[dict[str, Any]] = []
    for lesson_id in lesson_ids:
        lesson_results.append(
            await mcp.call_tool(
                "/mcp/verification",
                "verify_lesson_media_truth",
                {"lesson_id": lesson_id},
            )
        )

    course_results: list[dict[str, Any]] = []
    for course_id in course_ids:
        course_results.append(
            await mcp.call_tool(
                "/mcp/verification",
                "verify_course_cover_truth",
                {"course_id": course_id},
            )
        )

    combined_violations: list[dict[str, Any]] = []
    for payload in lesson_results + course_results:
        combined_violations.extend(payload.get("violations") or [])

    return {
        "generated_at": now_iso(),
        "verification": {
            "tool": "phase5_sampled_truth",
            "version": "1",
        },
        "cases": {
            "lesson_ids": lesson_ids,
            "course_ids": course_ids,
        },
        "lesson_results": lesson_results,
        "course_results": course_results,
        "violations": combined_violations,
    }


def verification_delta(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    before_signatures = verification_signatures(before)
    after_signatures = verification_signatures(after)
    before_set = set(before_signatures)
    after_set = set(after_signatures)
    new_signatures = sorted(after_set - before_set)
    return {
        "before_verdict": before.get("verdict"),
        "after_verdict": after.get("verdict"),
        "before_signatures": before_signatures,
        "after_signatures": after_signatures,
        "new_signatures": new_signatures,
        "no_new_violations": len(new_signatures) == 0,
    }


def render_markdown(ledger: dict[str, Any]) -> str:
    lines = [
        "# Phase 5 Remediation",
        "",
        f"- session_id: {ledger['session_id']}",
        f"- apply: {ledger['apply']}",
        f"- started_at: {ledger['started_at']}",
        f"- finished_at: {ledger.get('finished_at')}",
        f"- assets_processed: {ledger['summary']['assets_processed']}",
        f"- remaining_unrecoverable_missing_source: {ledger['summary']['remaining_unrecoverable_missing_source']}",
        f"- blocked_contract_risk_remaining: {ledger['summary']['blocked_contract_risk_remaining']}",
        f"- verification_no_new_violations: {ledger['summary']['verification_no_new_violations']}",
        "",
        "## Batches",
        "",
    ]
    for batch in ledger.get("batches") or []:
        lines.extend(
            [
                f"### Batch {batch['batch_index']}",
                "",
                f"- selected_assets: {len(batch.get('selected_asset_ids') or [])}",
                f"- processed_assets: {len(batch.get('processed_asset_ids') or [])}",
                f"- processed_assets_still_uploaded_missing: {batch['sql_verification']['processed_assets_still_uploaded_missing']}",
                f"- verification_no_new_violations: {batch['verification_delta']['no_new_violations']}",
                "",
            ]
        )
    return "\n".join(lines) + "\n"


async def run(args: argparse.Namespace) -> int:
    if args.batch_size < 1 or args.batch_size > MAX_BATCH_SIZE:
        raise SystemExit(f"--batch-size must be between 1 and {MAX_BATCH_SIZE}")
    if args.max_batches is not None and args.max_batches < 1:
        raise SystemExit("--max-batches must be >= 1 when provided")

    db_url = ensure_database_url(args)
    backend_url = str(args.backend_url).strip() or DEFAULT_BACKEND_URL
    session_id = str(uuid4())
    session_dir = Path(args.output_dir).expanduser().resolve() / f"{now_iso().replace(':', '').replace('+00:00', 'Z')}-{session_id}"
    session_dir.mkdir(parents=True, exist_ok=True)
    ledger_path = session_dir / "session-ledger.json"
    markdown_path = session_dir / "summary.md"
    hpu_visibility = hpu_visibility_sql(db_url)

    ledger: dict[str, Any] = {
        "session_id": session_id,
        "apply": bool(args.apply),
        "started_at": now_iso(),
        "backend_url": backend_url,
        "database_url_source": "DATABASE_URL_or_SUPABASE_DB_URL",
        "selection_contract": {
            "scope": "unrecoverable_missing_source",
            "excluded": ["blocked_contract_risk", "recoverable", "ambiguous"],
            "sql_hpu_visibility_predicate": hpu_visibility,
            "batch_size": args.batch_size,
            "max_batches": args.max_batches,
        },
        "pre_verification": {
            "scope_summary": load_scope_summary(db_url, hpu_visibility=hpu_visibility),
            "verification_baseline": None,
            "gaps": [
                "media-control-plane.list_orphaned_assets is currently broken in this environment because app.home_player_uploads lacks is_test/test_session_id columns; using get_asset per selected asset instead."
            ],
        },
        "batches": [],
        "summary": {
            "assets_processed": 0,
            "remaining_unrecoverable_missing_source": count_remaining_unrecoverable(db_url, hpu_visibility=hpu_visibility),
            "blocked_contract_risk_remaining": next(
                (
                    int(item["asset_count"])
                    for item in load_scope_summary(db_url, hpu_visibility=hpu_visibility)
                    if item["remediation_bucket"] == "blocked_contract_risk"
                ),
                0,
            ),
            "verification_no_new_violations": True,
        },
    }
    write_json(ledger_path, ledger)

    mcp = MCPClient(backend_url)
    await pool.open()

    try:
        baseline_verification = await verify_sampled_truth(mcp, db_url)
        ledger["pre_verification"]["verification_baseline"] = baseline_verification
        write_json(ledger_path, ledger)

        previous_verification = baseline_verification
        batch_index = 0

        while True:
            if args.max_batches is not None and batch_index >= args.max_batches:
                break

            candidates = load_candidates(
                db_url,
                hpu_visibility=hpu_visibility,
                limit=args.batch_size,
            )
            if not candidates:
                break

            batch_index += 1
            batch_record: dict[str, Any] = {
                "batch_index": batch_index,
                "started_at": now_iso(),
                "selected_asset_ids": [candidate.asset_id for candidate in candidates],
                "assets": [],
                "processed_asset_ids": [],
            }
            ledger["batches"].append(batch_record)
            write_json(ledger_path, ledger)

            for candidate in candidates:
                asset_record: dict[str, Any] = {
                    "asset_id": candidate.asset_id,
                    "selected_at": now_iso(),
                }
                batch_record["assets"].append(asset_record)

                precheck = await preverify_candidate(mcp, candidate)
                asset_record["precheck"] = precheck
                if precheck["failures"]:
                    asset_record["aborted"] = True
                    asset_record["abort_reason"] = "precheck_failed"
                    write_json(ledger_path, ledger)
                    raise RuntimeError(
                        f"Precheck failed for {candidate.asset_id}: {precheck['failures']}"
                    )

                before_row = await media_assets_repo.get_media_asset(candidate.asset_id)
                asset_record["state_before"] = summarize_asset_state(before_row)

                if args.apply:
                    await media_assets_repo.mark_media_asset_failed(
                        media_id=candidate.asset_id,
                        error_message="missing_source",
                    )
                    asset_record["mutation"] = {
                        "applied": True,
                        "mutated_at": now_iso(),
                        "state_after_pending_reads": True,
                    }
                else:
                    asset_record["mutation"] = {
                        "applied": False,
                        "mutated_at": now_iso(),
                        "reason": "dry_run",
                    }

                write_json(ledger_path, ledger)

                after_row = await media_assets_repo.get_media_asset(candidate.asset_id)
                asset_record["state_after"] = summarize_asset_state(after_row)

                post_media = await mcp.call_tool(
                    "/mcp/media-control-plane",
                    "get_asset",
                    {"asset_id": candidate.asset_id},
                )
                post_checks = storage_check_map(post_media)
                source_check = post_checks.get("source") or {}
                playback_check = post_checks.get("playback") or {}
                post_failures: list[str] = []
                expected_state = "failed" if args.apply else "uploaded"
                if (post_media.get("asset") or {}).get("state") != expected_state:
                    post_failures.append(
                        f"post Media MCP asset.state expected {expected_state!r}"
                    )
                if bool(source_check.get("exists")):
                    post_failures.append("post Media MCP source exists=true")
                if bool(playback_check.get("exists")):
                    post_failures.append("post Media MCP playback exists=true")
                if post_media.get("lesson_media_references"):
                    post_failures.append("post Media MCP reported lesson_media references")
                if post_media.get("runtime_projection"):
                    post_failures.append("post Media MCP reported runtime projections")
                if args.apply and (after_row or {}).get("state") != "failed":
                    post_failures.append("repository state_after was not failed")
                if args.apply and (after_row or {}).get("error_message") != "missing_source":
                    post_failures.append("repository error_message was not missing_source")

                asset_record["postcheck"] = {
                    "checked_at": now_iso(),
                    "media_mcp": {
                        "state_classification": post_media.get("state_classification"),
                        "asset_state": (post_media.get("asset") or {}).get("state"),
                        "storage_verification": post_media.get("storage_verification"),
                    },
                    "failures": post_failures,
                }
                batch_record["processed_asset_ids"].append(candidate.asset_id)
                if post_failures:
                    write_json(ledger_path, ledger)
                    raise RuntimeError(
                        f"Postcheck failed for {candidate.asset_id}: {post_failures}"
                    )

                write_json(ledger_path, ledger)

            processed_asset_ids = list(batch_record["processed_asset_ids"])
            after_verification = await verify_sampled_truth(mcp, db_url)
            delta = verification_delta(previous_verification, after_verification)
            sql_remaining = count_processed_still_uploaded_missing(db_url, processed_asset_ids)
            batch_record["verification_after"] = after_verification
            batch_record["verification_delta"] = delta
            batch_record["sql_verification"] = {
                "checked_at": now_iso(),
                "processed_assets_still_uploaded_missing": sql_remaining,
                "expected_remaining_uploaded_missing": 0 if args.apply else len(processed_asset_ids),
            }
            batch_record["completed_at"] = now_iso()

            expected_remaining = 0 if args.apply else len(processed_asset_ids)
            if sql_remaining != expected_remaining:
                write_json(ledger_path, ledger)
                raise RuntimeError(
                    "SQL verification failed for batch "
                    f"{batch_index}: expected {expected_remaining} processed assets "
                    f"to remain uploaded+missing, observed {sql_remaining}"
                )
            if not delta["no_new_violations"]:
                write_json(ledger_path, ledger)
                raise RuntimeError(
                    f"Verification MCP detected new violations after batch {batch_index}: {delta['new_signatures']}"
                )

            previous_verification = after_verification
            ledger["summary"]["assets_processed"] += len(processed_asset_ids)
            ledger["summary"]["remaining_unrecoverable_missing_source"] = count_remaining_unrecoverable(
                db_url,
                hpu_visibility=hpu_visibility,
            )
            ledger["summary"]["verification_no_new_violations"] = bool(
                ledger["summary"]["verification_no_new_violations"] and delta["no_new_violations"]
            )
            write_json(ledger_path, ledger)

        ledger["finished_at"] = now_iso()
        write_json(ledger_path, ledger)
        markdown_path.write_text(render_markdown(ledger), encoding="utf-8")

        summary = {
            "session_id": session_id,
            "apply": bool(args.apply),
            "assets_processed": ledger["summary"]["assets_processed"],
            "remaining_unrecoverable_missing_source": ledger["summary"]["remaining_unrecoverable_missing_source"],
            "blocked_contract_risk_remaining": ledger["summary"]["blocked_contract_risk_remaining"],
            "verification_no_new_violations": ledger["summary"]["verification_no_new_violations"],
            "ledger_path": str(ledger_path),
            "markdown_path": str(markdown_path),
        }
        print(json.dumps(summary, indent=2, ensure_ascii=False))
        return 0
    finally:
        await mcp.close()
        await pool.close()


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    return asyncio.run(run(args))


if __name__ == "__main__":
    raise SystemExit(main())
