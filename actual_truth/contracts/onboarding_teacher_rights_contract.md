# Onboarding and Teacher Rights Authority Contract

## 1. Authority Statement

This file is the PRIMARY AUTHORITY for:

- `onboarding_state`
- `role`
- `role_v2`
- `is_admin`
- teacher-rights ownership
- teacher-rights mutation rules

For these domains, every other source is non-primary.

- `codex/AVELI_EXECUTION_POLICY.md` is a policy constraint source.
- `Aveli_System_Decisions.md` is a semantic framing source.
- `aveli_system_manifest.json` is an execution-governance source.
- `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md` is OBSERVATIONAL evidence.
- `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md` is OBSERVATIONAL evidence.

If any non-primary source disagrees with this file on these domains, this file wins.

## 2. Canonical Fields

### `onboarding_state`

`onboarding_state` is the canonical onboarding field.

Allowed values:

- `incomplete`: canonical onboarding is not complete.
- `completed`: canonical onboarding is complete.

Rules:

- `onboarding_state` is required.
- No implicit default exists at runtime.
- Any value outside this enum is invalid.

### `role_v2`

`role_v2` is the canonical runtime role field.

Allowed values:

- `learner`: non-teacher learning role.
- `teacher`: approved teacher role.

Rules:

- `role_v2` is required.
- `role_v2` owns role truth.
- Any value outside this enum is invalid.

### `role`

`role` is the legacy fallback role field.

Allowed values:

- `learner`: legacy fallback for the non-teacher learning role.
- `teacher`: legacy fallback for the approved teacher role.

Rules:

- `role` is required for compatibility.
- `role` does not own role truth.
- `role` is consulted only when `role_v2` is missing or invalid.
- Any value outside this enum is invalid.

### `is_admin`

`is_admin` is the canonical admin override field.

Allowed values:

- `false`: no admin override is active.
- `true`: admin override is active.

Rules:

- `is_admin` is required.
- `is_admin` is not a role enum.
- `is_admin` does not change the semantic value of `role_v2`.

### Precedence Rules

Role evaluation follows this order:

1. `is_admin` determines admin authority.
2. `role_v2` determines canonical non-admin role authority.
3. `role` is used only when `role_v2` is missing or invalid.
4. If both `role_v2` and `role` are missing or invalid, role evaluation is invalid and privileged access is denied.

Teacher-rights evaluation follows this rule:

- Teacher rights exist only when the effective non-admin role is `teacher`.
- `is_admin = true` does not create teacher rights.

## 3. Ownership Rules

### `onboarding_state`

- `onboarding_state` belongs to the subject user's canonical onboarding lifecycle.
- The subject user owns progression of the subject user's own onboarding lifecycle through the canonical onboarding process.
- The system may persist the result of a valid onboarding progression.

### `role_v2`

- `role_v2` belongs to system-governed role authority.
- The subject user does not self-assign `role_v2`.
- Teacher rights are canonically represented by `role_v2 = teacher`.

### `role`

- `role` belongs to compatibility support only.
- `role` does not override `role_v2`.

### `is_admin`

- `is_admin` belongs to admin-governed override authority.
- The subject user does not self-assign `is_admin`.

## 4. Mutation Authority

### Onboarding Progression

Canonical onboarding progression uses `onboarding_state`.

Allowed transitions:

- `incomplete -> completed`: allowed for the subject user through the canonical onboarding process, or for the system when recording a valid completion for that subject user.
- `completed -> completed`: allowed as an idempotent write.

Forbidden transitions:

- `completed -> incomplete`
- any transition from an invalid value
- any transition to an invalid value
- any mutation of another user's onboarding state by a non-admin user

### Role Assignment

Canonical role assignment uses `role_v2`.

Allowed transitions:

- `learner -> teacher`: allowed only through canonical admin teacher approval.
- `learner -> learner`: allowed as a no-op.
- `teacher -> teacher`: allowed as a no-op.

Forbidden transitions:

- `teacher -> learner`
- any user-initiated self-assignment to `teacher`
- any mutation to an invalid role value
- any direct legacy-role mutation that conflicts with canonical `role_v2`

### Teacher Approval Path

Teacher approval is the only canonical path that grants teacher rights.

Rules:

- Approval authority is admin authority.
- Approval grants teacher rights by setting canonical role authority to `teacher`.
- Rejection does not grant teacher rights.
- Rejection preserves the non-teacher role state.
- Teacher rights are not granted by onboarding completion alone.
- Teacher rights are not granted by `is_admin` alone.

### Admin Override Mutation

Canonical admin override uses `is_admin`.

Allowed transitions:

- `false -> true`: allowed only by admin-governed authority.
- `true -> false`: allowed only by admin-governed authority.
- `false -> false`: allowed as a no-op.
- `true -> true`: allowed as a no-op.

Forbidden transitions:

- any subject-user self-assignment of `is_admin`
- any non-admin mutation of another user's `is_admin`

## 5. Runtime Read Rules

### Effective Role Read

Runtime reads role authority in this order:

1. Validate `role_v2`.
2. Use valid `role_v2` when present.
3. If `role_v2` is missing or invalid, validate `role`.
4. Use valid `role` only as legacy fallback.
5. If no valid role exists, deny privileged role-based access.

### Onboarding Gate Read

Runtime reads onboarding completion from `onboarding_state`.

Rules:

- `completed` is the only onboarding-complete state.
- `incomplete` is not onboarding-complete.
- invalid `onboarding_state` is an invalid runtime condition.
- invalid `onboarding_state` must not be normalized silently.
- `onboarding_state` does not replace membership authority for app entry.

### Teacher-Rights Read

Runtime reads teacher rights from effective role authority.

Rules:

- Effective teacher rights exist only for effective role `teacher`.
- Teacher-scoped runtime behavior requires teacher rights.
- Admin authority and teacher rights are separate authorities.
- A subject may hold both admin authority and teacher rights at the same time.

## 6. Conflict Resolution Rules

### `role` and `role_v2` Disagree

- `role_v2` wins.
- `role` does not suppress or elevate `role_v2`.
- A disagreement is compatibility drift, not a second source of truth.

### `onboarding_state` Is Invalid

- Runtime treats the onboarding state as invalid.
- Runtime does not invent a fallback onboarding value.
- Onboarding-gated access remains blocked until the state is valid.

### `is_admin` Conflicts With `role_v2`

- `is_admin = true` grants admin authority.
- `is_admin = true` does not convert `learner` into `teacher`.
- `role_v2 = teacher` grants teacher rights even when `is_admin = false`.
- `role_v2 = teacher` and `is_admin = true` means both authorities are active.

## 7. Non-Goals / Out of Scope

This contract does not define:

- route definitions
- endpoint definitions
- database schema
- storage schema
- API implementation
- UI behavior
- membership authority
- external provider onboarding state

