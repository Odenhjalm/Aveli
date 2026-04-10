# UWD WRITE PATH DOMINANCE TASK TREE

## Scope

- Domain: Course + Lesson Editor and Media Pipeline
- Mode: generate
- Source audit: write-path dominance refinement after the completed full audit
- Semantic retrieval fallback: GitHub connector code search, because `.repo_index` is absent and local index rebuild is forbidden by OS temporary Rule 6A

## Dominance Summary

| concern | dominant path | dominance | canonical status |
|---|---|---|---|
| course create | `POST /studio/courses` | PRIMARY | canonical route, frontend creation currently inert |
| course update | `PATCH /studio/courses/{course_id}` | PRIMARY | canonical |
| course delete | `DELETE /studio/courses/{course_id}` | PRIMARY | canonical |
| lesson create | `POST /studio/lessons` | PRIMARY | drift, mixed structure/content |
| lesson update | `PATCH /studio/lessons/{lesson_id}` | PRIMARY | drift, mixed structure/content |
| lesson delete | `DELETE /studio/lessons/{lesson_id}` | PRIMARY | canonical-compatible |
| lesson content write | `POST /studio/lessons` and `PATCH /studio/lessons/{lesson_id}` | PRIMARY | drift, no separate content endpoint |
| lesson media upload | `POST /api/lesson-media/{lesson_id}/upload-url` then `POST /api/lesson-media/{lesson_id}/{lesson_media_id}/complete` | PRIMARY | drift, upload creates placement |
| lesson media attach | implicit attach during `/api/lesson-media/{lesson_id}/upload-url` | PRIMARY | drift, ingest and placement conflated |
| legacy media upload | `/api/media/*`, `/studio/lessons/{lesson_id}/media*`, `/api/upload/*`, `/upload/*` | SHADOW/DEAD | non-canonical |

## Task Tree

### UWD-001

- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: cross-domain
- DESCRIPTION: Establish a write-path isolation boundary for all active, shadow, and dead write routes in this scope without changing canonical authorities. Mark mixed lesson writes, implicit media attach, disabled studio media writes, unmounted `api_media`, unmounted `upload`, and helper-only model writes as non-canonical implementation surfaces.
- DEPENDS_ON: []

### UWD-002

- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: lesson
- DESCRIPTION: Add the canonical Course + Lesson Editor backend write surfaces while preserving isolated legacy paths during switchover: `POST /studio/courses/{course_id}/lessons`, `PATCH /studio/lessons/{lesson_id}/structure`, and `PATCH /studio/lessons/{lesson_id}/content`. Split service and repository calls so lesson structure writes only touch `app.lessons` and content writes only touch backend-normalized `app.lesson_contents.content_markdown`.
- DEPENDS_ON: [UWD-001]

### UWD-003

- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Add the canonical lesson-media backend write surfaces while preserving isolated legacy paths during switchover: `POST /api/lessons/{lesson_id}/media-assets/upload-url`, `POST /api/media-assets/{media_asset_id}/upload-completion`, `POST /api/lessons/{lesson_id}/media-placements`, and `GET /api/media-placements/{lesson_media_id}`. Ensure ingest creates exactly one `media_assets` row and zero `lesson_media` rows, and placement creates exactly one `lesson_media` row and zero `media_assets` rows.
- DEPENDS_ON: [UWD-001]

### UWD-004

- TYPE: FRONTEND_ALIGNMENT
- DOMAIN TAG: content
- DESCRIPTION: Switch the studio course editor from mixed lesson writes to the canonical lesson structure/content split. Replace `upsertLesson` mixed payload usage with separate structure create/update calls and content update calls, and keep frontend markdown normalization as convenience only, not authority.
- DEPENDS_ON: [UWD-002]

### UWD-005

- TYPE: FRONTEND_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Switch studio lesson-media upload callers from `/api/lesson-media/{lesson_id}/upload-url` plus implicit placement to the canonical upload-url, upload-completion, and placement-attach sequence. Remove frontend dependence on upload responses that return `lesson_media_id` before placement exists.
- DEPENDS_ON: [UWD-003]

### UWD-006

- TYPE: LEGACY_REMOVAL
- DOMAIN TAG: lesson
- DESCRIPTION: Remove the mounted mixed lesson write surfaces `POST /studio/lessons` and `PATCH /studio/lessons/{lesson_id}` after frontend switchover. Preserve only canonical lesson delete and reorder behavior where contract-compatible.
- DEPENDS_ON: [UWD-004]

### UWD-007

- TYPE: LEGACY_REMOVAL
- DOMAIN TAG: media
- DESCRIPTION: Remove or unmount non-canonical mounted media write surfaces after frontend switchover: implicit-placement `/api/lesson-media/{lesson_id}/upload-url`, `/api/lesson-media/{lesson_id}/{lesson_media_id}/complete`, disabled `/studio/lessons/{lesson_id}/media*`, legacy `/studio/media/{media_id}` delete, and legacy `/studio/lessons/{lesson_id}/media/reorder`.
- DEPENDS_ON: [UWD-005]

### UWD-008

- TYPE: LEGACY_REMOVAL
- DOMAIN TAG: cross-domain
- DESCRIPTION: Quarantine or remove dead but dangerous write callers and helpers after active paths are replaced: unmounted `backend/app/routes/api_media.py`, unmounted `backend/app/routes/upload.py`, helper-only media model mutation paths, importer calls to mixed lesson/media endpoints, landing `studioUploads.ts` calls to `/api/media/*`, and stale media upload tests that still invoke unmounted routes as positive paths.
- DEPENDS_ON: [UWD-006, UWD-007]

### UWD-009

- TYPE: BACKEND_ALIGNMENT
- DOMAIN TAG: runtime
- DESCRIPTION: Enforce canonical write-path invariants after removal: structure endpoints reject `content_markdown`, content endpoint rejects structure fields, media ingest rejects placement output, placement rejects asset creation, no write path mutates `runtime_media`, and runtime playback remains `media_assets -> lesson_media -> runtime_media -> backend read composition`.
- DEPENDS_ON: [UWD-006, UWD-007, UWD-008]

### UWD-010

- TYPE: FRONTEND_ALIGNMENT
- DOMAIN TAG: runtime
- DESCRIPTION: Remove frontend contract dependencies that only existed for legacy write/read paths: `ApiPaths.mediaUploadUrl`, `ApiPaths.mediaComplete`, `ApiPaths.mediaAttach` for governed lesson-media writes, `preview_ready`, `original_name`, `resolved_preview_url`, and any frontend media resolver path that constructs playback outside backend-authored media objects.
- DEPENDS_ON: [UWD-009]

### UWD-011

- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: course
- DESCRIPTION: Rewrite backend Course + Lesson Editor tests to assert the canonical split: course writes remain canonical, lesson create/update structure surfaces are separate from content writes, mixed lesson write routes are absent, and studio lesson list reads do not expose `content_markdown`.
- DEPENDS_ON: [UWD-009]

### UWD-012

- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: media
- DESCRIPTION: Rewrite backend and frontend media pipeline tests to assert the canonical three-step media write chain, no upload-time placement, no completion-time attach, no `/api/media/*` positive-path dependencies, no legacy studio media write route dependence, and canonical placement read media shape only.
- DEPENDS_ON: [UWD-009, UWD-010]

### UWD-013

- TYPE: TEST_ALIGNMENT
- DOMAIN TAG: cross-domain
- DESCRIPTION: Add dominance regression gates that fail if non-canonical write dominance returns: mixed lesson writes, implicit media attach, unmounted `/api/media/*` write callers, disabled studio media writes, direct `runtime_media` writes, or frontend construction of governed media playback.
- DEPENDS_ON: [UWD-011, UWD-012]

### UWD-014

- TYPE: LEGACY_REMOVAL
- DOMAIN TAG: cross-domain
- DESCRIPTION: Clean up stale support artifacts only after test alignment passes: importer route comments, stale docs/task mirrors that still name old dominant write paths as canonical, skipped or quarantined tests that no longer describe valid runtime risk, and obsolete helper wrappers that are no longer imported.
- DEPENDS_ON: [UWD-013]

## DAG Validation

- Roots: UWD-001
- Isolation before removal: UWD-001 precedes UWD-006, UWD-007, and UWD-008.
- Removal before enforcement: UWD-006, UWD-007, and UWD-008 precede UWD-009.
- Enforcement before test alignment: UWD-009 precedes UWD-011, UWD-012, and UWD-013.
- Test alignment before cleanup: UWD-013 precedes UWD-014.
- No dependency points forward to a later prerequisite.
- No cycles.
