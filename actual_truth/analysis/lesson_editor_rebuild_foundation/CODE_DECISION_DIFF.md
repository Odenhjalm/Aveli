# LESSON EDITOR REBUILD CODE DECISION DIFF

## STATUS

CODE DIFF AUDIT

## 1. DIFF VERDICT

The current code is not a partial implementation of the rebuild target. It is a
legacy implementation that must be replaced in the editor content path.

The correct implementation stance is removal-biased:

- keep ETag concurrency
- keep structure/content separation
- keep governed media identity
- keep product capabilities
- remove Quill/Markdown as save, validation, preview, and learner content
  authority

## 2. DECISION-TO-CODE DIFF MATRIX

| Area | Rebuild decision | Current code | Required direction |
|---|---|---|---|
| Persistent content authority | `lesson_document_v1` canonical JSON in `content_document` | `content_markdown` is read/written and normalized | Replace content DTOs, repository write/read, API schemas, tests |
| Editor state authority | document model operations | Quill controller and Delta | Build editor model operations; Quill is legacy |
| Save path | validate document AST then write canonical JSON | Delta -> Markdown -> integrity guard -> PATCH Markdown | Remove Markdown serialization from save path |
| Newlines / paragraphs | paragraph nodes | regex normalization of newline runs | Replace newline semantics with block nodes |
| Italic / inline marks | explicit marks | Markdown delimiters plus italic repair | Replace delimiter repair with mark validation |
| Media | media nodes referencing `lesson_media_id` | Markdown tokens and embed/link rewrites | Replace token rewriting with media nodes |
| Magic-link / CTA | first-class CTA node | inserted as link-formatted label | Replace incidental link encoding with CTA node |
| Backend validation | backend-native document schema/reference validation | backend runs Flutter Markdown round-trip harness | Remove Flutter harness from validation path |
| Preview | persisted document renderer | Markdown-rendered persisted content plus media composition | Replace preview renderer with document renderer |
| Learner rendering | same document renderer | Markdown widget / Markdown pipeline | Replace learner renderer with document renderer |
| Test authority | document fixtures and behavior tests | Markdown adapter and guard tests | Rewrite tests around document model |

## 3. FRONTEND FILES TO REPLACE OR QUARANTINE

These files are legacy in the rebuilt editor path:

- `frontend/lib/editor/adapter/editor_to_markdown.dart`
- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/editor/adapter/lesson_markdown_validation.dart`
- `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- `frontend/lib/editor/normalization/quill_delta_normalizer.dart`
- `frontend/lib/editor/session/editor_operation_controller.dart`

These are not automatically deleted in the first task because references must
be removed deterministically. They must not remain reachable from the rebuilt
editor save, preview, learner-render, or validation path.

## 4. FRONTEND COURSE EDITOR DIFF

Current file:

- `frontend/lib/features/studio/presentation/course_editor_page.dart`

Current behavior:

- `_saveLessonContent` starts at line 3443
- save serializes Delta to Markdown at line 3473
- save validates Markdown integrity at line 3483
- save can block on Markdown integrity at lines 3511 and 3532
- save sends `ifMatch` at line 3569
- toolbar uses Quill at line 3772
- magic-link insertion starts at line 3645
- media insertion starts at line 5437

Required direction:

- preserve ETag behavior
- replace editor controller state and toolbar ownership
- replace Markdown serialization with document serialization
- replace Markdown integrity blocking with document validation
- preserve media and CTA capability as document operations

## 5. BACKEND FILES TO REPLACE OR QUARANTINE

Legacy validation path:

- `backend/app/utils/lesson_markdown_validator.py`

Legacy Markdown write path:

- `backend/app/services/courses_service.py:2192` normalizes Markdown
- `backend/app/services/courses_service.py:2199` validates Markdown
- `backend/app/services/courses_service.py:2235` rejects invalid Markdown
- `backend/app/repositories/courses.py:2090` writes `content_markdown` if current

Required direction:

- add backend-native `lesson_document_v1` validator
- compute ETag from canonical JSON
- write `content_document` with compare-and-set semantics
- remove Flutter subprocess validation from the new path

## 6. DEPENDENCY DIFF

Current dependencies:

- `flutter_quill`
- `flutter_quill_extensions`
- `markdown`
- `markdown_quill`
- `markdown_widget`

Required direction:

- do not depend on `markdown_quill` for canonical save behavior
- do not depend on `markdown_widget` for content truth rendering
- remove `flutter_quill` from long-term editor authority unless a task
  explicitly proves it can be demoted to a non-authoritative UI adapter

## 7. TEST DIFF

Current tests lock Markdown behavior:

- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`
- `frontend/test/unit/editor_markdown_adapter_test.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`
- `backend/tests/test_lesson_newline_persistence.py`
- `backend/tests/test_lesson_markdown_write_contract.py`

Required direction:

- replace Markdown round-trip tests with document serialization tests
- replace Quill newline tests with editor operation tests
- add document fixture corpus for every required feature
- assert preview renders persisted document only
- assert ETag conflicts fail without persistence
- assert media references are validated against lesson media ownership

## 8. REMOVAL-BIASED IMPLEMENTATION RULE

If a file exists only to repair Quill/Markdown behavior, the default decision is
removal or quarantine, not preservation.

If a dependency exists only to make Markdown the editor authority, the default
decision is removal, not preservation.

If a test exists only to prove Markdown round-trip stability, the default
decision is replacement with document-model tests.
