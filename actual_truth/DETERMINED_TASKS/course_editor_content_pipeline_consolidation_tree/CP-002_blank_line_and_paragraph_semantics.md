# CP-002_BLANK_LINE_AND_PARAGRAPH_SEMANTICS

- TYPE: `OWNER`
- TITLE: `Resolve blank-line and paragraph semantics`
- DOMAIN: `newline semantics`
- CLASSIFICATION: `RESOLVE`

## Problem Statement

Blank lines and paragraph breaks currently drift between frontend roundtrip,
frontend guard comparison, and backend validation behavior.

## Primary Authority Reference

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `backend/tests/test_lesson_newline_persistence.py`

## Implementation Surfaces Affected

- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/editor/adapter/editor_to_markdown.dart`
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- `backend/app/utils/lesson_markdown_validator.py`
- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `backend/tests/test_lesson_newline_persistence.py`

## DEPENDS_ON

- `CP-001`

## Exact Implementation Steps

1. Define the canonical behavior of blank lines and paragraph breaks from the
   locked newline fixtures.
2. Remove comparison-only newline rules that disagree with the owned boundary.
3. Align roundtrip, guard, and validator behavior to the same blank-line rules.
4. Keep preview and learner verification surfaces bound to the same fixture ids.

## Acceptance Criteria

- The locked blank-line fixtures produce one consistent result across save,
  reload, validation, preview, and learner render.
- No extra normalization layer silently rewrites paragraph intent.

## Stop Conditions

- Stop if preview and learner require different blank-line semantics for the
  same canonical Markdown.
- Stop if newline behavior still depends on hidden fallback normalization.

## Out Of Scope

- Inline document-token semantics
- Preview authority drift repair
