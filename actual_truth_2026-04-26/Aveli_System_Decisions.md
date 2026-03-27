# Aveli_System_Decisions.md

## Product Context

- Aveli is documented as a production-oriented product platform that combines education experience features, media delivery, and creator workflows into an integrated system, not as a simple content repository.
- Aveli is for teachers and learners, including course/lesson interactions and session-level experiences.
- Teachers use Aveli to create, manage, publish, and refine learning experiences and media-rich course content.
- Learners use Aveli to attend live sessions, learn, connect with the course community, and progress through guided paths.
- The user actions explicitly represented in the documented product framing are:
  - attend live sessions
  - learn via structured course/editor content
  - connect through platform social/communication flows
  - grow through repeated, persistent engagement and completion-oriented experience.
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

- Aveli is the documented system for media/course/editor workflows with dedicated API governance, auth/security controls, and control-plane/observability surfaces.
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
- Why this supports product intent:
  - A was chosen because experience control and operational consistency are required for live/spiritual context and session quality.

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
- Media control plane: `planned`
- Auth flow: `planned` + `runtime-audited`

## Resolved conflicts

1. **API definition conflict**
   - Resolved to option B.
   - Canonical decision: audit catalog/diff files are the accepted API truth source for verification and mismatch tracking.

2. **Media control plane conflict**
   - Resolved to option A.
   - Canonical decision: control-plane responsibilities and interfaces are defined by MCP/control-plane docs as primary intent.

3. **Auth flow conflict**
   - Resolved to option B with UX-driven evolution constraint.
   - Canonical decision: security and audit docs remain the governing baseline; UX-driven evolution proceeds within this baseline.

## Pending note

- This file is now the preserved decision layer for Phase 1 execution and is required as input for deterministic rule processing.
