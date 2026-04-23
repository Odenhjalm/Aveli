# LER-002 DOCUMENT SUBSTRATE AND API SHAPE

TYPE: `OWNER`
TASK_TYPE: `BACKEND_SUBSTRATE`
DEPENDS_ON: `[LER-001]`
EXECUTION_STATUS: `COMPLETED`

## Goal

Materialize the `lesson_document_v1` substrate and content read/write API shape
without creating a legacy data migration task.

## Required Outputs

- content persistence supports `content_document`
- editor content read returns `content_document` and `ETag`
- editor content write accepts `content_document` and requires `If-Match`
- ETag behavior remains content-only
- structure endpoints remain structure-only

## Forbidden

- using `content_markdown` as new editor authority
- adding migration of old lesson Markdown as a precondition
- mixing lesson title or position into content writes

## Verification

Backend API and repository tests prove `content_document` can be read and
written with ETag compare-and-set semantics.

## Stop Conditions

Stop if baseline/storage authority for `content_document` cannot be expressed
without weakening structure/content separation.

## Execution Record

Date: `2026-04-23`

Status: `COMPLETED`

### Completed Materialization

- Added append-only baseline candidate slot `backend/supabase/baseline_v2_slots/V2_0029_lesson_document_content.sql`.
- The slot expresses `app.lesson_contents.content_document jsonb not null default '{"schema_version":"lesson_document_v1","blocks":[]}'::jsonb`.
- The slot rebuilds `app.lesson_content_surface` with `content_document` as rebuilt-editor content authority while retaining `content_markdown` as legacy compatibility evidence only.
- Updated `backend/supabase/baseline_v2_slots.lock.json` with slot 29 after isolated local replay produced observed `post_state_hash`.
- Updated active studio content schemas so `StudioLessonContentUpdate`, `StudioLessonContentRead`, and `StudioLessonContent` use `content_document`.
- Updated active mounted studio content write route so PATCH `/lessons/{lesson_id}/content` passes `payload.content_document`.
- Updated `courses_service.build_lesson_content_etag` to hash canonical JSON bytes for `lesson_document_v1` instead of Markdown text.
- Updated `courses_service.read_studio_lesson_content` to return `content_document`, media, and an ETag derived from canonical document JSON.
- Updated `courses_service.update_lesson_content` to accept `content_document`, require `If-Match`, compare against the current document ETag, and write through repository CAS.
- Added repository read/write functions for `content_document`:
  - `get_studio_lesson_content` reads `content_document` with the empty document default.
  - `update_lesson_document_if_current` performs JSONB compare-and-set using the expected document.
- Added `backend/tests/test_lesson_document_content_backend_contract.py` to cover schema shape, canonical JSON ETag behavior, service CAS behavior, and repository JSONB-CAS boundary.
- Added `backend/tests/test_studio_lesson_document_content_api.py` to cover the active studio API read/write surface with `content_document`, `ETag`, missing `If-Match`, stale `If-Match`, and persisted readback.
- Updated `backend/tests/test_baseline_v2_cutover_lock_replay.py` with slot 29 replay expectations.

### Validation Against Required Outputs

- `content persistence supports content_document`: `PASS_REPLAYED`; SQL slot 29 was replayed in an isolated local database and recorded in the V2 lock.
- `editor content read returns content_document and ETag`: `PASS_TESTED`; schema/service tests cover read body shape and ETag.
- `editor content write accepts content_document and requires If-Match`: `PASS_TESTED`; service tests cover missing, stale, and matching preconditions.
- `ETag behavior remains content-only`: `PASS_TESTED`; ETag input is lesson id plus canonical content document bytes only.
- `structure endpoints remain structure-only`: `PASS_STATIC`; no structure route was modified to carry `content_document`.

### Verification Evidence

- `python -m compileall backend\app\services\courses_service.py backend\app\repositories\courses.py backend\app\routes\studio.py backend\app\schemas\__init__.py` passed.
- `python -m json.tool backend\supabase\baseline_v2_slots.lock.json > $null` passed.
- `python -m json.tool actual_truth\DETERMINED_TASKS\lesson_editor_rebuild\task_manifest.json > $null` passed before status finalization.
- Task-scoped grep confirmed the active studio PATCH route calls `content_document=payload.content_document`.
- Task-scoped grep confirmed `courses_service.update_lesson_content` calls `courses_repo.update_lesson_document_if_current`.
- Isolated local baseline replay to slot 29 produced `post_state_hash = 2b46e1197f4228d845736eaa6561a61b5364043236a25a16855809e770e6cc64`.
- Isolated local baseline replay to slot 29 produced runtime schema hash `61ecf976b5e8bf124685c06cbc3394d6461a1ae16e22ce25ea157cd76c30fdfb`.
- `V2_0029_lesson_document_content.sql` LF-normalized SHA256 is `0110cf23adc31535a8976ad0ced6610832c9d1fc82e3140ff30c596ed0dd94ae`.
- `pytest backend\tests\test_lesson_document_content_backend_contract.py` passed.
- `pytest backend\tests\test_studio_lesson_document_content_api.py` passed.
- `PYTHONPATH=<repo-root> pytest backend\tests\test_baseline_v2_authority_lock.py backend\tests\test_baseline_v2_cutover.py backend\tests\test_lesson_supported_content_fixture_corpus.py` passed.
- `PYTHONPATH=<repo-root> pytest backend\tests\test_baseline_v2_cutover_lock_replay.py` passed with `DATABASE_URL` loaded from local `backend/.env.local`.

### Environment Note

The process environment initially lacked `DATABASE_URL`. `backend/.env.local`
provided a local-only `127.0.0.1` database URL. Replay verification used
temporary isolated databases. After the lock was updated from observed replay
evidence, slot `V2_0029_lesson_document_content.sql` was applied to the
existing local `aveli_local` database because it lacked `content_document`.
This was a schema-only local runtime alignment; no legacy Markdown data was
migrated into document content.

Local runtime verification:

- before applying slot 29 locally: `content_document` column absent
- after applying slot 29 locally: `content_document` column present
- `app.lesson_content_surface` exposes `content_document`

### Status Decision

`LER-002` is complete. `LER-003` and `LER-004` are now eligible successors.
