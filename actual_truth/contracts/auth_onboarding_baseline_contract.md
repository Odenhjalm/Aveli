# Auth + Onboarding Baseline Contract

## STATUS

ACTIVE

This contract defines the exact physical baseline objects required for canonical Auth + Onboarding behavior.
This contract composes with:

- `auth_onboarding_contract.md`
- `onboarding_teacher_rights_contract.md`
- `profile_projection_contract.md`

## 1. REQUIRED OBJECTS

The following physical objects are required:

- schema `auth`
- table `auth.users`
- table `app.auth_subjects`
- table `app.profiles`
- table `app.refresh_tokens`
- table `app.auth_events`
- table `app.admin_bootstrap_state`
- function `app.bootstrap_first_admin(target_user_id uuid)`

## 2. REQUIRED OBJECT SEMANTICS

### `auth.users`

- owns identity, credentials, and canonical email-verification truth
- is external auth substrate, not business-domain projection

### `app.auth_subjects`

- is the canonical application subject authority for:
  - onboarding subject state
  - app-level role subject fields
  - app-level admin subject fields
- owns:
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`
- valid onboarding state values for the ordinary/referral onboarding chain are:
  - `incomplete`
  - `welcome_pending`
  - `completed`

### `app.profiles`

- owns only:
  - `user_id`
  - `display_name`
  - `bio`
  - `avatar_media_id`
  - `created_at`
  - `updated_at`
- supports projection persistence for onboarding-collected `display_name` and
  optional `bio` under the canonical create-profile surface
- supports media-mediated avatar attachment through `avatar_media_id` without
  moving media authority into Auth + Onboarding

### `app.refresh_tokens`

- required minimum fields:
  - `jti`
  - `user_id`
  - `token_hash`
  - `issued_at`
  - `expires_at`
  - `last_used_at`
  - `rotated_at`
  - `revoked_at`
- owns refresh-token persistence, rotation lineage, and revocation state

### `app.auth_events`

- required minimum fields:
  - `event_id`
  - `actor_user_id`
  - `subject_user_id`
  - `event_type`
  - `metadata`
  - `created_at`
- owns canonical audit/event persistence for Auth + Onboarding mutations

Required event families:

- `admin_bootstrap_consumed`
- `onboarding_completed`
- `teacher_role_granted`
- `teacher_role_revoked`

### `app.admin_bootstrap_state`

- owns one-time first-admin bootstrap availability
- MUST support exactly one logical bootstrap key for the first-admin grant
- MUST record whether bootstrap has been consumed

### `app.bootstrap_first_admin(target_user_id uuid)`

- is the only canonical mutation surface for establishing the first admin
- is operator-controlled only
- MUST set `app.auth_subjects.is_admin = true` for an existing `auth.users.id`
- MUST mark bootstrap as consumed in `app.admin_bootstrap_state`
- MUST record `admin_bootstrap_consumed` in `app.auth_events`
- MUST NOT be exposed as a public app-runtime route

## OPERATOR EXECUTION ACCESS

- Operator-controlled functions (such as `app.bootstrap_first_admin`) MUST:
  - NOT be callable by:
    - `public`
    - `anon`
    - `authenticated`
  - MAY be callable by:
    - `service_role`
    - direct SQL execution by operator

- `service_role` access is strictly an operator/tooling channel and MUST NOT:
  - be exposed through application runtime routes
  - be used as domain authority
  - be used by frontend clients

- Allowing `service_role` execution does not change authority ownership:
  - backend remains the only runtime authority
  - `service_role` is an execution mechanism only

## 3. OPTIONAL OBJECTS

The following remain optional for Auth + Onboarding:

- additional indexes that do not redefine authority
- additional views that do not redefine authority
- storage substrate required only by a separate media contract

## 4. FORBIDDEN OBJECTS AND DEPENDENCIES

The following are forbidden as Auth + Onboarding requirements:

- `app.certificates`
- `app.teacher_approvals`
- any `teacher_request` or pending teacher-queue table
- a persisted `photo_url` field in `app.profiles`
- `app.media_objects` or any avatar/media table as a prerequisite for Auth + Onboarding alignment
- runtime schema introspection as a replacement for baseline truth

## 5. FINAL ASSERTION

- Auth + Onboarding baseline truth is limited to the objects named in this contract.
- `app.auth_subjects` remains the canonical application subject authority.
- Any implementation dependency outside this set is either optional by explicit contract or drift.
