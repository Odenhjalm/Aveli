# TITLE
CCL Deterministic Task Index

## SOURCE AUTHORITY
actual_truth/DETERMINED_TASKS/CCL_course_cover_lesson_content_authority_task_tree.md

## MATERIALIZATION STATUS
MATERIALIZED_READY_FOR_CONTROLLER

## CHAIN STATUS
IN_PROGRESS

## CURRENT ELIGIBLE TASK SET
CCL-009, CCL-011

## CURRENT TASK
None

## LAST COMPLETED TASK
CCL-008

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
| CCL-011 | actual_truth/DETERMINED_TASKS/CCL-011.md | BACKEND_ALIGNMENT | OWNER | lesson-content | [CCL-003] | NOT_STARTED |
| CCL-007 | actual_truth/DETERMINED_TASKS/CCL-007.md | FRONTEND_ALIGNMENT | OWNER | course-cover | [CCL-006] | DONE |
| CCL-012 | actual_truth/DETERMINED_TASKS/CCL-012.md | FRONTEND_ALIGNMENT | OWNER | lesson-content | [CCL-011] | NOT_STARTED |
| CCL-008 | actual_truth/DETERMINED_TASKS/CCL-008.md | FRONTEND_ALIGNMENT | OWNER | course-cover | [CCL-007] | DONE |
| CCL-013 | actual_truth/DETERMINED_TASKS/CCL-013.md | FRONTEND_ALIGNMENT | OWNER | lesson-content | [CCL-012] | NOT_STARTED |
| CCL-014 | actual_truth/DETERMINED_TASKS/CCL-014.md | LEGACY_REMOVAL | OWNER | lesson-content | [CCL-013] | NOT_STARTED |
| CCL-009 | actual_truth/DETERMINED_TASKS/CCL-009.md | LEGACY_REMOVAL | OWNER | course-cover | [CCL-008] | NOT_STARTED |
| CCL-015 | actual_truth/DETERMINED_TASKS/CCL-015.md | TEST_ALIGNMENT | GATE | lesson-content | [CCL-014] | NOT_STARTED |
| CCL-010 | actual_truth/DETERMINED_TASKS/CCL-010.md | TEST_ALIGNMENT | GATE | course-cover | [CCL-006, CCL-009] | NOT_STARTED |
| CCL-016 | actual_truth/DETERMINED_TASKS/CCL-016.md | TEST_ALIGNMENT | GATE | lesson-content | [CCL-015] | NOT_STARTED |
| CCL-017 | actual_truth/DETERMINED_TASKS/CCL-017.md | TEST_ALIGNMENT | GATE | cross-domain | [CCL-010, CCL-016] | NOT_STARTED |
| CCL-018 | actual_truth/DETERMINED_TASKS/CCL-018.md | TEST_ALIGNMENT | AGGREGATE | cross-domain | [CCL-017] | NOT_STARTED |
