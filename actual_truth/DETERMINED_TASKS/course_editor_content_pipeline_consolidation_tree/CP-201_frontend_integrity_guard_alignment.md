# CP-201_FRONTEND_INTEGRITY_GUARD_ALIGNMENT

- TYPE: `OWNER`
- TITLE: `Align the frontend integrity guard to the shared boundary`
- DOMAIN: `frontend validation`
- CLASSIFICATION: `ALIGN`

## Problem Statement

The guard currently risks acting as a second semantic owner instead of a thin
verifier over the supported-content boundary.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`

## Implementation Surfaces Affected

- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`

## DEPENDS_ON

- `CP-G02`

## Exact Implementation Steps

1. Restrict guard comparison rules to the same semantics owned by the adapter
   boundary.
2. Preserve fail-closed behavior when the boundary cannot roundtrip a supported
   fixture correctly.
3. Ensure guard pass and fail reasons map back to the supported corpus.

## Acceptance Criteria

- The guard no longer defines its own formatting contract.
- Guard behavior is traceable to the owned adapter boundary and fixture corpus.

## Stop Conditions

- Stop if the guard still canonicalizes content differently from the owned
  boundary.

## Out Of Scope

- Backend validator runtime availability policy
