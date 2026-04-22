# CP-202_BACKEND_VALIDATOR_ROUNDTRIP_ALIGNMENT

- TYPE: `OWNER`
- TITLE: `Align the backend validator and roundtrip harness`
- DOMAIN: `backend validation`
- CLASSIFICATION: `ALIGN`

## Problem Statement

The backend validator currently shells through a frontend harness while also
applying its own comparison normalization, which can mask semantic drift.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `backend/tests/test_lesson_markdown_validator.py`

## Implementation Surfaces Affected

- `backend/app/utils/lesson_markdown_validator.py`
- `frontend/tool/lesson_markdown_roundtrip.dart`
- `frontend/tool/lesson_markdown_roundtrip_harness_test.dart`
- `backend/app/services/courses_service.py`
- `backend/tests/test_lesson_markdown_validator.py`
- `backend/tests/test_studio_lesson_content_authority.py`

## DEPENDS_ON

- `CP-G02`

## Exact Implementation Steps

1. Align backend comparison rules to the supported-content corpus and the owned
   frontend boundary.
2. Keep server-side validator behavior explicit for pass, fail, and
   runtime-unavailable cases.
3. Remove comparison-only formatting semantics that are not part of the shared
   contract.

## Acceptance Criteria

- Backend validator results agree with the adapter-owned contract for supported
  fixtures.
- Roundtrip harness behavior is no longer a separate semantic owner.

## Stop Conditions

- Stop if backend validation still silently rewrites supported fixtures
  differently from the owned boundary.

## Out Of Scope

- Preview and learner parity
