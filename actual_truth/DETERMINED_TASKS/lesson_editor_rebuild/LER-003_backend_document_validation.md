# LER-003 BACKEND DOCUMENT VALIDATION

TYPE: `OWNER`
TASK_TYPE: `BACKEND_VALIDATION`
DEPENDS_ON: `[LER-002]`
EXECUTION_STATUS: `COMPLETED`

## Goal

Replace Markdown round-trip validation with backend-native validation for
`lesson_document_v1`.

## Required Outputs

- backend validator for schema version, block nodes, inline marks, media nodes,
  CTA nodes, and canonical JSON shape
- media reference validation against lesson-owned governed media
- ETag calculation from canonical JSON bytes
- invalid document writes fail without persistence

## Forbidden

- calling Flutter from backend validation
- using Markdown round-trip comparison as document validation
- accepting unknown nodes or marks
- accepting storage URLs or runtime media IDs inside document nodes

## Verification

Backend tests cover valid documents, invalid schema versions, invalid marks,
invalid media references, invalid CTA nodes, and ETag conflict behavior.

## Stop Conditions

Stop if backend validation depends on frontend-only libraries or runtime Flutter
execution.

## Execution Record

Date: `2026-04-23`

Status: `COMPLETED`

### Completed Materialization

- Added `backend/app/utils/lesson_document_validator.py` as the backend-native `lesson_document_v1` validator.
- Validator enforces root `schema_version`, `blocks`, known block types, known inline marks, duplicate mark rejection, heading levels, list item shape, media node shape, media reference ownership/type matching, and CTA label/target validation.
- Validator canonicalizes JSON with sorted-key serialization and exposes canonical JSON bytes for ETag input.
- Updated `backend/app/services/courses_service.py` so content writes validate `content_document` against `lesson_document_v1` and lesson-owned media rows before persistence.
- Invalid document writes now fail with `400` before repository persistence.
- The active content write path no longer calls `lesson_markdown_validator`, Flutter, or Markdown round-trip validation.
- Expanded `backend/tests/test_lesson_document_content_backend_contract.py` to cover valid documents, invalid schema versions, invalid marks, duplicate marks, unknown blocks, invalid media references, invalid CTA nodes, ETag canonical JSON behavior, and ETag precondition behavior.
- Added API verification in `backend/tests/test_studio_lesson_document_content_api.py` that invalid document writes fail before persistence and valid writes return persisted `content_document`.

### Validation Against Required Outputs

- `backend validator for schema version, block nodes, inline marks, media nodes, CTA nodes, and canonical JSON shape`: `PASS_TESTED`.
- `media reference validation against lesson-owned governed media`: `PASS_TESTED`.
- `ETag calculation from canonical JSON bytes`: `PASS_TESTED`.
- `invalid document writes fail without persistence`: `PASS_TESTED`.

### Verification Evidence

- `python -m compileall backend\app\utils\lesson_document_validator.py backend\app\services\courses_service.py backend\tests\test_lesson_document_content_backend_contract.py` passed.
- `pytest backend\tests\test_lesson_document_content_backend_contract.py` passed with 13 tests.
- `pytest backend\tests\test_studio_lesson_document_content_api.py` passed.
- Targeted search of `backend/app/services/courses_service.py` found no `validate_lesson_markdown`, `lesson_markdown_validator`, or Markdown validation call in the active `update_lesson_content` path.

### Status Decision

`LER-003` is complete. `LER-004` is the next eligible task.
