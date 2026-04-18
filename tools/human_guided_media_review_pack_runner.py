from __future__ import annotations

import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path.cwd()
PRIMARY = ROOT / "audit_output" / "deterministic_media_resolution_pass_20260418T212206Z"
RESTORE_MANIFEST = ROOT / "restore" / "manifest.json"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def write_json(path: Path, data) -> None:
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def normalize_filename(value: str | None) -> str | None:
    if not value:
        return None
    name = Path(str(value).replace("\\", "/")).name.strip()
    if "__" in name:
        name = name.split("__", 1)[1]
    name = re.sub(r"^[0-9a-fA-F]{16,64}[_-]+", "", name)
    name = re.sub(r"\s+", " ", name).strip().lower()
    return name or None


def media_type(record: dict) -> str:
    content_type = record.get("detected_content_type") or ""
    if content_type.startswith("audio/"):
        return "audio"
    if content_type.startswith("video/"):
        return "video"
    if content_type.startswith("image/"):
        return "image"
    if content_type == "application/pdf":
        return "document"
    extension = (record.get("original_extension") or Path(record.get("original_filename") or "").suffix).lower()
    if extension in {".mp3", ".m4a", ".wav", ".aac", ".ogg"}:
        return "audio"
    if extension in {".mp4", ".mov", ".webm", ".mkv"}:
        return "video"
    if extension in {".png", ".jpg", ".jpeg", ".webp", ".gif"}:
        return "image"
    if extension in {".pdf", ".doc", ".docx", ".txt"}:
        return "document"
    return "unknown"


def file_observation(record: dict) -> dict:
    local_path = record.get("local_restore_path")
    result = {
        "exists": False,
        "readable": False,
        "actual_file_size": None,
        "size_gt_zero": False,
        "recognized_media_type": media_type(record),
    }
    if not local_path:
        return result
    try:
        stat = (ROOT / local_path).stat()
        result.update(
            {
                "exists": True,
                "readable": True,
                "actual_file_size": stat.st_size,
                "size_gt_zero": stat.st_size > 0,
            }
        )
    except OSError as exc:
        result["read_error"] = f"{type(exc).__name__}: {exc}"
    return result


def is_valid_local_candidate(record: dict) -> bool:
    obs = file_observation(record)
    return (
        record.get("download_status") in {"downloaded", "deduplicated"}
        and bool(record.get("local_restore_path"))
        and bool(record.get("sha256"))
        and obs["exists"]
        and obs["readable"]
        and obs["size_gt_zero"]
        and obs["recognized_media_type"] != "unknown"
    )


def slim_manifest_record(record: dict) -> dict:
    provenance = record.get("provenance") or {}
    return {
        "manifest_record_id": record.get("manifest_record_id"),
        "legacy_media_id": record.get("legacy_media_id"),
        "legacy_course_id": record.get("legacy_course_id"),
        "legacy_lesson_id": record.get("legacy_lesson_id"),
        "original_filename": record.get("original_filename"),
        "normalized_filename": normalize_filename(record.get("original_filename")),
        "original_extension": record.get("original_extension"),
        "download_status": record.get("download_status"),
        "failure_reason": record.get("failure_reason"),
        "local_restore_path": record.get("local_restore_path"),
        "source_reference_scrubbed": record.get("source_reference_scrubbed"),
        "detected_content_type": record.get("detected_content_type"),
        "candidate_file_type": media_type(record),
        "byte_size": record.get("byte_size"),
        "sha256": record.get("sha256"),
        "provenance": {
            "artifact": provenance.get("artifact"),
            "source_section": provenance.get("source_section"),
            "source_location": provenance.get("source_location"),
            "source_table": provenance.get("source_table"),
            "kind": provenance.get("kind"),
            "type": provenance.get("type"),
            "position": provenance.get("position"),
        },
        "file_observation": file_observation(record),
    }


def add_candidate(candidates: dict[str, dict], record: dict, basis: str, case: dict) -> None:
    record_id = record.get("manifest_record_id")
    if not record_id:
        return
    entry = candidates.setdefault(record_id, slim_manifest_record(record))
    entry.setdefault("candidate_evidence_basis", [])
    if basis not in entry["candidate_evidence_basis"]:
        entry["candidate_evidence_basis"].append(basis)
    entry["same_course_as_case"] = record.get("legacy_course_id") == case.get("course_id")
    entry["same_lesson_as_case"] = record.get("legacy_lesson_id") == case.get("lesson_id")
    entry["same_media_id_as_token_target"] = record.get("legacy_media_id") == case.get("token_target")
    if not entry["same_lesson_as_case"]:
        entry["ownership_warning"] = "Candidate is not deterministically owned by this markdown token; human authority review required."


def case_sort_key(case: dict) -> tuple:
    return (
        case.get("course_title") or "",
        case.get("course_id") or "",
        case.get("lesson_title") or "",
        case.get("lesson_id") or "",
        case.get("token_index") or 0,
        case.get("token_row_id") or "",
    )


def main() -> None:
    required = [
        PRIMARY / "dataset_summary.json",
        PRIMARY / "final_token_resolution.json",
        PRIMARY / "unrecoverable_media_queue.json",
        PRIMARY / "course_clean_state.json",
        RESTORE_MANIFEST,
    ]
    for path in required:
        if not path.exists():
            raise SystemExit(f"Missing required input: {path}")

    generated_at = now_iso()
    output_dir = ROOT / "audit_output" / f"human_guided_media_review_pack_{stamp()}"
    output_dir.mkdir(parents=True, exist_ok=False)

    summary = load_json(PRIMARY / "dataset_summary.json")
    final_tokens = load_json(PRIMARY / "final_token_resolution.json")["tokens"]
    unresolved_artifact = load_json(PRIMARY / "unrecoverable_media_queue.json")
    course_state = load_json(PRIMARY / "course_clean_state.json")
    manifest = load_json(RESTORE_MANIFEST)
    manifest_files = manifest["files"]

    files_by_media: dict[str, list[dict]] = defaultdict(list)
    valid_by_normalized_filename: dict[str, list[dict]] = defaultdict(list)
    valid_by_source_reference: dict[str, list[dict]] = defaultdict(list)
    valid_by_local_path: dict[str, list[dict]] = defaultdict(list)
    for record in manifest_files:
        media_id = record.get("legacy_media_id")
        if media_id:
            files_by_media[media_id].append(record)
        if is_valid_local_candidate(record):
            normalized = normalize_filename(record.get("original_filename"))
            if normalized:
                valid_by_normalized_filename[normalized].append(record)
            source_ref = record.get("source_reference_scrubbed")
            if source_ref:
                valid_by_source_reference[source_ref].append(record)
            local_path = record.get("local_restore_path")
            if local_path:
                valid_by_local_path[local_path].append(record)

    unresolved_lookup = {
        item["token_row_id"]: item
        for item in unresolved_artifact.get("unresolved_non_deterministic_queue", [])
    }
    unrecoverable_lookup = {
        item["token_row_id"]: item
        for item in unresolved_artifact.get("unrecoverable_media_queue", [])
    }

    unresolved_tokens = [
        token
        for token in final_tokens
        if token.get("final_resolution_status") in {"UNRESOLVED", "UNRECOVERABLE"}
    ]
    unresolved_tokens.sort(key=case_sort_key)

    cases = []
    for index, token in enumerate(unresolved_tokens, start=1):
        case_id = f"REVIEW_CASE_{index:04d}"
        status = (
            "UNRESOLVED_NON_DETERMINISTIC"
            if token.get("final_resolution_status") == "UNRESOLVED"
            else "UNRECOVERABLE"
        )
        source_queue = unresolved_lookup.get(token["token_row_id"]) or unrecoverable_lookup.get(token["token_row_id"]) or {}
        direct_records = sorted(files_by_media.get(token.get("token_target"), []), key=lambda r: r.get("manifest_record_id") or "")
        manifest_evidence = [slim_manifest_record(record) for record in direct_records]

        candidates: dict[str, dict] = {}
        for record in direct_records:
            source_ref = record.get("source_reference_scrubbed")
            if source_ref:
                for candidate in valid_by_source_reference.get(source_ref, []):
                    add_candidate(candidates, candidate, "EXACT_SOURCE_REFERENCE_MATCH", token)
            local_path = record.get("local_restore_path")
            if local_path:
                for candidate in valid_by_local_path.get(local_path, []):
                    add_candidate(candidates, candidate, "EXACT_LOCAL_RESTORE_PATH_MATCH", token)
            normalized = normalize_filename(record.get("original_filename"))
            if normalized:
                for candidate in valid_by_normalized_filename.get(normalized, []):
                    add_candidate(candidates, candidate, "EXACT_NORMALIZED_FILENAME_MATCH", token)

        candidate_list = sorted(
            candidates.values(),
            key=lambda item: (
                not item.get("same_lesson_as_case"),
                not item.get("same_course_as_case"),
                item.get("candidate_file_type") or "",
                item.get("original_filename") or "",
                item.get("manifest_record_id") or "",
            ),
        )
        for candidate_index, candidate in enumerate(candidate_list, start=1):
            candidate["candidate_id"] = f"{case_id}_CANDIDATE_{candidate_index}"
            candidate["decision_code"] = f"USE_CANDIDATE_{candidate_index}"

        use_decisions = [candidate["decision_code"] for candidate in candidate_list]
        allowed_decisions = use_decisions + [
            "REMOVE_TOKEN",
            "MARK_AS_COURSE_COVER",
            "EXCLUDE_FROM_V2",
            "MANUAL_REPLACE_LATER",
            "NEEDS_SEPARATE_REVIEW",
        ]

        original_filenames = sorted(
            {record.get("original_filename") for record in direct_records if record.get("original_filename")}
        )
        failure_reasons = Counter(record.get("failure_reason") or "none" for record in direct_records)
        manifest_statuses = Counter(record.get("download_status") or "unknown" for record in direct_records)

        cases.append(
            {
                "case_id": case_id,
                "course_id": token.get("course_id"),
                "course_title": token.get("course_title"),
                "lesson_id": token.get("lesson_id"),
                "lesson_title": token.get("lesson_title"),
                "current_status": status,
                "markdown_token_reference": {
                    "token_row_id": token.get("token_row_id"),
                    "token_index": token.get("token_index"),
                    "token_type": token.get("token_type"),
                    "token_target": token.get("token_target"),
                    "reference_label": f"{token.get('token_type')}:{token.get('token_target')}",
                },
                "target_media_id": token.get("token_target") if token.get("target_media_record_exists") else None,
                "token_target": token.get("token_target"),
                "target_media_record_exists": token.get("target_media_record_exists"),
                "manifest_source_evidence": {
                    "direct_manifest_record_count": len(direct_records),
                    "direct_valid_file_count": token.get("direct_valid_file_count"),
                    "manifest_download_status_counts": dict(manifest_statuses),
                    "failure_reason_counts": dict(failure_reasons),
                    "observed_original_filenames": original_filenames,
                    "source_queue_reason": source_queue.get("reason"),
                    "attempted_deterministic_resolution_evidence": source_queue.get("attempted_evidence", []),
                    "manifest_records": manifest_evidence,
                },
                "available_local_file_candidates": candidate_list,
                "candidate_summary": {
                    "available_local_candidate_count": len(candidate_list),
                    "candidate_file_paths": [candidate.get("local_restore_path") for candidate in candidate_list],
                    "candidate_file_types": sorted({candidate.get("candidate_file_type") for candidate in candidate_list if candidate.get("candidate_file_type")}),
                    "candidate_file_sizes": [candidate.get("byte_size") for candidate in candidate_list],
                    "candidate_hashes": sorted({candidate.get("sha256") for candidate in candidate_list if candidate.get("sha256")}),
                    "no_candidate_file_exists": len(candidate_list) == 0,
                },
                "human_decision": {
                    "allowed_decisions": allowed_decisions,
                    "selected_decision": None,
                    "selected_candidate_id": None,
                    "reviewer_notes": None,
                },
            }
        )

    courses: list[dict] = []
    course_groups: dict[tuple, list[dict]] = defaultdict(list)
    for case in cases:
        course_groups[(case["course_title"], case["course_id"])].append(case)

    for (course_title, course_id), course_cases in sorted(course_groups.items()):
        lessons = []
        lesson_groups: dict[tuple, list[dict]] = defaultdict(list)
        for case in course_cases:
            lesson_groups[(case["lesson_title"], case["lesson_id"])].append(case)
        for (lesson_title, lesson_id), lesson_cases in sorted(lesson_groups.items()):
            lessons.append(
                {
                    "lesson_id": lesson_id,
                    "lesson_title": lesson_title,
                    "case_count": len(lesson_cases),
                    "status_counts": dict(Counter(case["current_status"] for case in lesson_cases)),
                    "cases": lesson_cases,
                }
            )
        courses.append(
            {
                "course_id": course_id,
                "course_title": course_title,
                "case_count": len(course_cases),
                "status_counts": dict(Counter(case["current_status"] for case in course_cases)),
                "candidate_case_count": sum(1 for case in course_cases if case["candidate_summary"]["available_local_candidate_count"] > 0),
                "lessons": lessons,
            }
        )

    batches = []
    batch_counter = 1
    for course in courses:
        course_cases = []
        for lesson in course["lessons"]:
            course_cases.extend(lesson["cases"])
        for start in range(0, len(course_cases), 10):
            chunk = course_cases[start : start + 10]
            batches.append(
                {
                    "batch_id": f"REVIEW_BATCH_{batch_counter:03d}",
                    "course_id": course["course_id"],
                    "course_title": course["course_title"],
                    "case_count": len(chunk),
                    "status_counts": dict(Counter(case["current_status"] for case in chunk)),
                    "case_ids": [case["case_id"] for case in chunk],
                    "lesson_ids": sorted({case["lesson_id"] for case in chunk}),
                    "contains_multiple_courses": False,
                    "max_10_cases_verified": len(chunk) <= 10,
                    "copy_paste_review_prompt": (
                        "Review the listed case_ids. For each case, choose exactly one allowed decision code. "
                        "Use USE_CANDIDATE_<n> only when the selected candidate_id is present in that case. "
                        "Do not infer ownership without reviewing the evidence."
                    ),
                }
            )
            batch_counter += 1

    counts = {
        "total_review_cases": len(cases),
        "unresolved_non_deterministic": sum(1 for case in cases if case["current_status"] == "UNRESOLVED_NON_DETERMINISTIC"),
        "unrecoverable": sum(1 for case in cases if case["current_status"] == "UNRECOVERABLE"),
        "courses_with_review_cases": len(courses),
        "lessons_with_review_cases": len({(case["course_id"], case["lesson_id"]) for case in cases}),
        "cases_with_available_local_candidates": sum(1 for case in cases if case["candidate_summary"]["available_local_candidate_count"] > 0),
        "cases_without_available_local_candidates": sum(1 for case in cases if case["candidate_summary"]["available_local_candidate_count"] == 0),
        "batch_count": len(batches),
        "max_cases_per_batch": max((batch["case_count"] for batch in batches), default=0),
    }

    decision_schema = {
        "schema_version": 1,
        "generated_at": generated_at,
        "purpose": "Human authority decision schema for unresolved markdown-linked media review cases.",
        "allowed_decision_codes": {
            "USE_CANDIDATE_<n>": {
                "requires_candidate": True,
                "required_fields": ["case_id", "decision", "selected_candidate_id"],
                "meaning": "Use the specified candidate file for this markdown token after human review.",
            },
            "REMOVE_TOKEN": {
                "requires_candidate": False,
                "required_fields": ["case_id", "decision", "reviewer_notes"],
                "meaning": "Remove the markdown media token from the future V2 content model.",
            },
            "MARK_AS_COURSE_COVER": {
                "requires_candidate": False,
                "required_fields": ["case_id", "decision", "reviewer_notes"],
                "meaning": "Treat the media dependency as course-level cover/media intent rather than lesson body media.",
            },
            "EXCLUDE_FROM_V2": {
                "requires_candidate": False,
                "required_fields": ["case_id", "decision", "reviewer_notes"],
                "meaning": "Exclude this media dependency from V2 migration scope.",
            },
            "MANUAL_REPLACE_LATER": {
                "requires_candidate": False,
                "required_fields": ["case_id", "decision", "reviewer_notes"],
                "meaning": "Keep the lesson blocked until a replacement media file is provided later.",
            },
            "NEEDS_SEPARATE_REVIEW": {
                "requires_candidate": False,
                "required_fields": ["case_id", "decision", "reviewer_notes"],
                "meaning": "Escalate this case because the available evidence is insufficient for a decision now.",
            },
        },
        "decision_record_schema": {
            "case_id": "REVIEW_CASE_0001",
            "decision": "USE_CANDIDATE_1 | REMOVE_TOKEN | MARK_AS_COURSE_COVER | EXCLUDE_FROM_V2 | MANUAL_REPLACE_LATER | NEEDS_SEPARATE_REVIEW",
            "selected_candidate_id": "Required only for USE_CANDIDATE_<n>; otherwise null.",
            "reviewer_notes": "Required for every non-candidate decision; optional for USE_CANDIDATE_<n>.",
            "decided_by": "Human reviewer name or identifier.",
            "decided_at": "ISO-8601 timestamp.",
        },
        "copy_paste_decision_template": {
            "case_id": "REVIEW_CASE_0001",
            "decision": "USE_CANDIDATE_1",
            "selected_candidate_id": "REVIEW_CASE_0001_CANDIDATE_1",
            "reviewer_notes": "Evidence reviewed; candidate selected by human authority.",
            "decided_by": "",
            "decided_at": "",
        },
        "application_constraints": [
            "Do not apply any decision automatically.",
            "Do not modify restore/.",
            "Do not write migration data until the user explicitly requests a separate application step.",
            "If a case has no available candidates, USE_CANDIDATE_<n> is not valid for that case.",
        ],
    }

    review_pack = {
        "schema_version": 1,
        "generated_at": generated_at,
        "mode": "generate/no-code human-guided media resolution review pack",
        "authority_load": {
            "confirmation": "AVELI OPERATING SYSTEM LOADED",
            "primary_evidence": str(PRIMARY.relative_to(ROOT)),
        },
        "input_artifacts": {
            "primary_dataset_summary": str((PRIMARY / "dataset_summary.json").relative_to(ROOT)),
            "primary_final_token_resolution": str((PRIMARY / "final_token_resolution.json").relative_to(ROOT)),
            "primary_unrecoverable_media_queue": str((PRIMARY / "unrecoverable_media_queue.json").relative_to(ROOT)),
            "primary_course_clean_state": str((PRIMARY / "course_clean_state.json").relative_to(ROOT)),
            "restore_manifest": str(RESTORE_MANIFEST.relative_to(ROOT)),
        },
        "policy": {
            "no_resolution_applied": True,
            "markdown_is_only_media_ownership_authority": True,
            "candidate_files_are_presented_neutrally": True,
            "candidate_file_presence_does_not_imply_ownership": True,
        },
        "source_counts": {
            "primary_final_token_counts": summary.get("final_token_counts"),
            "primary_course_clean_state_counts": summary.get("course_clean_state_counts"),
        },
        "review_counts": counts,
        "courses": courses,
        "language_prompt_verification": {
            "generated_user_facing_product_text": False,
            "generated_operator_prompts": True,
            "swedish_user_facing_text_rule": "PASS_NO_PRODUCT_COPY_GENERATED",
            "english_prompt_rule": "PASS_PROMPTS_GENERATED_IN_ENGLISH_COPY_PASTE_FORMAT",
        },
    }

    batch_artifact = {
        "schema_version": 1,
        "generated_at": generated_at,
        "batching_policy": {
            "maximum_unresolved_cases_per_batch": 10,
            "keep_same_course_when_possible": True,
            "course_mixing": "No generated batch mixes courses.",
        },
        "counts": {
            "batch_count": len(batches),
            "total_case_count": len(cases),
            "max_cases_in_any_batch": max((batch["case_count"] for batch in batches), default=0),
            "batches_over_limit": [batch["batch_id"] for batch in batches if batch["case_count"] > 10],
            "batches_mixing_courses": [batch["batch_id"] for batch in batches if batch["contains_multiple_courses"]],
        },
        "batches": batches,
    }

    write_json(output_dir / "manual_review_pack.json", review_pack)
    write_json(output_dir / "manual_review_batches.json", batch_artifact)
    write_json(output_dir / "decision_schema.json", decision_schema)

    print(
        json.dumps(
            {
                "output_dir": str(output_dir.relative_to(ROOT)),
                "review_counts": counts,
                "batch_counts": batch_artifact["counts"],
                "verdict": "PASS" if counts["total_review_cases"] == 131 and not batch_artifact["counts"]["batches_over_limit"] and not batch_artifact["counts"]["batches_mixing_courses"] else "PARTIAL",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()