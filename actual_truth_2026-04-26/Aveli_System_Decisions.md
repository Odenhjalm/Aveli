# Aveli_System_Decisions.md

## Product Context

- Aveli is a social learning platform with courses and lessons as the core runtime learning model, plus a marketplace where advanced users can sell cultivated knowledge.
- Aveli is for teachers and learners, including course/lesson interactions, checkout/onboarding flows, and session-level experiences.
- Teachers use Aveli to create, manage, publish, and refine learning experiences, media-rich course content, and cultivated knowledge offers.
- Learners use Aveli to onboard, access lesson content, complete guided learning paths, and purchase or subscribe to learning access.
- The user actions explicitly represented in the approved product framing are:
  - onboard into the trusted teacher/learner journey
  - learn via structured course/editor content
  - access purchased, subscribed, or enrolled lesson experiences
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

## Non-Negotiable Constraints

- Media is an EXPERIENCE, not a file.
  - Media routes, identifiers, and control points must remain aligned to user-facing media behavior.
- Auth is a RELATIONSHIP ENTRY, not a login endpoint.
  - Auth-related structure is not to be redesigned in this phase.
- API must reflect REAL system behavior, not hypothetical design.
  - Canonical API truth remains the audit catalog + usage-diff evidence.
- Planned features MUST NOT be removed during stabilization.
  - Planned and control-plane components are preserved unless explicitly canceled by a documented process outside this phase.

## System definition

- Aveli is the documented system for social learning, course/editor workflows, media delivery, checkout/onboarding support, and marketplace expansion with dedicated API governance, auth/security controls, and control-plane/observability surfaces.
- Evidence:
  - docs/README.md
  - docs/architecture/aveli_editor_architecture_v2.md
  - docs/verification_mcp.md
  - docs/WORKFLOW.md

## COURSE MODEL (CANONICAL)

- course contains lessons directly
- lessons ordered via position
- no module abstraction exists
- any module-like grouping is UI-only and optional
- modules are not persisted, exposed, simulated, or inferred as system truth
- `module_id` is not part of the canonical course domain model
- remaining legacy module references in backend/frontend code or docs are implementation debt and must not be used to redefine system truth

## OPERATIONAL AUTHORITIES

- Media authority model = `split_intent_and_playback`
- Course access authority = `enrollments`
- Subscription state authority = `memberships`
- Playback authority = `runtime_media`
- Media intent authority = `control_plane`

## EXTERNAL DEPENDENCIES

- `auth.users`
- `storage.objects`
- `storage.buckets`
- These remain external dependencies and are not baseline-owned schema.
- Local scratch verification may require a minimal local storage substrate when storage-backed workers are enabled.

## EXTERNAL ID INTEGRITY RULE

- Fields referencing external systems (for example `auth.users.id`) MUST NOT use database foreign key constraints.
- `user_id` is a soft reference to `auth.users(id)`.
- Validity is enforced at:
  - auth layer (token validation)
  - backend services (creation and mutation checks)
- Reads MUST be tolerant of missing external records and MUST NOT hard crash because an external record is absent.
- Database MUST NOT enforce foreign key constraints for external dependencies.

## LEGACY MIGRATION RULE

- Legacy tables remain only while their intended functionality is still needed by live systems.
- Once canonical authorities cover that functionality, legacy tables should migrate out rather than persist as competing truth sources.

## CURRENT RUNTIME / BASELINE FOCUS

- lesson editor
- lesson view
- Stripe checkout
- onboarding

## CANONICAL MEDIA RESOLUTION PATH

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
- Home player may have separate source/storage truth, but playback must still resolve through `runtime_media`.
- Home player must not introduce alternative playback paths.
- These rules are operational laws and do not elevate home player into a separate top-level system model.

## Source of truth per component

### 1) API definitions
- Selected option: **B**
- Chosen source of truth:
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json
  - docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md
  - docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md
- Classification:
  - API contract intent: `planned`
  - Runtime status: `runtime-audited` (uses catalog + diff as validation surface)
- Why this supports product intent:
  - B was chosen because API behavior must reflect real interactions between teachers and learners instead of hypothetical endpoint design.

### 2) Media control plane scope
- Selected option: **A**
- Chosen source of truth:
  - docs/media_control_plane_mcp.md
  - docs/media_architecture.md
- Classification:
  - Scope intent: `planned`
  - Runtime status: `planned`
  - Canonical role: `media_intent_authority`
- Why this supports product intent:
  - A was chosen because experience control and operational consistency are required for live/spiritual context and session quality, while present playback authority remains `runtime_media`.

### 3) Auth flow definition
- Selected option: **B** (with user constraint: evolve into UX-driven system)
- Chosen source of truth:
  - docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md
  - docs/SECURITY.md
- Classification:
  - Auth/security intent: `planned`
  - Runtime status: `planned`
- Why this supports product intent:
  - B was chosen because trust and user journey integrity must be preserved through documented security and audit baselines.

## Planned vs runtime classification (resolved)

- API definitions: `planned` + `runtime-audited`
- Media control plane: `planned` + `intent-authoritative`
- Playback delivery: `runtime-active` via `runtime_media`
- Auth flow: `planned` + `runtime-audited`

## Resolved conflicts

1. **API definition conflict**
   - Resolved to option B.
   - Canonical decision: audit catalog/diff files are the accepted API truth source for verification and mismatch tracking.

2. **Media control plane conflict**
   - Resolved to option A.
   - Canonical decision: control-plane responsibilities and interfaces are defined by MCP/control-plane docs as primary media intent, while runtime playback authority remains `runtime_media`.

3. **Auth flow conflict**
   - Resolved to option B with UX-driven evolution constraint.
   - Canonical decision: security and audit docs remain the governing baseline; UX-driven evolution proceeds within this baseline.

## Pending note

- This file is now the preserved decision layer for Phase 1 execution and is required as input for deterministic rule processing.
