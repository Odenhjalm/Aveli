# LESSON_EDITOR_REBUILD_TASK_TREE

`input(task="Materialize deterministic task tree for the lesson editor rebuild", mode="generate")`

## Scope

- Target truth is `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`.
- Foundation evidence is under
  `actual_truth/analysis/lesson_editor_rebuild_foundation/`.
- Repository code is legacy evidence until a task explicitly replaces it.
- No legacy data migration is in scope.
- The goal is a fully working, future-proof editor for new canonical document
  content.

## Controller Model

This tree is intended for full-chain controller execution.

Current execution state:

- `LER-001`: `COMPLETED`
- `LER-002`: `COMPLETED`
- `LER-003`: `COMPLETED`
- `LER-004`: `COMPLETED`
- `LER-005`: `COMPLETED`
- `LER-006`: `COMPLETED`
- `LER-007`: `COMPLETED`
- `LER-008`: `COMPLETED`
- `LER-009`: `COMPLETED`
- `LER-010`: `COMPLETED`
- `LER-011`: `COMPLETED`
- `LER-012`: `COMPLETED`

The deterministic task tree is closed. No successor task remains in this DAG.

The controller must:

- load `task_manifest.json`
- validate every task file exists
- execute tasks in topological order
- run retrieval before each task using that task's `retrieval_queries`
- perform pre-change and post-change audits for every task
- record verification evidence before advancing
- stop on any contradiction between active contract truth and task output

The controller must use the retrieval-stage law in
`actual_truth/contracts/retrieval/retrieval_contract.md`.

## Retrieval Rule

Retrieval evidence for each task must include:

- contract sources
- active implementation files
- tests and validation scripts
- dependency manifests where relevant

The controller must not use chat history as authority.

## Materialized Task Order

1. `LER-001` contract layer reconciliation
2. `LER-002` document substrate and API shape
3. `LER-003` backend document validation and ETag authority
4. `LER-004` frontend document model and operation semantics
5. `LER-005` editor UI replacement
6. `LER-006` media and CTA document operations
7. `LER-007` persisted preview renderer
8. `LER-008` learner document renderer alignment
9. `LER-009` legacy Markdown/Quill path removal
10. `LER-010` document fixture and test corpus
11. `LER-011` deterministic audit gates
12. `LER-012` final aggregate editor gate

## Coverage Map

- Bold, italic, underline, clear formatting: `LER-004`, `LER-005`, `LER-010`
- Headings and lists: `LER-004`, `LER-005`, `LER-010`
- Image, audio, video, document: `LER-006`, `LER-008`, `LER-010`
- Magic-link / CTA: `LER-006`, `LER-010`
- Preview against saved content: `LER-007`, `LER-008`, `LER-010`
- ETag concurrency: `LER-002`, `LER-003`, `LER-010`
- Legacy removal: `LER-001`, `LER-009`, `LER-011`, `LER-012`

## Stop Conditions

Stop if implementation requires legacy data migration.

Stop if Markdown remains the rebuilt editor authority.

Stop if Quill Delta remains the rebuilt editor authority.

Stop if Preview Mode renders unsaved draft content.

Stop if ETag / If-Match concurrency is weakened.

Stop if governed media identity is bypassed.

Stop if old Markdown contracts are not reconciled before code claims
completion.
