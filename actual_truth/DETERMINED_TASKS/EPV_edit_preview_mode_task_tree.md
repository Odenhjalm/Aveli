# EPV EDIT MODE / PREVIEW MODE TASK TREE

## 1. EXECUTIVE VERDICT

PASS.

Implementation is fully resolvable from the ratified authority in:

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/contracts/media_lifecycle_contract.md`

No new authority decision is required.

No CONTRACT_UPDATE task is generated.

No BACKEND_ALIGNMENT task is generated because existing canonical read surfaces can compose persisted lesson text, lesson media, and course cover for Preview Mode.

Preview Mode implementation must be frontend composition over existing persisted canonical read surfaces only.

## 2. GITHUB EXPANSION SUMMARY

GitHub MCP expansion was performed first.

Relevant active files found by GitHub search:

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/courses/data/courses_repository.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/features/studio/data/studio_repository_lesson_media.dart`
- `frontend/lib/features/studio/data/studio_models.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart`
- `frontend/lib/editor/adapter/editor_to_markdown.dart`
- `frontend/lib/editor/adapter/markdown_to_editor.dart`
- `frontend/lib/shared/utils/lesson_content_pipeline.dart`
- `backend/app/routes/studio.py`
- `backend/app/routes/courses.py`
- `backend/app/repositories/courses.py`
- `backend/app/services/courses_service.py`
- `backend/app/schemas/__init__.py`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/widgets/lesson_media_preview_editor_regression_test.dart`
- `frontend/test/unit/editor_markdown_adapter_test.dart`
- `frontend/test/unit/studio_repository_lesson_media_routing_test.dart`
- `frontend/test/unit/media_upload_url_contract_test.dart`
- `frontend/test/widgets/course_page_access_test.dart`
- `backend/tests/test_studio_lesson_content_authority.py`
- `backend/tests/test_studio_lesson_media_contract_unit.py`
- `backend/tests/test_surface_based_lesson_reads.py`
- `actual_truth/DETERMINED_TASKS/CCL_course_cover_lesson_content_authority_task_tree.md`
- `actual_truth/DETERMINED_TASKS/CCL_INDEX.md`
- `actual_truth/DETERMINED_TASKS/CCL-004.md`
- `actual_truth/DETERMINED_TASKS/CCL-008.md`
- `actual_truth/DETERMINED_TASKS/CCL-010.md`
- `actual_truth/DETERMINED_TASKS/CCL-013.md`
- `actual_truth/DETERMINED_TASKS/CCL-018.md`

Directly verified files:

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/contracts/media_lifecycle_contract.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/DETERMINED_TASKS/CCL_course_cover_lesson_content_authority_task_tree.md`
- `actual_truth/DETERMINED_TASKS/CCL_INDEX.md`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/courses/data/courses_repository.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/features/studio/data/studio_repository_lesson_media.dart`
- `frontend/lib/features/studio/data/studio_models.dart`
- `backend/app/routes/studio.py`
- `backend/app/routes/courses.py`
- `backend/app/repositories/courses.py`
- `backend/app/services/courses_service.py`
- `backend/app/schemas/__init__.py`
- scoped frontend and backend tests listed above

Discarded historical or non-authoritative hits:

- `archive/**` search hits
- legacy or deferred preview/media task references outside the ratified EPV authority scope
- CCL historical failure notes that were superseded by the CCL `PASS (SCOPED)` classification
- preview-cache and editor-regression tests as authority sources; they remain implementation evidence only

## 3. CURRENT IMPLEMENTATION GAP SUMMARY

Authority status:

- `course_lesson_editor_contract.md` explicitly states that Edit Mode is the only authoring and mutation surface.
- `course_lesson_editor_contract.md` explicitly states that Preview Mode is read-only, persisted-only, and must render from the same canonical lesson text, lesson media, and course cover truth as learner mode.
- `course_lesson_editor_contract.md` forbids draft preview as Preview Mode authority.
- `media_pipeline_contract.md` makes `GET /api/media-placements/{lesson_media_id}` the canonical placement read surface for governed media objects.
- `course_public_surface_contract.md` makes `GET /courses/lessons/{lesson_id}` the learner `lesson_content_surface`.

Verified current editor behavior:

- `course_editor_page.dart` has an Edit/Preview toggle.
- `_setLessonPreviewMode(true)` currently calls `_syncLessonPreviewMarkdownFromController()`.
- `_syncLessonPreviewMarkdownFromController()` writes `_lessonPreviewMarkdown` from the live Quill controller.
- `_serializeLessonPreviewMarkdownFromController()` calls `editorDeltaToPassivePreviewMarkdown`.
- `_buildLessonPreviewMode()` renders `LessonPageRenderer` but feeds it `_currentLessonPreviewMarkdown()` and `_selectedLessonMediaItems()`.
- `_selectedLessonMediaItems()` maps the currently loaded studio media rows into learner `LessonMediaItem` shape.

Verified learner render behavior:

- `lesson_page.dart` uses `LessonPageRenderer(markdown: lesson.contentMarkdown, lessonMedia: detail.media)`.
- `LessonPageRenderer` prepares markdown through `prepareLessonMarkdownForRendering`.
- lesson media rendering uses backend-authored `media.resolvedUrl`.
- unresolved lesson media fails explicitly instead of falling back to frontend URL construction.

Verified persisted canonical read surfaces:

- `GET /studio/lessons/{lesson_id}/content` returns persisted `content_markdown`, media placement identities, and an `ETag`.
- `GET /api/media-placements/{lesson_media_id}` returns canonical governed media output as `media = { media_id, state, resolved_url } | null`.
- course cover rendering is sourced from backend-provided `cover.resolved_url`.

Current gap:

- Preview Mode has learner-equivalent renderer reuse, but the text input is still draft-derived from the live editor controller.
- Preview Mode media can be mapped from current studio state, but EPV must force canonical persisted placement reads for Preview Mode truth.
- Preview Mode cover truth must remain backend `cover.resolved_url` only and must not use local upload preview state.
- Existing passive preview serialization tests are implementation drift for EPV unless they are renamed and scoped to Edit Mode transient editor UI only.

## 4. EDIT/PREVIEW TASK TREE

### EPV-001

- ID: EPV-001
- TYPE: AUDIT_GATE
- ROLE: GATE
- DOMAIN TAG: edit-preview-authority
- DESCRIPTION: Reconfirm the ratified Edit Mode / Preview Mode authority before mutation work. Verify that `course_lesson_editor_contract.md`, `course_public_surface_contract.md`, `media_pipeline_contract.md`, and `media_lifecycle_contract.md` still define Preview Mode as read-only, persisted-only, learner-equivalent, and non-authoritative for content, media, and course cover. Verify that no CONTRACT_UPDATE or SQL change is required. Verify that the implementation can use existing canonical read surfaces: `GET /studio/lessons/{lesson_id}/content`, `GET /api/media-placements/{lesson_media_id}`, and backend-provided course `cover.resolved_url`.
- DEPENDS_ON: []

### EPV-002

- ID: EPV-002
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: persisted-preview-truth
- DESCRIPTION: Add or align a persisted Preview Mode read model in the Course + Lesson Editor. Preview hydration must read lesson text from `StudioRepository.readLessonContent`, read lesson media render objects from canonical placement reads for the returned `lesson_media_id` values, and read course cover only from backend-provided course `cover.resolvedUrl`. Preview hydration must not serialize the Quill controller, read `_lessonPreviewMarkdown`, use local upload preview bytes, use preview-cache data as truth, or call mutation methods.
- DEPENDS_ON: [EPV-001]

### EPV-003

- ID: EPV-003
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: learner-render-equivalence
- DESCRIPTION: Align Preview Mode rendering to the learner renderer. Preview Mode must pass persisted markdown and canonical `LessonMediaItem` values into the same `LessonPageRenderer` used by `lesson_page.dart`. Any wrapper, spacing, title, chip, or editor-context chrome may differ from learner UI only as presentation. Rendering helpers must not fork lesson markdown parsing, media URL resolution, or cover URL selection for Preview Mode.
- DEPENDS_ON: [EPV-002]

### EPV-004

- ID: EPV-004
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: mode-separation-ui
- DESCRIPTION: Wire the Edit/Preview UI toggle after persisted preview truth and learner renderer alignment are in place. Edit Mode must remain the only surface where the Quill controller, save, reset, title update, media upload, placement attach, placement reorder, placement delete, and cover assignment or clear controls can mutate state. Entering Preview Mode must trigger or reuse a successful persisted preview hydration and must fail closed if persisted content, canonical media placement reads, or cover read truth cannot be verified. Unsaved local edits must not appear in Preview Mode until they have been saved and reread or acknowledged as persisted backend truth.
- DEPENDS_ON: [EPV-002, EPV-003]

### EPV-005

- ID: EPV-005
- TYPE: LEGACY_REMOVAL
- ROLE: OWNER
- DOMAIN TAG: draft-preview-removal
- DESCRIPTION: Remove or quarantine draft-preview authority behavior from Preview Mode. `_syncLessonPreviewMarkdownFromController`, `_serializeLessonPreviewMarkdownFromController`, `_currentLessonPreviewMarkdown`, `_lessonPreviewMarkdown`, and `editorDeltaToPassivePreviewMarkdown` must not feed Preview Mode. If passive editor media previews remain, they must be clearly scoped to Edit Mode transient editor UI and must not use the name or authority boundary of Preview Mode. Legacy tests that assert passive preview serialization as Preview Mode truth must be removed, renamed, or rewritten as non-authoritative Edit Mode editor-helper tests.
- DEPENDS_ON: [EPV-004]

### EPV-006

- ID: EPV-006
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: frontend-preview-contract
- DESCRIPTION: Add or update frontend tests for Edit/Preview separation. Tests must prove that Preview Mode reads persisted content only, unsaved local edits do not render in Preview Mode, Preview Mode does not call `updateLessonContent` or `updateLessonStructure`, Preview Mode uses `LessonPageRenderer`, Preview Mode media uses canonical placement-read `media.resolved_url`, course cover uses backend `cover.resolved_url`, and user-facing UI copy in the touched editor preview surface is Swedish.
- DEPENDS_ON: [EPV-005]

### EPV-007

- ID: EPV-007
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: no-preview-authority
- DESCRIPTION: Add or update backend/static guard tests proving Preview Mode does not introduce a mutation API or alternate authority. Tests must prove no positive Preview Mode code path calls a new preview mutation surface, no frontend Preview Mode path uses `/api/lesson-media/{lesson_id}/{lesson_media_id}/preview` or `/api/lesson-media/previews` as content/media authority, and any future helper read surface remains a read-only projection over canonical persisted content/media/cover truth.
- DEPENDS_ON: [EPV-005]

### EPV-008

- ID: EPV-008
- TYPE: AUDIT_GATE
- ROLE: AGGREGATE
- DOMAIN TAG: edit-preview-final-gate
- DESCRIPTION: Run the final scoped audit gate after tests. Verify the DAG outputs against the contracts: Edit Mode is the only mutation surface, Preview Mode is read-only, Preview Mode is learner-equivalent, Preview Mode is persisted-only, no draft-preview authority remains, no alternate content/media/cover authority exists, all touched user-facing UI text is Swedish, and all task/test prompts are English and copy-paste ready.
- DEPENDS_ON: [EPV-006, EPV-007]

## 5. DAG VALIDATION

Root task:

- EPV-001

Terminal task:

- EPV-008

Edges:

- EPV-001 -> EPV-002
- EPV-002 -> EPV-003
- EPV-002 -> EPV-004
- EPV-003 -> EPV-004
- EPV-004 -> EPV-005
- EPV-005 -> EPV-006
- EPV-005 -> EPV-007
- EPV-006 -> EPV-008
- EPV-007 -> EPV-008

Topological order:

1. EPV-001
2. EPV-002
3. EPV-003
4. EPV-004
5. EPV-005
6. EPV-006
7. EPV-007
8. EPV-008

Required ordering proof:

- Authority alignment before UI toggle behavior: EPV-001 -> EPV-002 -> EPV-004.
- Learner-equivalent renderer alignment before preview exposure: EPV-003 -> EPV-004.
- Legacy/draft preview removal before final tests: EPV-005 -> EPV-006 and EPV-005 -> EPV-007.
- Tests before final audit gate: EPV-006 -> EPV-008 and EPV-007 -> EPV-008.

Cycle check:

- No task depends on itself.
- No dependency points to a later undefined task.
- No cycles exist.

## 6. STOP CONDITIONS

STOP if any implementation task would require a new authority decision.

STOP if a new backend mutation surface is proposed for Preview Mode.

STOP if Preview Mode cannot be composed from persisted canonical read truth.

STOP if `GET /studio/lessons/{lesson_id}/content` plus canonical placement reads cannot produce persisted lesson text and learner-renderable media inputs.

STOP if course cover Preview Mode truth cannot be tied to backend-provided `cover.resolved_url`.

STOP if implementation requires SQL or schema changes.

STOP if multiple Preview Mode truth models remain plausible after EPV-001.

STOP if Preview Mode uses local draft controller state, `_lessonPreviewMarkdown`, preview cache entries, upload preview bytes, or frontend-constructed URLs as authority.

STOP if user-facing UI text touched in this scope is not Swedish.

STOP if task, test, or verification prompts added by this tree are not English and copy-paste ready.
