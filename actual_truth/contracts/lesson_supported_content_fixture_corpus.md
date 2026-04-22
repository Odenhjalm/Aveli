# LESSON SUPPORTED CONTENT FIXTURE CORPUS

STATUS: ACTIVE

This artifact locks the currently intended supported lesson-content subset for
the Markdown-canonical Aveli editor pipeline.

It operates under:

- `course_lesson_editor_contract.md`
- `AVELI_COURSE_DOMAIN_SPEC.md`
- `lesson_document_edge_contract.md`

This corpus does not change canonical storage, route contracts, or backend
write-boundary authority.

## AUTHORITATIVE ARTIFACTS

- machine-readable corpus:
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- explanatory authority document:
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`

The JSON corpus is the execution-grade source for fixture ids, canonical
Markdown bodies, runtime-boundary bindings, and blocker ownership.

## CANONICAL STORAGE AND CONSUMER SURFACES

Canonical stored truth remains:

- `app.lesson_contents.content_markdown`

This corpus is locked against the active repo boundaries that currently consume
stored lesson content:

- editor hydration:
  `frontend/lib/editor/adapter/markdown_to_editor.dart`,
  `frontend/lib/features/studio/presentation/course_editor_page.dart`,
  `frontend/lib/features/courses/presentation/lesson_page.dart`
- editor save:
  `frontend/lib/editor/adapter/editor_to_markdown.dart`,
  `frontend/lib/editor/normalization/quill_delta_normalizer.dart`,
  `frontend/lib/features/studio/presentation/course_editor_page.dart`
- frontend integrity validation:
  `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
- backend validation:
  `backend/app/utils/lesson_markdown_validator.py`,
  `frontend/tool/lesson_markdown_roundtrip.dart`,
  `frontend/tool/lesson_markdown_roundtrip_harness_test.dart`
- preview rendering:
  `frontend/lib/features/studio/presentation/course_editor_page.dart`
- learner rendering:
  `frontend/lib/features/courses/presentation/lesson_page.dart`
- backend write boundary:
  `backend/app/routes/studio.py`,
  `backend/app/services/courses_service.py`,
  `backend/app/utils/lesson_content.py`,
  `backend/app/repositories/courses.py`

## SUPPORTED CANONICAL FIXTURES

The supported canonical fixture corpus currently covers:

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

The canonical stored Markdown forms are defined in the JSON corpus by fixture
id. Downstream implementation nodes must reuse those ids rather than inventing
new case names.

## RESOLVED BLOCKER FIXTURES

The former blocker-grade fixtures are now locked supported fixtures:

- `paragraph_blank_line_two_paragraphs`
  status: `locked`
  canonical meaning: one canonical Markdown blank line separates two stored
  paragraphs as `Hello world\n\nThis is a lesson`
- `document_token_inline`
  status: `locked`
  canonical meaning: `!document(id)` remains the stored form and materializes as
  inline document content on editor and render surfaces rather than trailing
  fallback-only media

## COMPATIBILITY-ONLY INPUTS

The corpus also records compatibility-only noncanonical inputs that are not
part of the canonical stored fixture set:

- escaped or underscore emphasis aliases that canonicalize to asterisk-based
  emphasis
- resolvable legacy lesson-document links that normalize to `!document(id)` at
  the backend write boundary

These inputs may remain accepted or normalized by active code, but they are not
canonical stored fixtures.

## UNSUPPORTED / OUT-OF-SCOPE SHAPES

The corpus explicitly records these as unsupported or out of scope for the
locked canonical subset:

- raw HTML media tags
- raw Markdown image URLs
- raw internal media or storage-path document links as canonical persisted
  content

## BINDING RULE

The corpus must remain bindable from:

- frontend adapter tests
- frontend newline tests
- frontend guard tests
- backend validator tests
- preview and learner parity tests
- backend write-contract tests

Any downstream node that needs new supported content must first change this
corpus and its contract evidence before implementation.
