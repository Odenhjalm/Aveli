# Onboarding and Teacher Rights Authority Contract

## STATUS

ACTIVE

This file is the PRIMARY AUTHORITY for:

- `onboarding_state`
- `role_v2`
- `role`
- `is_admin`
- teacher-rights ownership
- teacher-rights mutation rules
- admin-bootstrap authority boundaries

`app.auth_subjects` is the canonical application subject authority for this
file's owned fields.

This file owns field authority and mutation authority only. It does not own
post-auth entry authority, full entry composition, or routing authority.

This contract composes with:

- `onboarding_entry_authority_contract.md`
- `auth_onboarding_contract.md`
- `auth_onboarding_baseline_contract.md`

## 1. CANONICAL FIELDS

### `onboarding_state`

Allowed values:

- `incomplete`
- `completed`

Rules:

- `onboarding_state` is required.
- `completed` is the only onboarding-complete state.
- Any value outside this enum is invalid.

### `role_v2`

Allowed values:

- `learner`
- `teacher`

Rules:

- `role_v2` is required.
- `role_v2` is the only canonical non-admin role truth.
- Any value outside this enum is invalid.

### `role`

Allowed values:

- `learner`
- `teacher`

Rules:

- `role` is required for compatibility.
- `role` is a mirror only.
- `role` MUST equal `role_v2` on every valid row.
- `role` never owns role truth.
- A mismatch between `role` and `role_v2` is compatibility drift.

### `is_admin`

Allowed values:

- `false`
- `true`

Rules:

- `is_admin` is required.
- `is_admin` grants admin authority only.
- `is_admin` does not create teacher rights.

## 2. READ AUTHORITY

Authority evaluation follows this order:

1. `is_admin` determines admin authority.
2. `role_v2` determines non-admin role truth.
3. `role` may be observed only as a compatibility mirror.

Rules:

- Teacher rights exist only when `role_v2 = teacher`.
- `is_admin = true` does not convert `learner` into `teacher`.
- `role` MUST NOT be used as runtime fallback when `role_v2` is missing or invalid.
- If `role_v2` is missing or invalid, privileged non-admin role access is denied.
- These fields may be exposed through `GET /entry-state` only as defined by
  `onboarding_entry_authority_contract.md`.
- Teacher-rights fields alone MUST NOT grant app entry or determine post-auth routing.

## 3. OWNERSHIP RULES

### `onboarding_state`

- `onboarding_state` belongs to the subject user's lifecycle in `app.auth_subjects`.
- The subject user may progress only the subject user's own onboarding state.
- Progression is allowed only through the canonical onboarding-completion route.

### `role_v2`

- `role_v2` belongs to admin-governed teacher-role authority.
- The subject user does not self-assign teacher rights.

### `role`

- `role` belongs to compatibility support only.
- `role` must be maintained in sync with `role_v2`.

### `is_admin`

- `is_admin` belongs to operator-controlled admin authority.
- The subject user does not self-assign `is_admin`.
- App-runtime routes do not own `is_admin` mutation.

## 4. MUTATION AUTHORITY

### Onboarding Completion

Canonical route:

- `POST /auth/onboarding/complete`

Allowed transitions:

- `incomplete -> completed`
- `completed -> completed`

Rules:

- Completion is explicit-action-derived only.
- `PATCH /profiles/me` MUST NOT mutate `onboarding_state`.
- Email verification, referral transport, membership state, webhooks, and profile writes MUST NOT mutate `onboarding_state`.
- `completed -> incomplete` is forbidden.
- The completion route does not issue tokens.
- After success, the subject user must refresh auth context through `POST /auth/refresh`.

### Teacher Role Grant

Canonical route:

- `POST /admin/users/{user_id}/grant-teacher-role`

Allowed transitions:

- `learner -> teacher`
- `teacher -> teacher`

Rules:

- Grant authority is admin-only.
- Grant MUST write canonical truth to `role_v2`.
- Grant MUST mirror the same value to `role`.
- Grant MUST record `teacher_role_granted` in `app.auth_events`.
- Grant MUST revoke the target user's refresh tokens.
- Grant MUST NOT introduce pending or request state.

### Teacher Role Revoke

Canonical route:

- `POST /admin/users/{user_id}/revoke-teacher-role`

Allowed transitions:

- `teacher -> learner`
- `learner -> learner`

Rules:

- Revoke authority is admin-only.
- Revoke MUST write canonical truth to `role_v2`.
- Revoke MUST mirror the same value to `role`.
- Revoke MUST record `teacher_role_revoked` in `app.auth_events`.
- Revoke MUST revoke the target user's refresh tokens.
- Revoke MUST NOT introduce pending or request state.

### Admin Bootstrap

Canonical mutation authority:

- operator-controlled `app.bootstrap_first_admin(target_user_id uuid)`

Rules:

- The first admin is established only through the one-time bootstrap in the baseline contract.
- No app-runtime route exists for mutating `is_admin`.
- Tests, seeds, frontend flows, and legacy routes MUST NOT create admin authority.

## 5. EXPLICIT ELIMINATIONS

- No teacher-request lifecycle exists.
- No pending teacher state exists.
- No request queue exists.
- No certificate-approval model exists as teacher-role authority.
- No profile-derived teacher-role authority exists.

## 6. AUDIT EVENT REQUIREMENTS

The following event types are required:

- `admin_bootstrap_consumed`
- `onboarding_completed`
- `teacher_role_granted`
- `teacher_role_revoked`

Rules:

- Auth events are canonical audit evidence, not authority.
- Missing required auth events is implementation drift.

## 7. CONFLICT RULES

### `role_v2` and `role` Disagree

- `role_v2` wins.
- The disagreement is compatibility drift.
- Runtime MUST NOT fall back from invalid `role_v2` to `role`.

### `is_admin` and `role_v2` Both Active

- Both authorities are active.
- Admin authority remains separate from teacher rights.

### `onboarding_state` Is Invalid

- Runtime treats the state as invalid.
- Runtime MUST NOT invent a fallback onboarding value.

## 8. NON-GOALS

This contract does not define:

- post-auth entry authority
- full entry composition
- routing authority
- password-reset semantics
- referral redemption semantics
- profile projection response shape
- binary avatar/media upload behavior

## 9. FINAL ASSERTION

- `app.auth_subjects` is the canonical application subject authority for
  onboarding subject state, app-level role subject fields, and app-level admin
  subject fields.
- This contract defines field authority and mutation execution only.
- Post-auth routing authority belongs only to `onboarding_entry_authority_contract.md` through `GET /entry-state`.
- Teacher rights are admin-only.
- Admin bootstrap is operator-controlled only.
- Teacher-request lifecycle is eliminated.
