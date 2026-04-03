# Aveli System Decisions

## Product Context

- Aveli is a social learning platform with courses and lessons as the core runtime learning model, plus live lesson/session experiences and a marketplace for cultivated knowledge.
- Aveli is for teachers and learners, including course/lesson interactions, checkout/onboarding flows, session-level experiences, and guided app access.
- Teachers use Aveli to create, manage, publish, and refine learning experiences, media-rich course content, home-player tracks, and cultivated knowledge offers.
- Learners use Aveli to onboard, access the app through membership, discover courses and lesson structure without course enrollment, access `lesson_content_surface` through explicit course enrollment and `current_unlock_position`, and progress through repeated learning experiences.
- The user actions explicitly represented in the approved product framing are:
  - onboard into the trusted teacher/learner journey
  - enter the app through valid membership access
  - learn via structured course/editor content
  - access course content through `canonical_protected_course_content_access`
  - access curated home-player experiences through the home-player pipeline
  - progress through repeated, persistent learning experiences
- Activities, posts, messages, and notifications remain future-facing surfaces unless current runtime evidence explicitly promotes them into baseline truth.
- The decisions in this file intentionally keep technical choices aligned to these usage intents.

## System Philosophy

- Aveli is:
  - relationship-driven (not content-first)
  - experience-driven (not file-driven)
  - progression-based (not static)
- The system should optimize user trust, continuity, and repeatable workflows before feature surface expansion.
- Stabilization tasks are allowed only when they preserve these three properties.
- Semantic precision is mandatory. Aveli must not rely on overlapping names for different authorities.

## Expansion Model (Canonical)

- New features must attach to the system via new canonical entities.
- Core domain entities must remain stable and represent only canonical domain truth.
- Feature logic must not be embedded into:
  - `courses`
  - `lessons`
  - `course_enrollments`
  - `media_assets`
  - `lesson_media`
- Feature expansion must happen via new entities such as `live_sessions`, `notifications`, or `marketplace_products`.
- Mutation of core domain entities to support new features is forbidden.

## Studio Core Boundary

- Studio core means only:
  - course metadata
  - lesson metadata
  - lesson content
- Studio core explicitly excludes:
  - lesson-media payloads
  - profile media
  - studio sessions
- Studio core must use canonical course and lesson contracts directly.
- Studio core must not depend on shared legacy `Course` models, raw maps, or legacy lesson aliases.

## Feature Contract Expansion Rules

- Non-core features must define explicit canonical contracts before they are treated as stable runtime truth.
- Profile media is a separate feature domain and must use an explicit structured contract.
- Profile media must not use metadata blobs, map-based identity, or fallback fields as runtime truth.
- Studio sessions are a separate feature domain and must use a single canonical contract.
- Studio sessions must not use fallback/default values to hide missing data.
- Invalid non-core feature input must be rejected explicitly rather than normalized silently.
- Landing and other external consumers must consume typed contracts.
- Landing must not consume studio raw data or `Map<String, dynamic>` as runtime truth.

## Transition Layer Philosophy

- A transition layer exists only when canonical backend truth and active consumers still mismatch.
- A transition layer is allowed only as an explicit, temporary, scoped layer above canonical truth.
- A transition layer must define:
  - producer shape
  - consumer expectation
  - explicit mapping
  - removal condition
- A transition layer must never:
  - introduce fallback
  - hide missing data
  - silently correct invalid input or output
  - preserve legacy aliases as runtime truth
  - redefine canonical field names
- Transition layers are migration mechanisms, not semantic truth.

## Non-Negotiable Constraints

- Media is an EXPERIENCE, not a file.
  - Media routes, identifiers, and control points must remain aligned to user-facing media behavior.
- Auth is a RELATIONSHIP ENTRY, not a login endpoint.
  - Auth-related structure is not to be redesigned in this phase.
- API must reflect REAL system behavior, not hypothetical design.
  - Canonical API truth remains the audit catalog + usage-diff evidence, but audit evidence describes observed reality and does not itself legitimize legacy behavior.
- Planned features MUST NOT be removed during stabilization.
  - Planned and control-plane components are preserved unless explicitly canceled by a documented process outside this phase.
- Legacy behavior MUST NOT survive through fallback.
  - If canonical replacement exists, legacy must be removed rather than silently tolerated.
- Legacy removal requires a clear replacement.
  - No legacy endpoint, authority, or shortcut may be deleted unless a canonical replacement path is explicitly defined.
- Map-based contracts and metadata blobs must not become semantic truth.
- Default values must not hide missing required data.
- Implicit parsing and silent correction are forbidden.

## System Definition

- Aveli is the documented system for social learning, course/editor workflows, media delivery, checkout/onboarding support, membership-gated app access, course catalog and lesson structure exposed via explicit read surface, course content accessible through defined API surface only when `course_enrollments` AND `lesson.position <= current_unlock_position`, home-player curation, and marketplace expansion with dedicated API governance, auth/security controls, and control-plane/observability surfaces.
- Evidence:
  - docs/README.md
  - docs/architecture/aveli_editor_architecture_v2.md
  - docs/verification_mcp.md
  - docs/WORKFLOW.md

## Governance Model

- `Aveli_System_Decisions.md` is the semantic truth layer.
- `aveli_system_manifest.json` is the execution-rule layer.
- If the two documents must be interpreted together:
  - semantic meaning is governed by decisions
  - execution and enforcement policy is governed by manifest
- API audit artifacts describe observed runtime reality and are used for verification and mismatch tracking.
- Observed runtime reality does NOT automatically become canonical truth.

## Baseline Truth Rule

- `backend/supabase/baseline_slots` is the canonical baseline source of truth.
- Historical baseline slots and legacy DB state are reference-only inputs and MUST NOT redefine canonical media authority.

## Canonical Language Rules

- `membership` is the canonical term for app-access authority.
- `course_enrollment` / `course_enrollments` is the canonical term for `canonical_protected_course_content_access` authority.
- Canonical data categories are:
  - `course_identity`
  - `course_display`
  - `course_grouping`
  - `course_pricing`
  - `lesson_identity`
  - `lesson_structure`
  - `lesson_content`
  - `lesson_media`
- Category definitions are semantic law, not fixed field lists. Future fields must map into these categories without changing surface rules.
- `course_discovery_surface` is the canonical term for a surface that allows only `course_identity`, `course_display`, `course_grouping`, and `course_pricing`.
- `lesson_structure_surface` is the canonical term for a surface that allows only `lesson_identity` and `lesson_structure`.
- `lesson_content_surface` is the canonical term for a surface that allows only `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`, and requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
- For learner/public surfaces, `lesson_media` exists only inside `lesson_content_surface`.
- No independent lesson-media surface exists for learner/public surfaces.
- Studio authoring may manage `lesson_media` as authored placement, but it must not introduce a second media-resolution or frontend-representation authority.
- `media_assets` never defines access.
- No rule referring to visibility may be interpreted as permission for raw table access.
- `subscription` is NOT a canonical Aveli runtime term.
  - It may appear only in legacy, migration, audit, or historical references.
- `module` is NOT a valid Aveli system term.
  - It is forbidden in runtime/domain language and may appear only in historical or legacy references.
- Terms that imply duplicate authority for app access or `canonical_protected_course_content_access` must not be introduced.

## Course Model (Canonical)

- course contains lessons directly
- `course.step` is the only canonical progression field
- `course.course_group_id` is the only canonical grouping field
- `course.drip_enabled` and `course.drip_interval_days` are the only canonical drip-configuration fields
- `course.course_group_id` represents a progression set of courses
- courses within the same `course_group_id` belong to the same product progression
- progression within a `course_group_id` is strictly ordered by `course.step`
- `course.course_group_id` is used only for progression linkage and UI sequencing
- `course.course_group_id` must not be used for categories, tags, or arbitrary grouping
- drip behavior is course-level configuration only and must not be inferred from course type or enrollment source
- lessons are ordered via position
- `lesson.lesson_title` is the canonical lesson display name
- lesson runtime alias `title` is forbidden
- `lessons` stores lesson identity and structure only
- `lesson_contents` stores lesson body content only
- `content_markdown` is canonical only on `lesson_contents`
- no module abstraction exists
- any module-like grouping is NOT valid system truth
- explicit course grouping via `course_group_id` is valid system truth
- modules are not persisted, exposed, simulated, inferred, or tolerated as runtime/domain truth
- `module_id` is not part of the canonical course domain model
- remaining legacy module references in backend/frontend code or docs are implementation debt and must not be used to redefine system truth

## Operational Authorities

- Media authority model = `identity_runtime_truth_and_backend_representation`
- App-access authority = `memberships`
- Canonical course-content access authority = `course_enrollments`
- Execution authority = `worker`
- `course_discovery_surface` exposure is not governed by `course_enrollments`
- `lesson_structure_surface` exposure is not governed by `course_enrollments`
- `lesson_content_surface` access must not be derived from membership alone
- Media identity authority = `app.media_assets`
- Media authored-placement authority = `app.lesson_media`
- Runtime truth authority = `runtime_media`
- Frontend representation authority = `backend_read_composition`
- Media intent authority = `control_plane`
- Media lifecycle observability authority = `control_plane`
- Shape authority = `database`

## Canonical Media Model

- `app.media_assets` is media identity.
- `app.lesson_media` is authored placement.
- `app.runtime_media` is the runtime truth layer for media state and resolution eligibility.
- `runtime_media` is NOT the final frontend representation.
- The backend read composition layer constructs the frontend-facing media object only as `media = { media_id, state, resolved_url } | null`.

runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.

## Media Control Plane Authority

- `control_plane` is the only authority for:
  - media intent
  - pipeline expectations
  - lifecycle interpretation
- `control_plane` lifecycle observability classifications are:
  - `valid` when canonical media state can produce deterministic `runtime_media` truth and the read layer can emit the canonical media object without fallback
  - `broken` when canonical media state should resolve but runtime truth cannot produce the canonical media object
  - `stuck` when `state = processing` with no progress
  - `invalid` when canonical format or identity rules are violated
- Lifecycle classification must be derived from existing canonical state only.
- Lifecycle classification must not introduce additional state fields.
- Lifecycle classification must not depend on runtime or frontend logic.
- `control_plane` does NOT:
  - execute media processing
  - mutate media state
  - perform runtime-media resolution
  - construct frontend media representation
  - perform media delivery
  - enforce DB constraints
- Worker is the only execution authority.
- Worker owns media transformations and canonical state transitions only through the canonical worker function.
- Worker does NOT define media intent, runtime truth, or frontend representation rules.
- `runtime_media` is the only runtime truth layer for governed media surfaces.
- Runtime owns media state and resolution eligibility only and may reject invalid runtime state.
- Runtime does NOT define frontend representation, validate pipeline rules outside canonical state, access ingest identity as public truth, or perform transformation.
- Database is the only shape authority.
- Database enforces schema shape and invariants only.
- Database does NOT define behavior or infer meaning.

## Access Model (Canonical)

- `membership` is required to pass landing and enter the app.
- `membership` is global platform access, not creator-scoped.
- `course_discovery_surface` is separate from `lesson_content_surface`.
- `course_discovery_surface` allows only:
  - `course_identity`
  - `course_display`
  - `course_grouping`
  - `course_pricing`
- Forbidden categories must never appear on `course_discovery_surface`:
  - `lesson_content`
  - `lesson_media`
  - `enrollment_state`
  - `unlock_state`
- `lesson_structure_surface` allows only:
  - `lesson_identity`
  - `lesson_structure`
- `lesson_structure_surface` maps to `lessons` only.
- Forbidden categories must never appear on `lesson_structure_surface`:
  - `lesson_content`
  - `lesson_media`
  - `enrollment_state`
  - `unlock_state`
- `course_enrollments` is the only canonical authority for `canonical_protected_course_content_access`.
- `canonical_protected_course_content_access` means a lesson is accessible if and only if:
  - a `course_enrollments` row exists for `(user_id, course_id)`
  - `lesson.position <= current_unlock_position`
- `current_unlock_position` is stored on `course_enrollments`.
- `lesson_content_surface` allows only `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`.
- `lesson_content_surface` maps to `lessons` + `lesson_contents` + `lesson_media`.
- For learner/public surfaces, `lesson_media` exists only inside `lesson_content_surface`.
- Intro courses require `course_enrollments` rows with `source = intro_enrollment`, and `lesson_content_surface` still requires `lesson.position <= current_unlock_position`.
- No lesson content or lesson media access exists outside `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `media_assets` never defines access.
- No rule referring to visibility may be interpreted as permission for raw table access.
- Checkout may canonically produce:
  - membership
  - course_enrollment
  - both
- Checkout outcome is product-dependent, not guessed from legacy terminology.

## API Read Contract (Canonical)

- `GET /courses` is `course_discovery_surface`.
- `GET /courses/{course_id}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface` and must not require enrollment.
- `GET /courses/by-slug/{slug}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface` and must not require enrollment.
- Course-detail endpoints may return lessons only as `LessonSummary[]` on `lesson_structure_surface`.
- `LessonSummary` is the `lesson_structure_surface` shape and allows only:
  - `lesson_identity`
  - `lesson_structure`
- `LessonSummary` is sourced from `lessons` only.
- Forbidden categories must never appear in `LessonSummary`:
  - `lesson_content`
  - `lesson_media`
  - `enrollment_state`
  - `unlock_state`
- `GET /courses/lessons/{lesson_id}` is `lesson_content_surface`.
- `LessonContent` is the `lesson_content_surface` shape and allows only:
  - `lesson_identity`
  - `lesson_structure`
  - `lesson_content`
  - `lesson_media`
- `LessonContent` is sourced from canonical `lessons` + `lesson_contents` + `lesson_media`.
- `LessonContent` requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `lesson_media` exists only inside `LessonContent`.
- No endpoint may return `lesson_content` or `lesson_media` without `course_enrollments` AND `lesson.position <= current_unlock_position`.
- No rule referring to visibility may be interpreted as permission for raw table access.
- `app.lessons` must remain structure-only and `app.lesson_contents` must remain content-only.
- `app.lessons` and `app.lesson_contents` must not be collapsed into one raw-table lesson access surface that bypasses canonical surface boundaries.

## Contract Consumption Rules

- Runtime contracts must be typed and explicit.
- `Map<String, dynamic>` must not be used as runtime truth.
- Metadata blobs must not act as identity, authority, or compatibility contract surfaces.
- Landing must consume typed contracts rather than studio raw payloads.
- Lesson naming law is global:
  - `lesson_title` is canonical everywhere
  - `title` is forbidden as a runtime lesson alias

## Drip Model (Canonical)

- Drip is a course-level configuration.
- Drip is not tied to enrollment source.
- Teacher controls:
  - `drip_enabled`
  - `drip_interval_days`
- `course_enrollments` is the only source of `canonical_protected_course_content_access` truth.
- Intro courses require explicit enrollment with `source = intro_enrollment`, and `lesson_content_surface` access still requires `lesson.position <= current_unlock_position`.
- Paid courses require explicit enrollment with `source = purchase`, and `lesson_content_surface` access still requires `lesson.position <= current_unlock_position`.
- Enrollment stores state only.
- Enrollment always stores `drip_started_at` and `current_unlock_position`.
- Enrollment source records access origin and does not define drip behavior.
- The system must not assume default drip behavior.
- The system must not infer drip from course type.
- Drip progression is stored state, not derived state.
- On creation of any enrollment, `drip_started_at = granted_at`.
- On creation of an enrollment for a course with `drip_enabled = true`:
  - if the course has at least one lesson, `current_unlock_position = 1`
  - if the course has zero lessons, `current_unlock_position = 0`
- On creation of an enrollment for a course with `drip_enabled = false`:
  - if the course has at least one lesson, `current_unlock_position = max_lesson_position`
  - if the course has zero lessons, `current_unlock_position = 0`
- Drip progression is advanced only by a worker process.
- The worker runs on a fixed cron-based interval.
- The worker evaluates enrollments only for courses where `drip_enabled = true`.
- Worker-based scheduling is the canonical way to advance drip progression.
- No lazy evaluation of unlock state is allowed in runtime.
- Runtime requests must never advance drip state.
- Frontend must never compute unlock state.
- UI must reflect drip configuration consistently in course cards and course views.
- `lesson.position` is the canonical progression index.
- `current_unlock_position` is the canonical persisted highest accessible `lesson.position`.
- Worker progression updates are determined by:
  - `drip_started_at`
  - `lesson.position`
  - `course.drip_interval_days`
- Canonical worker formula:
  - `unlocked_count = 1 + floor((now - drip_started_at) / (course.drip_interval_days days))`
  - `computed_unlock_position = min(max_lesson_position, unlocked_count)`
- `current_unlock_position` must never exceed the highest existing `lesson.position` in the course.
- If `current_unlock_position` already equals `max_lesson_position`, worker execution must be a no-op.
- Worker runs must be deterministic.
- Repeated worker executions in the same cron window must produce the same persisted result.
- Worker may only update when `computed_unlock_position > current_unlock_position`.
- Worker must never decrease `current_unlock_position`.

## Canonical Media Processing Mode

- All audio must pass the worker pipeline.
- WAV must become MP3 before `ready`.
- Audio `ready` requires `media_assets.playback_format = mp3`.
- No direct `ready` writes are allowed for audio.
- Canonical worker mutation authority for media readiness is a single security-definer function.
- Media readiness mutation must occur only through the canonical worker function.
- The canonical worker function is the only allowed mutation boundary for audio state transitions that lead to `media_assets.state = ready`.
- The canonical worker function assigns `media_assets.playback_format = mp3` during canonical audio processing.
- Direct `UPDATE` to `media_assets.state = ready` is forbidden.
- No API path, migration path, trigger path, or ad-hoc SQL path may mark audio `ready` outside the canonical worker function.
- There is no alternate media-readiness mutation path.

## Home Player Model (Canonical)

- Home player is part of the same media domain.
- Home player has:
  - its own upload pipeline
  - its own frontend management surface
  - teacher-controlled active/inactive curation
- Home player curation is controlled by `control_plane`.
- Home-player runtime truth is still owned by `runtime_media`.
- Home player does not create a separate media authority, alternate resolver, or separate media domain.
- Home player must not introduce special-case frontend representation, direct storage delivery, or bypass paths around `runtime_media` and backend read composition.

## External Dependencies

- `auth.users`
- `storage.objects`
- `storage.buckets`
- These remain external dependencies and are not baseline-owned schema.
- Local scratch verification may require a minimal local storage substrate when storage-backed workers are enabled.

## External ID Integrity Rule

- Fields referencing external systems (for example `auth.users.id`) MUST NOT use database foreign key constraints.
- `user_id` is a soft reference to `auth.users(id)`.
- Validity is enforced at:
  - auth layer (token validation)
  - backend services (creation and mutation checks)
- Reads MUST be tolerant of missing external records and MUST NOT hard crash because an external record is absent.
- Database MUST NOT enforce foreign key constraints for external dependencies.

## Legacy Migration Rule

- Legacy tables, endpoints, and compatibility behaviors remain only while their intended functionality is still needed by live systems.
- Once canonical authorities cover that functionality, legacy must migrate out rather than persist as competing truth.
- Legacy must not survive through fallback behavior.
- Legacy removal must proceed in this order:
  - canonical replacement exists
  - legacy surface is identified and marked
  - legacy surface is blocked and/or logged where appropriate
  - legacy surface is removed

## Current Runtime / Baseline Focus

- lesson editor
- lesson view
- Stripe checkout
- onboarding
- membership-gated app entry
- canonical_protected_course_content_access
- home-player curation and unified media-authority compliance

## Canonical Media Resolution Path

- Resolution chain:
  - canonical media identity and attachment pointers
  - `control_plane`
  - `runtime_media`
  - backend read composition layer
  - API response
  - frontend render
- `app.media_assets` defines media identity.
- `app.lesson_media` defines authored placement.
- `app.runtime_media` defines runtime truth for state and resolution eligibility.
- `runtime_media` is not the final frontend representation.

runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.
- `storage.objects` is an external physical-storage dependency and is never a valid media authority or delivery source.
- `control_plane` defines media intent and lifecycle interpretation, not execution, runtime truth, or frontend representation.
- No layer may bypass `runtime_media`.
- No layer may bypass backend read composition when constructing frontend-facing media.
- All lesson/content media references must use `lesson_media_id` only.
- Fallback is forbidden.
  - If canonical media resolution fails, the system must fail explicitly rather than route through legacy or storage shortcuts.

## Source of Truth Per Component

### 1) API definitions
- Chosen source of truth:
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md
  - docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md
- Classification:
  - API verification source: `runtime-observed`
  - Canonical legitimacy: `separate_from_observation`
- Canonical decision:
  - audit artifacts describe what exists and how it behaves
  - audit artifacts do not automatically justify keeping legacy endpoints or duplicate authorities

### 2) Media control plane scope
- Chosen source of truth:
  - docs/media_control_plane_mcp.md
  - docs/media_architecture.md
- Classification:
  - Scope intent: `planned_preserved`
  - Canonical roles: `media_intent_authority`, `media_lifecycle_observability_authority`
- Canonical decision:
  - control plane is preserved and not open to semantic redefinition
  - control plane must not be removed or semantically redefined
  - control plane does not own execution, runtime truth, or frontend representation

### 3) Auth flow definition
- Chosen source of truth:
  - docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md
  - docs/SECURITY.md
- Classification:
  - Auth/security intent: `planned`
  - Runtime status: `runtime-audited`
- Canonical decision:
  - security and audit docs remain the governing baseline for auth constraints
  - UX-driven evolution must not redesign the structural trust boundary in this phase

## Planned vs Runtime Classification (Resolved)

- API definitions: observed via audit, verified separately from legitimacy
- Media control plane: planned, preserved, intent-authoritative
- Media runtime truth: runtime-active via `runtime_media`
- Media representation to frontend: runtime-active via backend read composition
- Auth flow: planned constraints + runtime-audited behavior
- Home player ingest/curation: runtime-active within the same media domain
- Membership app access: runtime/canonical authority
- `course_discovery_surface`: canonical surface type
- `lesson_structure_surface`: canonical surface type
- `lesson_content_surface`: canonical surface type
- `canonical_protected_course_content_access`: runtime/canonical authority

## Explicitly Forbidden Surfaces

- `subscription` as active runtime/domain authority
- `module` as runtime/domain construct
- duplicate app-access authorities parallel to `memberships`
- duplicate `canonical_protected_course_content_access` authorities parallel to `course_enrollments`
- implicit intro access
- treating `course_discovery_surface` as enrollment-gated
- hiding course catalog behind enrollment
- treating `lesson_structure_surface` as `lesson_content_surface`
- conflating `course_discovery_surface` or `lesson_structure_surface` with `lesson_content_surface`
- exposing `lesson_content` or `lesson_media` on `lesson_structure_surface`
- returning `lesson_content_surface` data from course-detail endpoints
- treating any rule that does not require `course_enrollments` AND `lesson.position <= current_unlock_position` as sufficient authority for `lesson_content_surface`
- entitlement fallback paths
- step-based ownership logic
- runtime-derived progression
- runtime-derived unlock state
- drip logic tied to `intro_enrollment` vs `purchase`
- hardcoded drip defaults
- fallback drip behavior
- implicit unlock strategies
- inferred drip behavior from course type
- implicit `lesson_content_surface` access by inferred tags or hidden rules
- direct media delivery from `storage.objects`
- alternate media authorities outside `runtime_media`
- alternate frontend-representation authorities outside backend read composition
- cover-specific resolver ownership
- frontend media construction or resolution
- fallback to legacy paths when canonical resolution fails
- any endpoint or function that presents storage as business truth instead of dependency detail

## Preserved Decision Layer

- This file is the preserved semantic decision layer for rule interpretation, contradiction review, and deterministic cleanup of legacy surfaces.
