# LER LESSON EDITOR REBUILD INDEX

| ID | status | short description | dependencies |
|---|---|---|---|
| LER-001 | `completed` | Reconcile active contracts so the rebuild is governed by `lesson_document_v1`, not Markdown. | [] |
| LER-002 | `completed` | Materialize `content_document` substrate and editor content API shape with ETag / If-Match. | [LER-001] |
| LER-003 | `completed` | Replace Markdown round-trip validation with backend-native document validation. | [LER-002] |
| LER-004 | `completed` | Add frontend document model, operations, serialization, and local validation. | [LER-002] |
| LER-005 | `completed` | Replace Course Editor authoring UI with document-model editor behavior. | [LER-004] |
| LER-006 | `completed` | Move media and magic-link / CTA into first-class document operations. | [LER-005] |
| LER-007 | `completed` | Render Course Editor Preview Mode from persisted document content only. | [LER-006] |
| LER-008 | `completed` | Align learner lesson rendering to the same document renderer. | [LER-007] |
| LER-009 | `completed` | Remove or quarantine legacy Markdown and Quill authority paths. | [LER-003, LER-008] |
| LER-010 | `completed` | Create document fixture corpus and tests for every required capability. | [LER-003, LER-006, LER-008] |
| LER-011 | `completed` | Add deterministic gates against legacy authority returning. | [LER-009, LER-010] |
| LER-012 | `completed` | Run the final aggregate editor rebuild gate. | [LER-011] |

Canonical tree directory:

- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/`

Target contract:

- `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`
