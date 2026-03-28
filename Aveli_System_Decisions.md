# Aveli System Decisions

## Product Context

- Aveli is a social learning platform with courses and lessons as the core runtime learning model, plus live lesson/session experiences and a marketplace for cultivated knowledge.
- Aveli is for teachers and learners, including course/lesson interactions, checkout/onboarding flows, session-level experiences, and guided app access.
- Teachers use Aveli to create, manage, publish, and refine learning experiences, media-rich course content, home-player tracks, and cultivated knowledge offers.
- Learners use Aveli to onboard, access the app through membership, access lesson content through enrollment or explicitly defined membership-included intro access, and progress through repeated learning experiences.
- The user actions explicitly represented in the approved product framing are:
  - onboard into the trusted teacher/learner journey
  - enter the app through valid membership access
  - learn via structured course/editor content
  - access course experiences through canonical course-access rules
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

## System Definition

- Aveli is the documented system for social learning, course/editor workflows, media delivery, checkout/onboarding support, membership-gated app access, enrollment-gated course access, home-player curation, and marketplace expansion with dedicated API governance, auth/security controls, and control-plane/observability surfaces.
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

## Canonical Language Rules

- `membership` is the canonical term for app-access authority.
- `enrollment` / `enrollments` is the canonical term for standard course-access authority.
- `subscription` is NOT a canonical Aveli runtime term.
  - It may appear only in legacy, migration, audit, or historical references.
- `module` is NOT a valid Aveli system term.
  - It is forbidden in runtime/domain language and may appear only in historical or legacy references.
- Terms that imply duplicate authority for app access or course access must not be introduced.

## Course Model (Canonical)

- course contains lessons directly
- lessons are ordered via position
- no module abstraction exists
- any module-like grouping is NOT valid system truth
- modules are not persisted, exposed, simulated, inferred, or tolerated as runtime/domain truth
- `module_id` is not part of the canonical course domain model
- remaining legacy module references in backend/frontend code or docs are implementation debt and must not be used to redefine system truth

## Operational Authorities

- Media authority model = `split_intent_and_playback`
- App-access authority = `memberships`
- Course-access authority = `enrollments`
- Standard course access must not be derived from membership alone
- Membership may grant explicit access to a defined introduction-course set without converting membership into the general course-access authority
- Playback authority = `runtime_media`
- Media intent authority = `control_plane`

## Access Model (Canonical)

- `membership` is required to pass landing and enter the app.
- `membership` is global platform access, not creator-scoped.
- `enrollments` is the only canonical authority for normal course access.
- Membership-included intro-course access is allowed only as an explicit, defined mapping.
- Membership-included intro-course access must NOT be implemented as implicit rule magic such as tag-based or inferred access.
- Checkout may canonically produce:
  - membership
  - enrollment
  - both
- Checkout outcome is product-dependent, not guessed from legacy terminology.

## Home Player Model (Canonical)

- Home player is part of the same media domain.
- Home player has:
  - its own upload pipeline
  - its own frontend management surface
  - teacher-controlled active/inactive curation
- Home player curation is controlled by `control_plane`.
- Home-player playback is still owned by `runtime_media`.
- Home player does not create a separate playback authority, alternate playback law, or separate media domain.
- Home player must not introduce special playback shortcuts, direct storage playback, or bypass paths around `runtime_media`.

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
- canonical course access
- home-player curation and playback compliance

## Canonical Media Resolution Path

- Resolution chain:
  - `lesson_content_markdown (lesson_media_id)`
  - `lesson_media`
  - `control_plane`
  - `storage.objects`
  - `runtime_media`
  - playback API
  - client
- `runtime_media` is the only playback authority.
- `storage.objects` is an external physical-storage dependency and is never a valid playback source.
- `control_plane` defines media intent, not playback.
- No layer may bypass `runtime_media`.
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
  - Scope intent: `planned_protected`
  - Canonical role: `media_intent_authority`
- Canonical decision:
  - control plane is preserved and protected
  - control plane must not be removed or semantically redefined
  - control plane does not own playback

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
- Media control plane: planned, protected, intent-authoritative
- Playback delivery: runtime-active via `runtime_media`
- Auth flow: planned constraints + runtime-audited behavior
- Home player ingest/curation: runtime-active within the same media domain
- Membership app access: runtime/canonical authority
- Enrollment course access: runtime/canonical authority

## Explicitly Forbidden Surfaces

- `subscription` as active runtime/domain authority
- `module` as runtime/domain construct
- duplicate app-access authorities parallel to `memberships`
- duplicate normal course-access authorities parallel to `enrollments`
- implicit course access by inferred tags or hidden rules
- direct playback from `storage.objects`
- alternate playback authorities outside `runtime_media`
- fallback to legacy paths when canonical resolution fails
- any endpoint or function that presents storage as business truth instead of dependency detail

## Preserved Decision Layer

- This file is the preserved semantic decision layer for rule interpretation, contradiction review, and deterministic cleanup of legacy surfaces.