# LESSON SUPPORTED CONTENT FIXTURE CORPUS

STATUS: LEGACY_COMPATIBILITY_ONLY

This artifact records the legacy Markdown-compatible lesson-content subset for
the old Aveli editor pipeline.

It is not rebuilt-editor authority.

The rebuilt editor authority is `lesson_document_v1` as defined by
`lesson_editor_rebuild_manifest_contract.md`.

It operates under:

- `course_lesson_editor_contract.md`
- `AVELI_COURSE_DOMAIN_SPEC.md`
- `lesson_document_edge_contract.md`

This corpus does not change rebuilt-editor canonical storage, route contracts,
or backend write-boundary authority.

## AUTHORITATIVE ARTIFACTS

- machine-readable corpus:
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- explanatory authority document:
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`

The JSON corpus is the execution-grade source for legacy Markdown fixture ids,
Markdown bodies, runtime-boundary bindings, and blocker ownership.

It must not be used as proof that Markdown remains rebuilt-editor authority.

## LEGACY STORAGE AND CONSUMER SURFACES

Legacy Markdown storage was:

- `app.lesson_contents.content_markdown`

Rebuilt-editor stored truth is:

- `app.lesson_contents.content_document`

This corpus records the legacy Markdown shapes that still matter for
compatibility and legacy-removal gates. It does not keep the deleted
Quill/Markdown editor tests alive.

Active rebuilt-editor bindings are now:

- document model and local validation:
  `frontend/lib/editor/document/lesson_document.dart`,
  `frontend/test/unit/lesson_document_model_test.dart`
- document editor and persisted preview shell:
  `frontend/lib/editor/document/lesson_document_editor.dart`,
  `frontend/test/widgets/lesson_document_editor_test.dart`,
  `backend/tests/test_write_path_dominance_regression.py`
- document save/read transport:
  `frontend/lib/features/studio/data/studio_repository.dart`,
  `frontend/test/unit/studio_repository_lesson_content_read_test.dart`
- backend document validation and CAS:
  `backend/app/utils/lesson_document_validator.py`,
  `backend/tests/test_lesson_document_content_backend_contract.py`,
  `backend/tests/test_studio_lesson_document_content_api.py`

Rebuilt preview and learner rendering now bind to document rendering:

- document preview and learner rendering:
  `frontend/lib/features/courses/presentation/lesson_page.dart`,
  `frontend/lib/editor/document/lesson_document_editor.dart`
- legacy Markdown tooling and scans:
  `backend/app/utils/lesson_content.py`,
  `backend/scripts/scan_markdown_integrity.py`,
  `backend/scripts/normalize_markdown_bold_formatting.py`

## LEGACY SUPPORTED FIXTURES

The legacy Markdown fixture corpus currently covers:

- headings
- lists
- bold
- italic
- underline
- blank lines / paragraph breaks
- `!image(id)`
- `!audio(id)`
- `!video(id)`
- `!document(id)`

The legacy Markdown forms are defined in the JSON corpus by fixture id.
Downstream implementation nodes may use those ids only for compatibility,
import/export, or legacy-removal verification.

## RESOLVED BLOCKER FIXTURES

The former blocker-grade fixtures are recorded as legacy supported fixtures:

- `paragraph_blank_line_two_paragraphs`
  status: `locked`
  legacy meaning: one Markdown blank line separates two stored
  paragraphs as `Hello world\n\nThis is a lesson`
- `document_token_inline`
  status: `locked`
  legacy meaning: `!document(id)` remains the Markdown stored form and
  materializes as inline document content on old editor and render surfaces
  rather than trailing fallback-only media

## COMPATIBILITY-ONLY INPUTS

The corpus also records compatibility-only noncanonical inputs that are not
part of the canonical stored fixture set:

- escaped or underscore emphasis aliases that canonicalize to asterisk-based
  emphasis
- resolvable legacy lesson-document links that normalize to `!document(id)` at
  the backend write boundary

These inputs may remain accepted or normalized by active code, but they are not
rebuilt-editor canonical stored fixtures.

## UNSUPPORTED / OUT-OF-SCOPE SHAPES

The corpus explicitly records these as unsupported or out of scope for the
locked canonical subset:

- raw HTML media tags
- raw Markdown image URLs
- raw internal media or storage-path document links as rebuilt-editor persisted
  content

## LEGACY BINDING RULE

The corpus may remain bindable from document-model tests, document transport
tests, backend document-contract tests, rebuilt preview/learner document tests,
and legacy tooling compatibility tests.

These old active-editor bindings are retired and must not be reintroduced as
rebuilt-editor authority:

- `frontend/test/unit/editor_markdown_adapter_test.dart`
- `frontend/test/unit/lesson_content_serialization_test.dart`
- `frontend/test/unit/lesson_newline_persistence_test.dart`
- `frontend/test/unit/lesson_markdown_integrity_guard_test.dart`
- `frontend/test/widgets/lesson_editor_quill_input_test.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`
- `frontend/test/unit/editor_operation_controller_test.dart`
- `backend/tests/test_lesson_markdown_validator.py`
- `backend/tests/test_lesson_markdown_write_contract.py`
- `backend/tests/test_studio_lesson_content_authority.py`

Any downstream node that needs new rebuilt-editor supported content must define
or update a `lesson_document_v1` document fixture corpus instead of extending
this Markdown corpus as authority.
