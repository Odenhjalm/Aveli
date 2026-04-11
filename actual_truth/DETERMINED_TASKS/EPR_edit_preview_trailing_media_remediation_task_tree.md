# EPR EDIT PREVIEW TRAILING MEDIA REMEDIATION TASK TREE

## 1. EXECUTIVE VERDICT

PASS.

The remaining EPV gap is fully resolvable from current authority and direct source truth.

No contract update is required.

No backend change is required.

No SQL change is required.

The remediation scope is limited to learner-equivalent rendering of canonical trailing/non-embedded lesson media in Course Editor Preview Mode.

## 2. GITHUB EXPANSION SUMMARY

GitHub MCP expansion was performed first against `Odenhjalm/Aveli`.

Relevant GitHub-discovered files:

- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `backend/tests/test_write_path_dominance_regression.py`
- `actual_truth/DETERMINED_TASKS/EPV_edit_preview_mode_task_tree.md`

Relevant GitHub search themes:

- learner lesson trailing media rendering
- `LessonPageRenderer`
- `_buildLessonPreviewMode`
- `fetchLessonMediaPlacements`
- `fetchLessonMediaPreviews`
- non-embedded lesson media tests

Direct-source verified files:

- `actual_truth/contracts/course_lesson_editor_contract.md`
- `actual_truth/contracts/course_public_surface_contract.md`
- `actual_truth/contracts/media_pipeline_contract.md`
- `actual_truth/DETERMINED_TASKS/EPV_edit_preview_mode_task_tree.md`
- `frontend/lib/features/courses/presentation/lesson_page.dart`
- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/studio/presentation/lesson_media_preview_cache.dart`
- `frontend/lib/features/studio/data/studio_repository_lesson_media.dart`
- `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`
- `frontend/test/widgets/lesson_media_pipeline_test.dart`
- `frontend/test/widgets/lesson_preview_rendering_test.dart`
- `frontend/test/unit/lesson_media_preview_cache_test.dart`
- `frontend/test/unit/studio_repository_lesson_media_routing_test.dart`

Discarded as non-authoritative for this remediation:

- historical/archive contract-like files
- generic media preview cache tests that validate Edit Mode transient editor media thumbnails rather than Course Editor Preview Mode authority

## 3. VERIFIED REMAINING GAP

Current ratified authority:

- Preview Mode is read-only.
- Preview Mode is persisted-only.
- Preview Mode must render from the same canonical lesson text, lesson media, and course cover truth as learner mode.
- Preview Mode must not become an alternate content, media, or course-cover authority.
- A new backend mutation surface for Preview Mode is forbidden.
- Existing canonical read surfaces can compose persisted lesson text, lesson media, and course cover.

Direct source confirms the gap:

- Learner lesson UI in `frontend/lib/features/courses/presentation/lesson_page.dart` computes trailing media from `detail.media` by extracting embedded media ids from markdown and selecting non-embedded media that pass `_isAllowedTrailingLessonMediaType`.
- `_isAllowedTrailingLessonMediaType` currently allows document media only.
- Learner lesson UI renders that trailing document media after `LessonPageRenderer`.
- Course Editor Preview Mode in `frontend/lib/features/studio/presentation/course_editor_page.dart` renders `LessonPageRenderer` with persisted `snapshot.markdown` and canonical `snapshot.lessonMedia`, but does not render the learner trailing document media section.
- Course Editor Preview hydration already reads persisted lesson media ids from `StudioRepository.readLessonContent` and resolves canonical placement objects through `fetchLessonMediaPlacements`, so no backend read surface is required.

Resolved implementation model:

- Reuse or extract learner lesson content composition from `lesson_page.dart` so Course Editor Preview Mode uses the same embedded-media detection, document-only trailing-media filtering, and trailing document media rendering as learner mode.
- Do not duplicate a separate Preview-only media truth model.
- Do not use `lessonMediaPreviewCacheProvider`, `/api/lesson-media/previews`, local upload preview bytes, or controller/draft markdown as Preview Mode authority.

## 4. EPV REMEDIATION TASK TREE

### EPR-001

- ID: EPR-001
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: learner-trailing-media-render-equivalence
- DESCRIPTION: Align Course Editor Preview Mode with learner trailing media rendering. Extract or expose a shared learner-equivalent content composition from `frontend/lib/features/courses/presentation/lesson_page.dart` that includes `LessonPageRenderer`, embedded lesson media id detection, learner document-only trailing media filtering, and trailing document media rendering. Use that shared composition from `frontend/lib/features/studio/presentation/course_editor_page.dart` for Preview Mode with the existing persisted `snapshot.markdown` and canonical `snapshot.lessonMedia`. The implementation must not call mutation methods, must not use local draft/controller markdown, must not use `lessonMediaPreviewCacheProvider` as Preview Mode authority, must not use `/api/lesson-media/previews`, and must not introduce a new backend read or mutation surface.
- DEPENDS_ON: []

### EPR-002

- ID: EPR-002
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: preview-trailing-media-tests
- DESCRIPTION: Add or update scoped tests proving Course Editor Preview Mode renders learner-equivalent trailing/non-embedded canonical lesson media. Tests must cover at least one embedded canonical media item and one non-embedded canonical document media item returned from persisted content reads and canonical placement reads. Tests must prove Preview Mode remains persisted-only and read-only by asserting unsaved local draft text does not render, `fetchLessonMediaPlacements` is called for the persisted media ids, `fetchLessonMediaPreviews` is not called as Preview Mode authority, and `updateLessonContent` and `updateLessonStructure` are not called. Tests must preserve existing learner behavior that non-embedded audio/image media are not rendered as learner trailing media unless learner source truth changes.
- DEPENDS_ON: [EPR-001]

### EPR-003

- ID: EPR-003
- TYPE: AUDIT_GATE
- ROLE: AGGREGATE
- DOMAIN TAG: edit-preview-trailing-media-final-gate
- DESCRIPTION: Run the final scoped audit gate for the remediation. Verify Course Editor Preview Mode renders the same learner-equivalent truth for markdown-embedded media and learner trailing document media, uses only persisted canonical read truth, remains read-only, introduces no new backend mutation surface, introduces no draft-preview authority, does not use preview cache entries as Preview Mode authority, preserves Swedish user-facing UI copy for touched surfaces, and keeps task/test prompts English and copy-paste ready.
- DEPENDS_ON: [EPR-002]

## 5. DAG VALIDATION

Root task:

- EPR-001

Terminal task:

- EPR-003

Edges:

- EPR-001 -> EPR-002
- EPR-002 -> EPR-003

Topological order:

1. EPR-001
2. EPR-002
3. EPR-003

Ordering proof:

- Learner-equivalent trailing media rendering must be aligned before tests assert the behavior: EPR-001 -> EPR-002.
- Tests must pass before the final audit gate: EPR-002 -> EPR-003.

Cycle check:

- No task depends on itself.
- No dependency points to a later undefined task.
- No cycles exist.

## 6. STOP CONDITIONS

STOP if resolving trailing media equivalence requires a new authority decision.

STOP if implementation would require a backend change, SQL change, or contract update.

STOP if Preview Mode would need a new mutation API.

STOP if Preview Mode would use draft/controller markdown as render authority.

STOP if Preview Mode would use `lessonMediaPreviewCacheProvider`, `/api/lesson-media/previews`, local upload preview bytes, or frontend-constructed media URLs as render authority.

STOP if learner trailing media rules cannot be mapped directly from `lesson_page.dart`.

STOP if multiple Preview Mode truth models remain plausible after direct source inspection.

STOP if user-facing UI text touched by the remediation is not Swedish.

STOP if task, test, or verification prompts added by the remediation are not English and copy-paste ready.
