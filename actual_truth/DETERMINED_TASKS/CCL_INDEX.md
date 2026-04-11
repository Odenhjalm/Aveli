# TITLE
CCL Deterministic Task Index

## SOURCE AUTHORITY
actual_truth/DETERMINED_TASKS/CCL_course_cover_lesson_content_authority_task_tree.md

## MATERIALIZATION STATUS
MATERIALIZED_READY_FOR_CONTROLLER

## CHAIN STATUS
IN_PROGRESS

## CURRENT ELIGIBLE TASK SET
CCL-017

## CURRENT TASK
None

## LAST COMPLETED TASK
CCL-016

## CURRENT BLOCKED OR FAILED TASK
None

The tree is materialized.
The task files are the execution ledger.
Controller execution must read and update these files.
Controller execution was repaired at CCL-007 after the missing CCL-004 readiness/status backend handoff was completed. Completed tasks and next eligible tasks are recorded in the ordered task table and in each task ledger file.

## DEFERRED TEST-ALIGNMENT NOTE
CCL-005 stale worker-promotion tests were classified as non-canonical legacy-test conflict, not implementation failure. The deferred tests are `backend/tests/test_media_transcode_worker_source_wait.py::test_transcode_cover_promotes_without_legacy_public_url` and `backend/tests/test_media_transcode_worker_source_wait.py::test_transcode_cover_logs_when_ready_asset_not_promoted`. CCL-010 owns final test alignment for worker no-assignment behavior; CCL-009 owns later legacy route/source inventory proving no active positive path treats worker cover promotion as canonical.

CCL-006 stale studio course-cover test expectation was classified as non-canonical legacy-test conflict, not implementation failure. The deferred test is `backend/tests/test_courses_studio.py::test_studio_course_and_lesson_endpoints_follow_canonical_shape`, where a pending media asset with legacy source path `courses/{course_id}/covers/{cover_media_id}.png` is expected to be assignable. CCL-010 owns final test alignment for canonical cover assignment rejection and happy-path coverage through canonical course-cover ingest/readiness.

CCL-008 stale frontend cover-rendering tests were classified as non-canonical legacy-test conflict, not implementation failure. The deferred tests are `frontend/test/unit/course_cover_assets_test.dart`, which still expects slug asset fallback when backend `cover.resolved_url` is absent; `frontend/test/unit/course_cover_render_source_test.dart`, which still references removed local override/editor-source helpers and local preview rendering as authority; and `frontend/test/unit/course_cover_resolver_test.dart`, which still imports removed `course_cover_resolver.dart` and expects removed `CourseCoverData.source` / editor override semantics. CCL-010 owns final frontend test alignment for canonical cover rendering from `cover.resolved_url` only.

## CONTROLLER REPAIR NOTE
CCL-007 was blocked because frontend replacement could not consume backend readiness/status truth without a mounted canonical media asset status surface. Inspection classified the blocker as an incomplete prior backend handoff owned by CCL-004, not a true frontend implementation failure. The repair added `GET /api/media-assets/{media_asset_id}/status` under the existing mounted `studio.media_pipeline_router`, with response `{ media_asset_id, asset_state }`, and kept cover assignment/clear exclusively under `PATCH /studio/courses/{course_id}` with `cover_media_id`. The repair did not mount or use `/api/media/cover-*`, did not use unmounted `api_media`, did not make upload completion act as readiness authority, and did not introduce frontend fallback readiness inference. CCL-007 is now DONE; next deterministic task by task ID is CCL-008.

## REPAIRED BLOCK NOTE
CCL-010 is DONE after deterministic unblock repair. The block was classified as backend repository drift in the CCL-004-owned canonical media pipeline completion/status read surface, not as a CCL-010 test-only failure and not as a baseline-slot defect. `backend/app/repositories/media_assets.py` now reads canonical `app.media_assets` fields only for `get_media_asset` and `get_media_assets`, and `_canonical_storage_bucket_for_access` no longer treats `streaming_storage_bucket` as storage-access authority. Active baseline/local DB evidence remains `id`, `media_type`, `purpose`, `original_object_path`, `ingest_format`, `playback_object_path`, `playback_format`, and `state`; no deprecated `streaming_*` column set was reintroduced. Verification passed for backend py_compile, DB-backed studio cover shape, backend cover gate tests, frontend cover tests, direct DB column inventory, source scans, `git diff --check`, and `git diff --cached --check`. The next deterministic eligible task is CCL-011.

## CCL-011 COMPLETION NOTE
CCL-011 is DONE. The backend now mounts `GET /studio/lessons/{lesson_id}/content` as the dedicated lesson content read authority. The endpoint returns only `{ lesson_id, content_markdown, media }`, emits HTTP `ETag`, reads through `app.lesson_contents.content_markdown`, enforces teacher/course ownership, and does not mutate content. `PATCH /studio/lessons/{lesson_id}/content` now requires the current `If-Match` token, rejects tokenless writes with `428`, rejects stale writes with `412`, and emits a replacement `ETag` on success. Structure routes remain content-free. Verification passed through backend py_compile, direct ASGI endpoint checks, direct route inventory, scoped backend route/content tests, scoped studio structure test, cleanup checks, and `git diff --check`. CCL-012 later consumed this backend surface and is now recorded separately.

## CCL-012 COMPLETION NOTE
CCL-012 is DONE. The studio frontend data layer now separates structure and content: `LessonStudio` no longer carries `contentMarkdown` and rejects `content_markdown`, `media`, and `etag` in structure payloads; `StudioRepository.readLessonContent` reads only `GET /studio/lessons/{lesson_id}/content` and preserves the backend `ETag`; `StudioRepository.updateLessonContent` requires a non-empty `If-Match` token and returns the replacement `ETag`; the mixed `upsertLesson` repository path is fail-closed instead of positive. A scoped frontend unit test proves structure rejection, dedicated content read, ETag preservation, If-Match transport, and tokenless-write rejection. Scoped repository/model analyzer, the focused unit test, and `git diff --check` passed. A separate analyzer run on `course_editor_page.dart` still reports two pre-existing `use_build_context_synchronously` infos at lines 4731 and 4741 outside the CCL-012 edits. CCL-013 later consumed this frontend data layer and is now recorded separately.

## CCL-013 COMPLETION NOTE
CCL-013 is DONE. The studio editor now hydrates selected lesson markdown only through `StudioRepository.readLessonContent` / `GET /studio/lessons/{lesson_id}/content`, stores the backend-issued content `ETag`, and treats editor readiness as selected lesson id + request id + hydrated lesson id + non-empty token + no hydration error. The prior structure-derived empty markdown fallback was removed from editor boot; `upsertLesson` is no longer a positive editor save call; content writes use `StudioRepository.updateLessonContent` with the stored `If-Match` token; `412` and `428` responses force an explicit stale/error state requiring rehydration; failed hydration blocks edit/save/reset; and narrow-layout rendering now uses the same hydration/error gate instead of directly rendering the editor. Verification passed through the focused widget test `frontend/test/widgets/course_editor_lesson_content_lifecycle_test.dart`, the repository test `frontend/test/unit/studio_repository_lesson_content_read_test.dart`, focused source scans, focused widget-test analyzer, and `git diff --check`. `flutter analyze lib/features/studio/presentation/course_editor_page.dart` still reports two pre-existing `use_build_context_synchronously` infos at lines 4908 and 4918 outside the CCL-013 edits. The broad legacy `frontend/test/widgets/course_editor_screen_test.dart` still fails to compile due stale map-based model fixtures, old `upsertLesson` named arguments, old course summary constructors, and old preview cache/upload job fields; that broad frontend test realignment remains owned by downstream CCL-016. The next deterministic eligible task is CCL-014; CCL-014 was not executed.

## CCL-014 COMPLETION NOTE
CCL-014 is DONE. The legacy broad frontend fixture file `frontend/test/widgets/course_editor_screen_test.dart` was quarantined because it encoded non-canonical mixed structure/content assumptions: `listCourseLessons` payloads with `content_markdown`, stale `LessonStudio.contentMarkdown` and `LessonSummary.contentMarkdown` fixture construction, legacy `is_intro` raw-map structure fixtures, and positive `upsertLesson` mocks. Helper-only backend mixed paths were fail-closed in `backend/app/models.py`, `backend/app/services/courses_service.py`, and `backend/app/repositories/courses.py` without modifying backend routes or schemas. Verification passed through source scans showing no mixed structure/content references in the quarantined widget fixture, no active backend app caller of the fail-closed mixed helpers, backend py_compile for modified backend files, focused Flutter analyzer, focused Flutter tests for the quarantine and canonical content read/editor lifecycle tests, and `git diff --check`. At the time CCL-014 was completed, CCL-015 had not been executed yet and was the next deterministic eligible task.

## CCL-015 COMPLETION NOTE
CCL-015 is DONE. Backend lesson-content tests now align to canonical content authority: writes fetch the backend-issued `ETag` from `GET /studio/lessons/{lesson_id}/content`, send `If-Match`, and assert that missing-token writes fail with `428`, stale writes fail with `412`, persisted content roundtrips through `app.lesson_contents.content_markdown`, and structure create/list/update responses remain free of `content_markdown`, `media`, and `etag`. A focused backend test `backend/tests/test_studio_lesson_content_authority.py` proves the dedicated content read shape `{ lesson_id, content_markdown, media }`, unauthorized read rejection, and mixed structure/content update rejection. The logs MCP backend test helper was adjusted inside the backend-test mutation plane to remove a positive legacy `/studio/lessons` mixed content creation path and use canonical course/lesson/media test substrate. Verification passed through backend py_compile, the scoped backend lesson-content suite (`22 passed, 1 warning`), the updated logs MCP backend file (`5 passed, 1 warning`), source scans for content/structure authority and If-Match coverage, and `git diff --check`. CCL-016 was not executed. The next deterministic eligible task is CCL-016.

## CCL-016 COMPLETION NOTE
CCL-016 is DONE. Frontend lesson-content tests now assert the canonical editor lifecycle: hydration uses the dedicated content read path, structure fixtures do not act as content authority, writes require the backend-issued `ETag`, stale `412` saves fail closed without structure overwrite, failed hydration and blank ETag state block writes, intentional empty clear is explicit, and lesson switching loads selected content without leaking or overwriting prior lesson state. The broad `course_editor_screen_test.dart` remains a quarantine sentinel and contains no `content_markdown`, `contentMarkdown`, `etag`, or `media` fixture authority. Verification passed through `flutter test test/widgets/course_editor_lesson_content_lifecycle_test.dart`, `flutter test test/unit/studio_repository_lesson_content_read_test.dart`, `flutter test test/widgets/course_editor_screen_test.dart`, focused Flutter analyzer, targeted source scans, and `git diff --check`. CCL-017 was not executed. The next deterministic eligible task is CCL-017.

## ROOT TASKS
- CCL-001
- CCL-002

## TERMINAL TASK
CCL-018

## ORDERED TASK TABLE
| TASK ID | FILE PATH | TYPE | ROLE | DOMAIN TAG | DEPENDS_ON | STATUS |
|---|---|---|---|---|---|---|
| CCL-001 | actual_truth/DETERMINED_TASKS/CCL-001.md | CONTRACT_UPDATE | OWNER | course-cover | [] | DONE |
| CCL-002 | actual_truth/DETERMINED_TASKS/CCL-002.md | CONTRACT_UPDATE | OWNER | lesson-content | [] | DONE |
| CCL-003 | actual_truth/DETERMINED_TASKS/CCL-003.md | BASELINE_SLOT | GATE | cross-domain | [CCL-001, CCL-002] | DONE |
| CCL-004 | actual_truth/DETERMINED_TASKS/CCL-004.md | BACKEND_ALIGNMENT | OWNER | course-cover | [CCL-003] | DONE |
| CCL-005 | actual_truth/DETERMINED_TASKS/CCL-005.md | BACKEND_ALIGNMENT | OWNER | course-cover | [CCL-004] | DONE |
| CCL-006 | actual_truth/DETERMINED_TASKS/CCL-006.md | BACKEND_ALIGNMENT | OWNER | course-cover | [CCL-004, CCL-005] | DONE |
| CCL-011 | actual_truth/DETERMINED_TASKS/CCL-011.md | BACKEND_ALIGNMENT | OWNER | lesson-content | [CCL-003] | DONE |
| CCL-007 | actual_truth/DETERMINED_TASKS/CCL-007.md | FRONTEND_ALIGNMENT | OWNER | course-cover | [CCL-006] | DONE |
| CCL-012 | actual_truth/DETERMINED_TASKS/CCL-012.md | FRONTEND_ALIGNMENT | OWNER | lesson-content | [CCL-011] | DONE |
| CCL-008 | actual_truth/DETERMINED_TASKS/CCL-008.md | FRONTEND_ALIGNMENT | OWNER | course-cover | [CCL-007] | DONE |
| CCL-013 | actual_truth/DETERMINED_TASKS/CCL-013.md | FRONTEND_ALIGNMENT | OWNER | lesson-content | [CCL-012] | DONE |
| CCL-014 | actual_truth/DETERMINED_TASKS/CCL-014.md | LEGACY_REMOVAL | OWNER | lesson-content | [CCL-013] | DONE |
| CCL-009 | actual_truth/DETERMINED_TASKS/CCL-009.md | LEGACY_REMOVAL | OWNER | course-cover | [CCL-008] | DONE |
| CCL-015 | actual_truth/DETERMINED_TASKS/CCL-015.md | TEST_ALIGNMENT | GATE | lesson-content | [CCL-014] | DONE |
| CCL-010 | actual_truth/DETERMINED_TASKS/CCL-010.md | TEST_ALIGNMENT | GATE | course-cover | [CCL-006, CCL-009] | DONE |
| CCL-016 | actual_truth/DETERMINED_TASKS/CCL-016.md | TEST_ALIGNMENT | GATE | lesson-content | [CCL-015] | DONE |
| CCL-017 | actual_truth/DETERMINED_TASKS/CCL-017.md | TEST_ALIGNMENT | GATE | cross-domain | [CCL-010, CCL-016] | NOT_STARTED |
| CCL-018 | actual_truth/DETERMINED_TASKS/CCL-018.md | TEST_ALIGNMENT | AGGREGATE | cross-domain | [CCL-017] | NOT_STARTED |
