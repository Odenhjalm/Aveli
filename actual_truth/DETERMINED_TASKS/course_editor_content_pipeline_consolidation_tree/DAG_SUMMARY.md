# COURSE_EDITOR_CONTENT_PIPELINE_CONSOLIDATION_TREE DAG SUMMARY

## SECTION: ROOT OBJECTIVE

- Consolidate the Markdown-canonical course editor content pipeline into one
  owned adapter boundary with explicit supported-content semantics, aligned
  validation, and parity-verified preview and learner rendering.

## SECTION: TASK TREE

### 1. SUPPORTED_CONTENT_BLOCKERS

- `CP-001` -> lock the supported-content fixture corpus
- `CP-002` -> resolve blank-line and paragraph semantics
- `CP-003` -> resolve inline document-token semantics
- `CP-G01` -> block downstream work until supported-content semantics are
  explicit

### 2. STUDIO_ADAPTER_BOUNDARY

- `CP-101` -> consolidate the Markdown-to-Delta hydration boundary
- `CP-102` -> consolidate the Delta-to-Markdown save boundary
- `CP-103` -> align editor input and newline sanitization
- `CP-G02` -> verify studio hydration and save now flow through one owned
  boundary

### 3. VALIDATION_PARITY

- `CP-201` -> align the frontend integrity guard to the shared boundary
- `CP-202` -> align the backend validator and roundtrip harness
- `CP-G03` -> verify frontend and backend validation parity

### 4. RENDER_PARITY

- `CP-301` -> complete learner inline-token rendering
- `CP-302` -> align studio preview to learner-equivalent composition
- `CP-G04` -> verify preview and learner parity

### 5. REGRESSION_AND_OBSERVABILITY

- `CP-401` -> repair the preview-authority regression drift test
- `CP-402` -> pin the blank-line persistence regression suite
- `CP-403` -> pin the EOF italic regression suite
- `CP-404` -> add guard and validator observability coverage
- `CP-G05` -> final content-pipeline readiness gate

## DEPENDENCY SUMMARY

- Blocker entrypoint:
  - `CP-001 -> CP-002`
  - `CP-001 -> CP-003`
  - `CP-002 + CP-003 -> CP-G01`
- Adapter spine:
  - `CP-G01 -> CP-101`
  - `CP-G01 -> CP-102`
  - `CP-G01 -> CP-103`
  - `CP-101 + CP-102 + CP-103 -> CP-G02`
- Validation branch:
  - `CP-G02 -> CP-201`
  - `CP-G02 -> CP-202`
  - `CP-201 + CP-202 -> CP-G03`
- Render branch:
  - `CP-G01 + CP-G02 -> CP-301`
  - `CP-G01 + CP-G02 + CP-301 -> CP-302`
  - `CP-301 + CP-302 -> CP-G04`
- Regression branch:
  - `CP-302 -> CP-401`
  - `CP-G03 + CP-G04 -> CP-402`
  - `CP-G02 + CP-G03 -> CP-403`
  - `CP-G03 -> CP-404`
  - `CP-401 + CP-402 + CP-403 + CP-404 -> CP-G05`

## PARALLELIZATION NOTES

- After `CP-001`, `CP-002` and `CP-003` can run in parallel.
- After `CP-G01`, `CP-101`, `CP-102`, and `CP-103` can run in parallel if file
  ownership stays disjoint.
- After `CP-G02`, `CP-201`, `CP-202`, and `CP-301` can run in parallel.
- After `CP-G03` and `CP-G04`, `CP-402`, `CP-403`, and `CP-404` can run in
  parallel.

## BLOCKER NOTES

- `CP-002` is blocker-grade because blank-line persistence is a current defect.
- `CP-003` is blocker-grade because `!document(id)` is supported canonical
  Markdown but still incomplete through hydrate and render.
- `CP-G01`, `CP-G02`, `CP-G03`, and `CP-G04` are explicit STOP gates and cannot
  be skipped by later nodes.

## CURRENT EXECUTION NOTE

- `CP-001` has already been executed and is represented here for graph
  completeness.
- The next executable blocker nodes are `CP-002` and `CP-003`.

## MATERIALIZED TASK FILES

- `CP-001_supported_content_fixture_corpus_lock.md`
- `CP-002_blank_line_and_paragraph_semantics.md`
- `CP-003_inline_document_token_semantics.md`
- `CP-G01_supported_content_blocker_gate.md`
- `CP-101_markdown_to_delta_hydration_boundary.md`
- `CP-102_delta_to_markdown_save_boundary.md`
- `CP-103_editor_input_newline_sanitization_alignment.md`
- `CP-G02_studio_adapter_boundary_gate.md`
- `CP-201_frontend_integrity_guard_alignment.md`
- `CP-202_backend_validator_roundtrip_alignment.md`
- `CP-G03_validation_parity_gate.md`
- `CP-301_learner_inline_token_rendering.md`
- `CP-302_studio_preview_learner_composition.md`
- `CP-G04_preview_learner_parity_gate.md`
- `CP-401_preview_authority_regression_drift_repair.md`
- `CP-402_blank_line_persistence_regression_suite.md`
- `CP-403_eof_italic_regression_suite.md`
- `CP-404_guard_validator_observability_hardening.md`
- `CP-G05_final_content_pipeline_readiness_gate.md`
