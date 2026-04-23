# LER-001 CONTRACT LAYER RECONCILIATION

TYPE: `OWNER`
TASK_TYPE: `CONTRACT_ALIGNMENT`
EXECUTION_STATUS: `COMPLETED`
DEPENDS_ON: `[]`

## Goal

Reconcile active contract text with
`lesson_editor_rebuild_manifest_contract.md`.

## Required Outputs

- `course_lesson_editor_contract.md` no longer declares Markdown or
  `content_markdown` as rebuilt-editor authority
- `AVELI_COURSE_DOMAIN_SPEC.md` defines the document content model for the
  rebuild
- `course_public_surface_contract.md` no longer forces learner rendering to use
  Markdown as truth
- Markdown fixture corpus is reclassified as legacy compatibility or replaced
  by a document fixture corpus pointer

## Forbidden

- leaving two simultaneous rebuilt-editor content authorities
- treating existing Markdown contract text as a reason to preserve the broken
  editor architecture
- adding a legacy data migration requirement

## Verification

Search active contracts for rebuilt-editor authority language. The search must
not find Markdown or `content_markdown` as canonical for the rebuilt editor.

## Stop Conditions

Stop if another active contract must own editor document authority and the owner
cannot be determined from repo-visible truth.

## Execution Record

Status: `COMPLETED`

Changed artifacts:

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- `backend/tests/test_lesson_supported_content_fixture_corpus.py`

Verification evidence:

- `lesson_supported_content_fixture_corpus.json` parses as valid JSON.
- Direct contract search finds no remaining claim that Markdown is the
  rebuilt-editor canonical lesson-content format.
- Direct contract search finds no remaining claim that `content_markdown` is
  canonical rebuilt-editor authority.
- The Markdown fixture corpus is reclassified as
  `LEGACY_COMPATIBILITY_ONLY`.
- `pytest backend\tests\test_lesson_supported_content_fixture_corpus.py`
  passes with the corpus asserted as legacy compatibility only.

Next eligible task:

- `LER-002`
