# RWD POST-1067127 REMEDIATION TASK TREE

## 1. EXECUTIVE VERDICT

Status: GENERATED.

This is a remediation-only deterministic task tree for the remaining post-UWD gaps after:

- commit `1067127`
- the lesson-media placement reorder/delete decision in `actual_truth/contracts/media_pipeline_contract.md`
- the lesson delete media cleanup decision in `actual_truth/contracts/course_lesson_editor_contract.md`
- the media lifecycle authority contract in `actual_truth/contracts/media_lifecycle_contract.md`

No new authority decision is required for this tree.

This tree does not regenerate the UWD tree.
This tree does not reopen ratified authority.
This tree does not mix cleanup authority into lesson delete or placement delete.
This tree does not assume asset deletion during lesson delete.

Retrieval note:

- local `.repo_index` is absent
- no local index rebuild was performed
- GitHub code search fallback was used against `Odenhjalm/Aveli`
- direct repo inspection was used to reconcile the fallback hits against current working-tree contracts and source

## 2. REMAINING VERIFIED GAPS

### G1. Canonical placement reorder/delete surfaces are declared but not mounted.

Authority:

- `actual_truth/contracts/media_pipeline_contract.md` declares:
  - `PATCH /api/lessons/{lesson_id}/media-placements/reorder`
  - `DELETE /api/media-placements/{lesson_media_id}`
  - reorder may mutate only `app.lesson_media.position`
  - delete may delete only the target `app.lesson_media` row
  - neither may mutate `app.media_assets`
  - neither may write `app.runtime_media`

Current repo evidence:

- `backend/app/routes/studio.py` mounts `media_pipeline_router` with upload-url, upload-completion, placement attach, and placement read only.
- `backend/app/routes/studio.py` still mounts old write routes:
  - `PATCH /api/lesson-media/{lesson_id}/reorder`
  - `DELETE /api/lesson-media/{lesson_id}/{lesson_media_id}`
- old placement delete currently performs direct asset deletion when it sees no remaining lesson-media link.

Classification: active runtime drift.

### G2. Frontend still calls non-canonical reorder/delete routes.

Current repo evidence:

- `frontend/lib/features/studio/data/studio_repository_lesson_media.dart` calls:
  - `DELETE /api/lesson-media/$lessonId/$lessonMediaId`
  - `PATCH /api/lesson-media/$lessonId/reorder`
- `frontend/lib/features/studio/presentation/course_editor_page.dart` still routes editor reorder/delete actions through those repository methods.

Classification: active frontend drift.

### G3. Lesson delete must remove lesson-owned placement rows, not media assets.

Authority:

- `actual_truth/contracts/course_lesson_editor_contract.md` declares that lesson delete removes:
  - target `app.lesson_contents`
  - lesson-owned `app.lesson_media`
  - target `app.lessons`
- lesson delete must not create, update, or delete `app.media_assets`
- lesson delete must not write `app.runtime_media`
- asset cleanup after lesson delete is media lifecycle authority only

Current repo evidence:

- `backend/app/repositories/courses.py` deletes `app.lesson_contents` and `app.lessons`, but does not delete lesson-owned `app.lesson_media`.

Classification: active backend drift.

### G4. Lifecycle trigger integration is missing at the post-reference-removal boundary.

Authority:

- `actual_truth/contracts/media_lifecycle_contract.md` defines media lifecycle as the only authority allowed to delete `app.media_assets`.
- cleanup is asynchronous, idempotent, and may be triggered by explicit jobs, periodic GC, post-placement-delete signals, or post-lesson-delete signals.
- a signal may only request lifecycle evaluation and is not cleanup authority by itself.

Current repo evidence:

- old placement delete directly deletes `app.media_assets` through repository code.
- lesson delete does not yet remove placement rows and therefore does not yet emit a post-reference-removal lifecycle signal.

Classification: active backend/lifecycle drift.

### G5. Deleted tests removed canonical or canonical-adjacent coverage.

Coverage gaps after commit `1067127`:

- positive backend `cover_media_id` write persistence
- lesson delete placement cleanup without asset cleanup
- course-cover lifecycle safety and shared-reference protection

Historical source evidence:

- deleted `backend/tests/test_course_cover_pipeline.py` contained:
  - `test_studio_course_update_persists_cover_media_id`
  - `test_prune_course_cover_assets_skips_shared_lesson_storage`
  - `test_delete_media_asset_and_objects_skips_shared_media_object_storage`
  - `test_garbage_collect_media_reports_remaining_cover_storage_for_deleted_course`
- deleted `backend/tests/test_studio_media_delete_pipeline.py` contained asset-deleting lesson-delete coverage that must be replaced, not restored as-is.

Classification: test drift.

### G6. Dominance gates do not yet forbid the old reorder/delete surfaces.

Current repo evidence:

- `backend/tests/test_write_path_dominance_regression.py` forbids old upload/complete and studio media writes.
- it does not yet forbid:
  - `PATCH /api/lesson-media/{lesson_id}/reorder`
  - `DELETE /api/lesson-media/{lesson_id}/{lesson_media_id}`
- it does not yet assert the newly canonical reorder/delete route pair remains mounted.

Classification: test drift / dominance gate gap.

## 3. REMEDIATION TASK TREE

### RWD-001

- ID: RWD-001
- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Add canonical backend placement reorder/delete surfaces under `media_pipeline_router`: `PATCH /api/lessons/{lesson_id}/media-placements/reorder` and `DELETE /api/media-placements/{lesson_media_id}`. Reorder may mutate only `app.lesson_media.position`. Delete may delete only the target `app.lesson_media` row. Neither endpoint may create, update, or delete `app.media_assets`, and neither endpoint may write `app.runtime_media`. Preserve the old `/api/lesson-media` reorder/delete routes until frontend migration is complete.
- DEPENDS_ON: []

### RWD-002

- ID: RWD-002
- TYPE: FRONTEND_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Switch studio frontend reorder/delete callers to the canonical placement endpoints. `reorderLessonMedia` must call `PATCH /api/lessons/{lesson_id}/media-placements/reorder`. `deleteLessonMedia` must call `DELETE /api/media-placements/{lesson_media_id}`. Keep the existing lesson-media list/read behavior out of scope unless directly required by the route migration.
- DEPENDS_ON: [RWD-001]

### RWD-003

- ID: RWD-003
- TYPE: LEGACY_REMOVAL
- DOMAIN TAG: media
- DESCRIPTION: Remove or quarantine the non-canonical mounted write routes `PATCH /api/lesson-media/{lesson_id}/reorder` and `DELETE /api/lesson-media/{lesson_id}/{lesson_media_id}` after frontend switchover. Remove any direct asset deletion from the old placement-delete path as part of removing that path. Preserve non-write `/api/lesson-media` read/preview behavior unless separately governed by another task.
- DEPENDS_ON: [RWD-002]

### RWD-004

- ID: RWD-004
- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: lesson
- DESCRIPTION: Align lesson delete with `course_lesson_editor_contract.md` by deleting the target `app.lesson_contents` row, all `app.lesson_media` placement rows whose `lesson_id` is the deleted lesson, and the target `app.lessons` row. This task must not delete `app.media_assets`, must not write `app.runtime_media`, and must not treat lesson delete success as asset cleanup completion.
- DEPENDS_ON: []

### RWD-005

- ID: RWD-005
- TYPE: LIFECYCLE_INTEGRATION
- DOMAIN TAG: media
- DESCRIPTION: Add non-deleting media lifecycle trigger integration at the post-reference-removal boundary for canonical placement delete and lesson delete. The integration may request or enqueue lifecycle evaluation after placement links are removed, but it must not synchronously delete `app.media_assets` or storage objects in the placement-delete or lesson-delete request path. All asset deletion must remain under `media_lifecycle_contract.md` orphan verification and media lifecycle authority.
- DEPENDS_ON: [RWD-001, RWD-003, RWD-004]

### RWD-006

- ID: RWD-006
- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Add or update backend and frontend tests for canonical placement reorder/delete. Tests must assert canonical routes are used, old frontend reorder/delete route tokens are absent, reorder mutates only placement position, delete removes only the target placement link, and neither operation deletes `app.media_assets` or writes `app.runtime_media`.
- DEPENDS_ON: [RWD-005]

### RWD-007

- ID: RWD-007
- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: course
- DESCRIPTION: Restore or replace positive backend `cover_media_id` write persistence coverage for the canonical studio course update surface. The test must verify that a positive `cover_media_id` value persists as the structural course-cover pointer without introducing frontend cover-resolution authority or lifecycle cleanup behavior.
- DEPENDS_ON: []

### RWD-008

- ID: RWD-008
- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: lesson
- DESCRIPTION: Replace deleted lesson-delete media cleanup coverage with canonical lesson-delete placement cleanup coverage. Tests must assert lesson delete removes the lesson-owned `app.lesson_contents`, `app.lesson_media`, and `app.lessons` rows, does not delete `app.media_assets`, does not write `app.runtime_media`, and treats any asset cleanup as a separate media lifecycle concern.
- DEPENDS_ON: [RWD-004, RWD-005]

### RWD-009

- ID: RWD-009
- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Restore course-cover lifecycle safety coverage under `media_lifecycle_contract.md`. Tests must verify orphan checks, shared-reference preservation, double-check-before-delete behavior where applicable, and storage cleanup only after asset deletion is confirmed safe. Tests must not assert asset deletion from lesson delete or placement delete.
- DEPENDS_ON: [RWD-005]

### RWD-010

- ID: RWD-010
- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: cross-domain
- DESCRIPTION: Update write-path dominance regression gates so old reorder/delete surfaces cannot regain dominance. The gate must forbid `PATCH /api/lesson-media/{lesson_id}/reorder` and `DELETE /api/lesson-media/{lesson_id}/{lesson_media_id}`, assert canonical reorder/delete routes remain mounted, and assert studio frontend data paths no longer contain the old reorder/delete route tokens.
- DEPENDS_ON: [RWD-003, RWD-006]

### RWD-011

- ID: RWD-011
- TYPE: AUDIT_GATE
- DOMAIN TAG: cross-domain
- DESCRIPTION: Perform a final no-code end-state audit after remediation. The audit must verify canonical placement reorder/delete dominance, absence or quarantine of old `/api/lesson-media` reorder/delete writes, frontend route alignment, lesson delete placement cleanup without asset deletion, lifecycle separation, restored coverage, and no new contract or baseline authority gaps.
- DEPENDS_ON: [RWD-007, RWD-008, RWD-009, RWD-010]

## 4. DAG VALIDATION

The DAG is acyclic.

Topologically valid order:

1. RWD-001
2. RWD-004
3. RWD-007
4. RWD-002
5. RWD-003
6. RWD-005
7. RWD-006
8. RWD-008
9. RWD-009
10. RWD-010
11. RWD-011

Critical ordering checks:

- backend route alignment precedes frontend migration: RWD-001 -> RWD-002
- frontend migration precedes legacy removal: RWD-002 -> RWD-003
- lifecycle integration follows the canonical route and lesson-delete owners: RWD-001, RWD-003, RWD-004 -> RWD-005
- test alignment reflects canonical contracts after implementation owners: RWD-005 -> RWD-006, RWD-008, RWD-009
- dominance gate follows legacy removal and canonical placement tests: RWD-003, RWD-006 -> RWD-010
- final audit is the last node: RWD-011 depends on all terminal test/gate lanes

## 5. STOP CONDITIONS

No stop condition is active for task-tree generation.

Verified non-blockers:

- no new authority decision is required because placement reorder/delete, lesson delete media cleanup, and media lifecycle cleanup are already declared in contracts
- lifecycle integration is constrained to non-deleting trigger/evaluation boundaries
- task tree does not assume asset deletion during lesson delete or placement delete
- final audit remains no-code and last in the DAG

Execution-time stop conditions retained for future task execution:

- STOP if lifecycle integration would delete `app.media_assets` or storage objects directly from lesson delete or placement delete
- STOP if canonical placement delete cannot resolve ownership without adding a new authority decision
- STOP if a test tries to restore old lesson-delete asset deletion behavior as canonical
- STOP if old `/api/lesson-media` reorder/delete write surfaces remain reachable after RWD-003
- STOP if any task requires SQL or baseline mutation outside a separately declared baseline-owner task
