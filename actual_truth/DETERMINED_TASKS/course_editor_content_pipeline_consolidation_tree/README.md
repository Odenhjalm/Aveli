# COURSE_EDITOR_CONTENT_PIPELINE_CONSOLIDATION_TREE

`input(task="Construct deterministic implementation task tree for the Markdown-canonical course editor content pipeline", mode="generate")`

## Scope

- Scope is limited to lesson and course editor content-pipeline consolidation.
- Canonical stored truth remains `app.lesson_contents.content_markdown`.
- Quill Delta remains transient editor and render state only.
- No schema or API migration branch is introduced unless repo evidence later
  proves it is unavoidable.
- Preview and learner remain separate verification surfaces even when renderer
  code is shared.
- `!image(id)`, `!audio(id)`, `!video(id)`, and `!document(id)` remain
  first-class supported tokens.

## Locked Planning Inputs

- The primary structural defect is duplicated adapter, normalization, and
  validation boundaries.
- Blank-line persistence is an active defect.
- EOF italic is improved but still structurally fragile.
- The target architecture is one owned Markdown-canonical adapter boundary with
  parity-verified preview and learner rendering.
- `CP-001` is already completed and owns the supported-content fixture corpus in
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.md` and
  `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`.

## Canonical Truth Layers

- EXECUTION CONTRACT:
  - `actual_truth/contracts/course_lesson_editor_contract.md`
  - `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md`
  - `actual_truth/contracts/lesson_document_edge_contract.md`
- FIXTURE CORPUS:
  - `actual_truth/contracts/lesson_supported_content_fixture_corpus.md`
  - `actual_truth/contracts/lesson_supported_content_fixture_corpus.json`
- EMERGENT_TRUTH EVIDENCE:
  - `frontend/lib/editor/adapter/editor_to_markdown.dart`
  - `frontend/lib/editor/adapter/markdown_to_editor.dart`
  - `frontend/lib/editor/guardrails/lesson_markdown_integrity_guard.dart`
  - `frontend/lib/shared/utils/lesson_content_pipeline.dart`
  - `backend/app/utils/lesson_markdown_validator.py`
  - `frontend/lib/features/studio/presentation/course_editor_page.dart`
  - `frontend/lib/features/courses/presentation/lesson_page.dart`

## Retrieval Queries

- `content_markdown`, `markdown_to_editor`, `editor_to_markdown`
- `lesson_markdown_integrity_guard`, `lesson_markdown_validator`
- `lesson_content_surface`, `readLessonContent`, `fetchLessonMediaPlacements`
- `!image(`, `!audio(`, `!video(`, `!document(`
- `lesson_newline_persistence`, `EOF italic`, `lesson preview`
- `lesson_supported_content_fixture_corpus`

## Evaluation Criteria

- Studio hydration and save are explainable through one owned adapter boundary.
- Blank-line semantics are explicit and no longer drift between frontend and
  backend.
- Inline document-token semantics are explicit and parity-verified.
- Frontend guard and backend validator agree on the same supported-content
  contract.
- Preview and learner parity is explicitly verified as a separate gate.
- Every materialized node declares TYPE and DEPENDS_ON and can execute
  deterministically.

## Retrieval Note

- This tree is derived from the audited repo boundaries and approved DAG.
- No new architecture search or contract reopening was performed while
  materializing this tree.

## Current Execution Note

1. `CP-001` is complete and has already locked the supported-content fixture
   corpus.
2. The next eligible blocker nodes are `CP-002` and `CP-003`.
3. `CP-G01` remains blocked until both blocker nodes are complete.

## Major Branches

1. Supported-content blocker branch
2. Studio adapter-boundary branch
3. Validation parity branch
4. Preview and learner render-parity branch
5. Regression, drift, and observability hardening branch

## Critical Path

`CP-001 -> CP-002 -> CP-G01 -> CP-101 -> CP-102 -> CP-103 -> CP-G02 -> CP-201 -> CP-202 -> CP-G03 -> CP-301 -> CP-302 -> CP-G04 -> CP-401 -> CP-402 -> CP-403 -> CP-404 -> CP-G05`

`CP-003` is a parallel blocker to `CP-002` and must complete before `CP-G01`.

## Materialized Task Order

1. `CP-001` supported-content fixture corpus lock
2. `CP-002` blank-line and paragraph semantics
3. `CP-003` inline document-token semantics
4. `CP-G01` supported-content blocker gate
5. `CP-101` Markdown-to-Delta hydration-boundary consolidation
6. `CP-102` Delta-to-Markdown save-boundary consolidation
7. `CP-103` editor input and newline sanitization alignment
8. `CP-G02` studio adapter-boundary gate
9. `CP-201` frontend integrity-guard alignment
10. `CP-202` backend validator and roundtrip-harness alignment
11. `CP-G03` validation parity gate
12. `CP-301` learner inline-token rendering completion
13. `CP-302` studio preview learner-equivalent composition
14. `CP-G04` preview and learner parity gate
15. `CP-401` preview authority regression-drift repair
16. `CP-402` blank-line persistence regression suite
17. `CP-403` EOF italic regression suite
18. `CP-404` guard and validator observability hardening
19. `CP-G05` final content-pipeline readiness gate
