# CCL COURSE COVER + LESSON CONTENT AUTHORITY TASK TREE

## 1. EXECUTIVE VERDICT

Status: REVISED TIGHTENED.

This is a single coordinated implementation task tree for two isolated fail domains:

- Course Cover Authoring Authority: media -> course.cover_media_id -> render
- Studio Lesson Content Read Authority: content_markdown -> editor hydration

This tree does not implement anything.
This tree does not mutate code, contracts, SQL, database state, or runtime state.

Retrieval note:

- local `.repo_index` is absent
- no local index rebuild was performed
- GitHub code search fallback was used against `Odenhjalm/Aveli`
- direct repo inspection was used to reconcile fallback hits against current working-tree contracts and source

## 2. AUTHORITY SUMMARY

### Course Cover Authority

Canonical identity:

- `app.courses.cover_media_id`

Canonical media prerequisites:

- `app.media_assets` owns media identity
- `app.runtime_media` owns runtime readiness and resolution eligibility
- backend read composition owns frontend-facing `cover = { media_id, state, resolved_url } | null`

Forbidden:

- worker assigning course cover
- frontend resolving cover storage or playback
- `/api/media/cover-*` as mounted canonical truth
- `cover` as write authority
- local preview as persisted truth

Single canonical path to create:

1. canonical media ingest pipeline creates or completes a governed image asset with explicit course-cover scope
2. worker processes media and produces runtime truth only
3. teacher assigns or clears cover through course structure authority only
4. backend read composition emits `cover`
5. frontend renders only backend-provided `cover.resolved_url`

There must be exactly one media ingest authority. Course-cover ingest must reuse the canonical media ingest pipeline with explicit course-cover scope. It must not introduce a parallel media lifecycle, parallel media identity creator, parallel upload-completion authority, or cover-specific runtime resolver.

### Studio Lesson Content Read Authority

Canonical identity:

- `app.lesson_contents.content_markdown`

Forbidden:

- `content_markdown` in studio lesson structure list responses
- `content_markdown` in studio lesson structure models
- editor hydration from lesson structure lists
- frontend/editor state as content authority
- implicit overwrite from empty hydration

Single canonical path to create:

1. dedicated editor content read returns only lesson content authority and a backend-issued concurrency token
2. studio structure reads remain structure-only
3. editor hydrates from the dedicated content read
4. editor writes through the existing canonical content write surface with the current backend-issued concurrency token
5. tests prove switching lessons and saving cannot overwrite persisted content unintentionally

## 3. EXECUTION GRAPH

Topologically valid order:

1. CCL-001
2. CCL-002
3. CCL-003
4. CCL-004
5. CCL-005
6. CCL-006
7. CCL-011
8. CCL-007
9. CCL-012
10. CCL-008
11. CCL-013
12. CCL-014
13. CCL-009
14. CCL-015
15. CCL-010
16. CCL-016
17. CCL-017
18. CCL-018

Dependency edges:

- CCL-001 -> CCL-003
- CCL-002 -> CCL-003
- CCL-003 -> CCL-004
- CCL-003 -> CCL-011
- CCL-004 -> CCL-005
- CCL-004 -> CCL-006
- CCL-005 -> CCL-006
- CCL-006 -> CCL-007
- CCL-006 -> CCL-010
- CCL-007 -> CCL-008
- CCL-008 -> CCL-009
- CCL-009 -> CCL-010
- CCL-011 -> CCL-012
- CCL-011 -> CCL-016
- CCL-012 -> CCL-013
- CCL-013 -> CCL-014
- CCL-014 -> CCL-015
- CCL-015 -> CCL-016
- CCL-010 -> CCL-017
- CCL-016 -> CCL-017
- CCL-017 -> CCL-018

Cross-domain dependency:

- CCL-004 and CCL-005 create the media-readiness truth that CCL-006 must validate before `cover_media_id` assignment.
- CCL-006 creates course cover assignment truth that CCL-008 and CCL-010 must consume.
- CCL-011 creates lesson content read truth that CCL-013 and CCL-014 must consume.
- CCL-017 joins the cover and lesson lanes before final global dominance verification.

Mutation plane separation:

1. CONTRACT_UPDATE tasks define authority and route contracts only.
2. BASELINE_SLOT task determines whether append-only baseline work is required before backend work.
3. BACKEND_ALIGNMENT tasks change backend route, schema, service, repository, worker, and read composition behavior.
4. FRONTEND_ALIGNMENT tasks change repository, model, widget, page, and editor lifecycle behavior.
5. LEGACY_REMOVAL tasks remove or quarantine superseded paths after replacements exist.
6. TEST_ALIGNMENT tasks validate canonical behavior and block authority regressions.

## 4. TASK TREE

### CCL-001

- TASK ID: CCL-001
- TYPE: CONTRACT_UPDATE
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Define the canonical course cover authoring contract. The contract must state that `app.courses.cover_media_id` is the only course-cover identity; `cover` is backend-authored read data only; media ingest and worker processing create media/runtime truth only; teacher assignment and clear use course structure authority only; frontend renders only backend-provided `cover.resolved_url`; `/api/media/cover-*` is not canonical authority. Lock the course-cover read shape as `cover = { media_id, state, resolved_url } | null`; `media_id`, `state`, and `resolved_url` are read-only backend output; `cover` is never accepted as request input; `resolved_url` must never be reconstructed by the frontend from storage paths, media IDs, filenames, buckets, or preview URLs.
- DEPENDS_ON: []
- MUTATION PLANE: contracts only
- VERIFICATION: Contract review proves no cover assignment authority exists in media pipeline, worker, frontend preview, or read composition, and proves the only frontend-authoritative cover render field is backend-provided `cover.resolved_url` inside the locked `cover` response object.

### CCL-002

- TASK ID: CCL-002
- TYPE: CONTRACT_UPDATE
- ROLE: OWNER
- DOMAIN TAG: lesson-content
- DESCRIPTION: Define the canonical studio editor lesson content read contract. The contract must add a dedicated editor content read surface for existing persisted `app.lesson_contents.content_markdown`, keep `/studio/courses/{course_id}/lessons` structure-only, and require editor hydration to use the content read surface only. Lock the content read body as `{ lesson_id, content_markdown, media }`, where `lesson_id` identifies the lesson, `content_markdown` is the backend-authored persisted markdown string, and `media` is a read-only backend-authored list of governed media objects if applicable, otherwise an empty list. The response must not include lesson structure fields such as `lesson_title`, `position`, or course structure payload. The dedicated content read must also emit the canonical concurrency token as an HTTP `ETag`; content writes must use `If-Match` with that token, and successful writes must return the backend-normalized content body plus the replacement `ETag`. Structure endpoints must never expose `content_markdown`, content media resolver fields, or content concurrency tokens.
- DEPENDS_ON: []
- MUTATION PLANE: contracts only
- VERIFICATION: Contract review proves structure reads never expose `content_markdown`, content reads never mutate structure, the content read response shape is stable, and the write surface remains the existing canonical content write guarded by the backend-issued concurrency token.

### CCL-003

- TASK ID: CCL-003
- TYPE: BASELINE_SLOT
- ROLE: GATE
- DOMAIN TAG: cross-domain
- DESCRIPTION: Perform the baseline substrate decision after CCL-001 and CCL-002. Verify whether existing baseline substrate already provides `app.courses.cover_media_id`, `app.media_assets`, `app.runtime_media`, `app.lesson_contents`, storage substrate, and required constraints for the two contracts. CCL-003 is the only baseline slot in this tree. If required substrate is missing and can be handled inside this baseline slot without changing the DAG, keep it isolated to this mutation plane before backend alignment; if it cannot be handled inside CCL-003 without adding task IDs or changing the graph, execution must STOP and report the baseline blocker. If no substrate is missing, record that no baseline mutation is required for this repair.
- DEPENDS_ON: [CCL-001, CCL-002]
- MUTATION PLANE: baseline only if required by substrate audit and only inside CCL-003
- VERIFICATION: Backend work is blocked until the baseline decision is explicit, no required runtime authority lacks substrate ownership, and no new task ID or hidden baseline mutation has been introduced.

### CCL-004

- TASK ID: CCL-004
- TYPE: BACKEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Reuse the canonical media ingest pipeline for course-cover ingest with explicit course-cover scope. This task must not create a second media ingest authority. If a mounted cover-scoped route is added, it is only a thin scoped adapter into the same canonical media ingest service/repository that creates `app.media_assets`, issues upload targets, confirms completion, and reports media state. Media identity creation remains owned only by the canonical media pipeline. Cover ingest must accept image assets only and must persist a backend-verifiable course/teacher scope or association required by CCL-006; that scope must not be inferred later from filenames, UI state, preview state, or client-only request context. Cover ingest must not set `app.courses.cover_media_id`, create frontend representation, fork upload-completion/status logic, write `runtime_media` directly, or bypass worker/runtime readiness. `/api/media/cover-*` must not become the positive path.
- DEPENDS_ON: [CCL-003]
- MUTATION PLANE: backend routes, schemas, services, repositories
- VERIFICATION: Backend route inspection proves there is exactly one media ingest authority, course-cover ingest delegates to the canonical media ingest pipeline, media identity is created only by the canonical pipeline, and `/api/media/cover-*` is not used as the positive path.

### CCL-005

- TASK ID: CCL-005
- TYPE: BACKEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Align course-cover worker behavior so worker processing creates runtime truth only. The worker may transform a course-cover media asset and update canonical media/runtime readiness, but it must never assign, replace, or clear `app.courses.cover_media_id`, and must not report cover assignment as a worker side effect.
- DEPENDS_ON: [CCL-004]
- MUTATION PLANE: backend worker and media repositories
- VERIFICATION: Worker tests and source inspection prove no worker path writes course cover assignment.

### CCL-006

- TASK ID: CCL-006
- TYPE: BACKEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Align course structure write authority for cover assignment and clear. `PATCH /studio/courses/{course_id}` must be the single mounted assignment/clear path for `cover_media_id`. The only allowed assignment input is `cover_media_id: <uuid>`; the only allowed clear input is `cover_media_id: null`; omitting `cover_media_id` means no cover change. Assignment must validate, on the backend only, that the media asset exists, is image media, is produced by the canonical media ingest pipeline, has a backend-verifiable scope or association to the same course and authorized teacher context, and is runtime-ready according to backend/runtime truth. Runtime-ready means backend read composition can emit `cover = { media_id, state, resolved_url }` with `state` ready and non-null `resolved_url`; otherwise assignment must fail closed. Reject non-image media, pending/uploaded/processing/failed media, missing runtime readiness, wrong-course media, wrong-teacher media, unscoped media, missing assets, raw URL inputs, storage path inputs, and `cover` object inputs. Clear must remove only the course pointer and must not delete media assets, storage objects, or runtime rows. Course create/update schemas and repository behavior must support set and clear without using `cover` as write authority. Worker-based assignment, frontend-driven validation as authority, and implicit assignment during ingest are forbidden.
- DEPENDS_ON: [CCL-004, CCL-005]
- MUTATION PLANE: backend routes, schemas, services, repositories
- VERIFICATION: Backend tests prove assign, persist, clear, no-change omission, and rejection of every invalid media case through course structure authority only; tests also prove ingest and worker paths cannot assign cover and frontend-provided validation cannot bypass backend policy.

### CCL-007

- TASK ID: CCL-007
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Replace inert cover methods in `MediaPipelineRepository` and studio cover authoring callers with the canonical flow. Direct cover upload must call the canonical media ingest pipeline through the course-cover scope defined by CCL-004; completion/status must consume backend media state; assignment and clear must call the course structure update path with `cover_media_id`; lesson-media-as-cover convenience must either be removed or routed through the same contract-defined cover media identity and the same course assignment path. Frontend code may perform user guidance checks, but those checks are never authority and must not create an alternate acceptance policy, URL resolver, upload-completion flow, or implicit assignment.
- DEPENDS_ON: [CCL-006]
- MUTATION PLANE: frontend repositories, widgets, pages
- VERIFICATION: Frontend source inspection proves no positive cover path calls inert `_unavailable()` methods or `/api/media/cover-*`.

### CCL-008

- TASK ID: CCL-008
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Align studio editor preview and learner rendering for course covers. Local upload preview may be temporary UI state only and must never become authority. Studio course editor, course page, catalog, and learner surfaces must render the persisted cover only from backend-provided `cover.resolved_url` from the locked `cover = { media_id, state, resolved_url } | null` response shape. Frontend must not reconstruct URLs from `media_id`, storage path, bucket, filename, upload URL, signed URL, or previous preview state, and must not treat `cover_media_id` alone as renderable media.
- DEPENDS_ON: [CCL-007]
- MUTATION PLANE: frontend widgets/pages/models
- VERIFICATION: Frontend tests prove preview is non-authoritative and learner rendering consumes only backend `cover.resolved_url`.

### CCL-009

- TASK ID: CCL-009
- TYPE: LEGACY_REMOVAL
- ROLE: OWNER
- DOMAIN TAG: course-cover
- DESCRIPTION: Remove or quarantine all non-canonical cover authoring surfaces after the canonical frontend path exists. This includes unmounted `/api/media/cover-upload-url`, `/api/media/cover-from-media`, `/api/media/cover-clear`, missing helper references such as `clear_course_cover` and `set_course_cover_media_id_if_unset` if they remain outside canonical course structure authority, stale mocks that make unmounted cover routes look canonical, and any dead route comments that imply media pipeline assignment authority.
- DEPENDS_ON: [CCL-008]
- MUTATION PLANE: legacy route/helpers/test fixture cleanup
- VERIFICATION: Route inventory and source scans prove no active or positive test path treats `/api/media/cover-*` or worker cover promotion as canonical.

### CCL-010

- TASK ID: CCL-010
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: course-cover
- DESCRIPTION: Align course-cover tests end-to-end. Tests must prove cover upload through the single canonical media ingest authority with course-cover scope, completion, worker readiness, assignment through `PATCH /studio/courses/{course_id}`, persistence in `app.courses.cover_media_id`, backend read composition into `cover = { media_id, state, resolved_url } | null`, frontend render from `cover.resolved_url`, clear behavior, no-change omission behavior, invalid media rejection for non-image, non-ready, wrong-course, wrong-teacher, unscoped, missing, raw URL, storage path, and `cover` object inputs, worker no-assignment behavior, and absence of `/api/media/cover-*` positive paths.
- DEPENDS_ON: [CCL-006, CCL-009]
- MUTATION PLANE: tests only
- VERIFICATION: Scoped backend and frontend cover tests pass and fail closed on duplicate authority paths.

### CCL-011

- TASK ID: CCL-011
- TYPE: BACKEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: lesson-content
- DESCRIPTION: Add the dedicated mounted studio lesson content read endpoint defined by CCL-002. The endpoint must read `app.lesson_contents.content_markdown` through backend authority, return only the locked content body `{ lesson_id, content_markdown, media }`, emit the backend-issued `ETag` concurrency token, enforce teacher/course authorization, and keep structure endpoints unchanged and content-free. `media`, if applicable, must be backend-authored governed media output only and must not expose storage paths, signed URLs, upload URLs, or frontend-resolved URLs. Existing content write behavior must remain through `PATCH /studio/lessons/{lesson_id}/content`, but it must reject writes without a matching `If-Match` token and return a stale-state failure without persisting when the token no longer matches current content authority.
- DEPENDS_ON: [CCL-003]
- MUTATION PLANE: backend routes, schemas, services, repositories
- VERIFICATION: Backend route and schema tests prove content read exists, returns exactly the locked content body plus the HTTP `ETag`, rejects stale or tokenless writes, and proves structure list/create/update responses do not contain `content_markdown`, content media, or content concurrency tokens.

### CCL-012

- TASK ID: CCL-012
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: lesson-content
- DESCRIPTION: Align studio frontend repository and models with the dedicated content read. `StudioRepository` must expose a content read call that returns `lesson_id`, `content_markdown`, `media`, and the backend-issued `ETag` as transport metadata; `LessonStudio` and all structure-list models must remove `contentMarkdown`; editor content write models must remain content-only and must carry only the write payload plus the required concurrency token at the repository/transport boundary; course lesson list hydration must not infer content from structure responses.
- DEPENDS_ON: [CCL-011]
- MUTATION PLANE: frontend repositories and models
- VERIFICATION: Frontend unit tests prove structure models cannot carry `content_markdown` and repository content reads use the dedicated endpoint.

### CCL-013

- TASK ID: CCL-013
- TYPE: FRONTEND_ALIGNMENT
- ROLE: OWNER
- DOMAIN TAG: lesson-content
- DESCRIPTION: Rewrite studio editor hydration lifecycle to load persisted lesson content from the dedicated content read endpoint only. The canonical concurrency model is backend `ETag` on content read plus `If-Match` on content write. The editor must store the latest successful content token per selected lesson, include that token on save, and treat stale-write failures as non-persisted conflict states that require rehydration before retry. Failed hydration must keep save disabled for that lesson until a successful content read or explicit user recovery path obtains a new token. Empty content is valid only when it comes from successful hydration of persisted empty content, or when the user intentionally clears content after successful hydration; it must never be persisted because structure data lacked content, a content read failed, a lesson switch raced, or the editor initialized with an empty fallback. The editor must guard stale requests during lesson/course switches, preserve dirty state intentionally, and align read/write surfaces so saving cannot overwrite existing content unintentionally.
- DEPENDS_ON: [CCL-012]
- MUTATION PLANE: frontend editor page/state lifecycle
- VERIFICATION: Widget tests prove persisted content loads through the endpoint, the current `ETag` is used on save, stale-write failures do not persist, switching lessons is stable, failed content reads fail closed, intentional empty clears are distinguishable from fallback empty state, and save does not fire from empty structure hydration.

### CCL-014

- TASK ID: CCL-014
- TYPE: LEGACY_REMOVAL
- ROLE: OWNER
- DOMAIN TAG: lesson-content
- DESCRIPTION: Remove or quarantine legacy lesson content-in-structure assumptions after the canonical hydration path exists. This includes frontend fixtures that inject `content_markdown` into `listCourseLessons`, stale `LessonStudio.contentMarkdown` usage, raw-map structure mocks with legacy `title` or `is_intro` when they mask content authority, and helper-only backend paths that make mixed lesson payloads look canonical.
- DEPENDS_ON: [CCL-013]
- MUTATION PLANE: legacy frontend/backend/test fixture cleanup
- VERIFICATION: Source scans prove `content_markdown` no longer appears in studio lesson structure models, structure-list mocks, or positive structure-read assertions.

### CCL-015

- TASK ID: CCL-015
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: lesson-content
- DESCRIPTION: Align backend lesson-content read tests. Tests must prove the dedicated editor content read returns persisted `content_markdown`, the locked body `{ lesson_id, content_markdown, media }`, and the backend-issued `ETag`; structure list/create/update responses remain content-free; content write/read round trips preserve backend-normalized markdown; writes require matching `If-Match`; stale writes fail without persistence; unauthorized reads are rejected; and no structure endpoint can become content authority.
- DEPENDS_ON: [CCL-014]
- MUTATION PLANE: backend tests only
- VERIFICATION: Scoped backend lesson-content tests pass and fail closed on content leakage into structure endpoints.

### CCL-016

- TASK ID: CCL-016
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: lesson-content
- DESCRIPTION: Align frontend lesson-content editor tests. Tests must prove editor hydration calls the dedicated content endpoint, structure list fixtures omit `content_markdown`, persisted content renders in the editor, save uses the canonical write endpoint with the current backend-issued concurrency token only after valid hydration or intentional user edits, failed hydration disables persistence, stale-write failures do not overwrite content, intentional empty clear is explicit, and lesson switching cannot overwrite content with an empty fallback.
- DEPENDS_ON: [CCL-015]
- MUTATION PLANE: frontend tests only
- VERIFICATION: Scoped frontend editor tests pass and fail closed on structure-list hydration.

### CCL-017

- TASK ID: CCL-017
- TYPE: TEST_ALIGNMENT
- ROLE: GATE
- DOMAIN TAG: cross-domain
- DESCRIPTION: Add cross-domain dominance gates. The gates must prove there is exactly one authority path for media ingest, cover assignment, lesson content read, and lesson content write; no duplicate cover assignment path; no mounted `/api/media/cover-*` positive route; no inert cover method used by mounted frontend UI; no worker cover assignment; no frontend cover URL construction; no `content_markdown` in studio lesson structure models or responses; no editor hydration from structure lists; no content write without a valid backend-issued concurrency token; and no implicit empty-content persistence. The gate must also verify product-facing text touched in these domains is Swedish and developer/operator prompts remain English and copy-paste ready.
- DEPENDS_ON: [CCL-010, CCL-016]
- MUTATION PLANE: tests and static dominance scans only
- VERIFICATION: Static route/source scans and scoped tests prove no duplicate authority path remains in either domain.

### CCL-018

- TASK ID: CCL-018
- TYPE: TEST_ALIGNMENT
- ROLE: AGGREGATE
- DOMAIN TAG: cross-domain
- DESCRIPTION: Perform final scoped verification for the coordinated repair. Verify cover upload through exactly one media ingest authority, assignment, persistence, backend read composition, frontend render, deterministic clear/no-change behavior, and no unmounted/inert cover path. Verify editor content read hydration, content-free structure endpoints, `ETag`/`If-Match` write safety, stale-state failure, failed-hydration failure closure, intentional empty clear behavior, and no legacy content-in-structure path. Verify tests reflect canonical behavior and no legacy paths remain active.
- DEPENDS_ON: [CCL-017]
- MUTATION PLANE: verification only
- VERIFICATION: Final scoped PASS is allowed only if both domains pass together and no authority conflicts remain.

## 5. CRITICAL STAGE GATES

### Gate A: Contract Gate

- TASKS: CCL-001, CCL-002
- PASS CONDITION: Both contracts define one authority per concept, lock the cover and lesson-content response shapes, define read-only fields, forbid frontend media URL reconstruction, forbid content leakage into structure responses, and leave no route or representation ambiguity.

### Gate B: Baseline Gate

- TASK: CCL-003
- PASS CONDITION: Required runtime substrate exists or the required append-only baseline mutation is confined to CCL-003 before backend alignment; otherwise execution stops.

### Gate C: Cover Backend Gate

- TASKS: CCL-004, CCL-005, CCL-006
- PASS CONDITION: Media readiness and course assignment are separate, there is exactly one media ingest authority, worker never assigns cover, assignment accepts only `cover_media_id: <uuid>`, clear accepts only `cover_media_id: null`, omitted `cover_media_id` means no change, and `cover_media_id` set/clear is course structure authority only.

### Gate D: Cover Frontend/Legacy Gate

- TASKS: CCL-007, CCL-008, CCL-009
- PASS CONDITION: Mounted frontend uses the canonical flow, renders backend-provided cover only, and does not use `/api/media/cover-*` or inert cover methods.

### Gate E: Lesson Backend Gate

- TASK: CCL-011
- PASS CONDITION: Dedicated content read exists with body `{ lesson_id, content_markdown, media }` plus HTTP `ETag`, content write requires `If-Match`, stale writes fail without persistence, and structure endpoints remain content-free.

### Gate F: Lesson Frontend/Legacy Gate

- TASKS: CCL-012, CCL-013, CCL-014
- PASS CONDITION: Editor hydrates only from the content endpoint, stores the backend-issued content token, writes only with the current token, and cannot overwrite persisted content from failed hydration, stale state, or structure-list fallback.

### Gate G: Domain Test Gates

- TASKS: CCL-010, CCL-015, CCL-016
- PASS CONDITION: Cover and lesson-content tests assert canonical behavior and fail on duplicate authority paths.

### Gate H: Global Dominance Gate

- TASKS: CCL-017, CCL-018
- PASS CONDITION: Both domains pass together; exactly one authority path exists for media ingest, cover assignment, lesson content read, and lesson content write; no legacy active path, hidden fallback, inert cover method, worker assignment, frontend media resolver, content-in-structure hydration, or implicit empty-content persistence remains.

## 6. DAG VALIDATION

The graph is acyclic.

Roots:

- CCL-001
- CCL-002

Terminal node:

- CCL-018

No dependency points to a later undefined task.
No task depends on itself.
No task requires truth owned by a later task.

Critical ordering checks:

- contract authority precedes baseline decision: CCL-001, CCL-002 -> CCL-003
- baseline decision precedes backend mutation: CCL-003 -> CCL-004 and CCL-011
- media readiness precedes cover assignment: CCL-004, CCL-005 -> CCL-006
- cover assignment precedes cover frontend alignment: CCL-006 -> CCL-007
- cover frontend replacement precedes cover legacy removal: CCL-008 -> CCL-009
- lesson content read precedes frontend hydration rewrite: CCL-011 -> CCL-012 -> CCL-013
- frontend hydration rewrite precedes legacy content-in-structure cleanup: CCL-013 -> CCL-014
- domain test gates precede global dominance gates: CCL-010, CCL-016 -> CCL-017 -> CCL-018

## 7. STOP CONDITIONS FOR FUTURE EXECUTION

STOP if any of the following occurs during execution:

- a cover path assigns `app.courses.cover_media_id` outside course structure authority
- worker attempts to assign, replace, or clear course cover
- frontend constructs or resolves a cover URL outside backend `cover.resolved_url`
- `/api/media/cover-*` becomes an active positive cover authoring path
- media ingest or completion writes course structure
- cover assignment accepts `cover`, raw URL, storage path, non-image media, non-ready media, wrong-course media, wrong-teacher media, unscoped media, or frontend-only validation as authority
- structure endpoints expose `content_markdown`
- editor hydration reads `content_markdown` from lesson structure lists
- content write succeeds without a matching backend-issued `If-Match` token
- saving can overwrite persisted content after a failed or empty hydration fallback
- baseline substrate is missing and cannot be resolved inside CCL-003 without adding task IDs or changing the graph
- user-facing product copy touched in these domains is not Swedish
- operator prompts or task prompts cease to be English and copy-paste ready
